#!/usr/bin/env ruby
# frozen_string_literal: true

# Daily AI event discovery, run by .github/workflows/discover-events.yml.
#
#   ruby scripts/discover_events.rb prompt   Writes tmp/discovery_prompt.md for Copilot CLI,
#                                            including a digest of all known events.
#   ruby scripts/discover_events.rb issues   Reads tmp/discovered_events.json (written by
#                                            Copilot CLI), drops duplicates and unverifiable
#                                            entries, and opens one "new-event" issue per
#                                            remaining event so the normal issue -> PR
#                                            pipeline takes over.
require "json"
require "net/http"
require "open3"
require "uri"
require "fileutils"
require_relative "../lib/beijing_events"

TMP_DIR = File.join(BeijingEvents::ROOT, "tmp")
PROMPT_PATH = File.join(TMP_DIR, "discovery_prompt.md")
RESULTS_PATH = File.join(TMP_DIR, "discovered_events.json")
MAX_ISSUES = ENV.fetch("MAX_ISSUES", "5").to_i
HORIZON_DAYS = 90
DRY_RUN = ENV["DRY_RUN"] == "true"

# Issue form labels in display order; must match .github/ISSUE_TEMPLATE/new-event.yml
# and the FIELDS table in scripts/issue_to_event.rb.
FIELD_LABELS = {
  "title" => "Event title",
  "date" => "Date",
  "end_date" => "End date",
  "time" => "Time",
  "location" => "Location",
  "address" => "Address",
  "online" => "Online",
  "language" => "Language",
  "category" => "Category",
  "price" => "Price",
  "url" => "Link",
  "organizer" => "Organizer",
  "description" => "Description"
}.freeze
LANGUAGE_NAMES = { "en" => "English", "zh" => "中文" }.freeze

def normalize_url(url)
  uri = URI.parse(url.to_s.strip)
  host = uri.host.to_s.downcase.delete_prefix("www.")
  query = URI.decode_www_form(uri.query.to_s).reject { |key, _| key.start_with?("utm_") }
  "#{host}#{uri.path.to_s.chomp('/')}#{query.any? ? "?#{URI.encode_www_form(query)}" : ''}"
rescue URI::Error
  url.to_s.strip.downcase
end

# Events already tracked as issues (any state), parsed from the issue form body.
def tracked_issues
  out, status = Open3.capture2("gh", "issue", "list", "--label", "new-event", "--state", "all",
                               "--limit", "200", "--json", "title,body")
  abort "could not list existing issues with gh" unless status.success?
  JSON.parse(out).map do |issue|
    answers = issue["body"].to_s.gsub("\r\n", "\n").split(/^### /).drop(1).to_h do |section|
      label, value = section.split("\n", 2)
      [label.strip, value.to_s.strip]
    end
    { "title" => answers["Event title"] || issue["title"].to_s.sub(/\A\[Event\]\s*/, ""),
      "date" => (Date.iso8601(answers["Date"].to_s) rescue answers["Date"]),
      "url" => answers["Link"] }
  end
end

def known_entries = BeijingEvents.all.map(&:data) + tracked_issues

def write_prompt
  today = BeijingEvents.today
  digest = known_entries.sort_by { |e| e["date"].to_s }
                        .map { |e| "- #{e['date']} | #{e['title']} | #{e['url']}" }.join("\n")
  FileUtils.mkdir_p(TMP_DIR)
  File.write(PROMPT_PATH, <<~PROMPT)
    You are the daily event scout for the beijing-events repository.
    Today is #{today.iso8601} (Beijing time).

    ## Goal

    Find tech events (meetups, conferences, hackathons, workshops, developer salons)
    taking place in Beijing between #{today.iso8601} and #{(today + HORIZON_DAYS).iso8601}
    that are NOT in the known list below, and save them to `tmp/discovered_events.json`.

    ## How to search

    Use web search and open promising pages with web_fetch. Run several queries in
    English and Chinese, for example:
    - "Beijing tech conference #{today.strftime('%B %Y')}", "Beijing developer meetup", "Beijing hackathon"
    - "北京 技术大会", "北京 开发者 活动", "北京 黑客松", "北京 技术沙龙", "北京 meetup"
    Also try event listing pages such as:
    - https://www.meetup.com/find/?location=cn--beijing&keywords=technology
    - https://gdg.community.dev/gdg-beijing/
    - https://www.huodongxing.com/events?city=北京
    - conference sites (QCon, ArchSummit, PyCon China, CNCF/KCD, GOSIM, juejin.cn, segmentfault.com, oschina.net)
    Verify every event by opening its own page with web_fetch. Never invent events or URLs.

    ## Known events — do NOT report these again

    #{digest}

    ## Output

    Write a single file `tmp/discovered_events.json` containing a JSON array
    (write `[]` if you found nothing new). One object per event:

    {
      "title": "English Title / 中文标题",        // bilingual if available, max 100 chars
      "date": "YYYY-MM-DD",                       // start date, required
      "end_date": "YYYY-MM-DD",                   // optional, multi-day events only
      "time": "19:00-21:30",                      // optional, Beijing time, 24h
      "location": "Venue, District / 中文地点",    // required
      "address": "街道地址",                       // optional
      "online": false,                            // optional, true if there is an online stream
      "language": ["en", "zh"],                   // optional
      "category": ["ai"],                         // required, subset of: #{BeijingEvents::CATEGORIES.join(', ')}
      "price": "Free / 免费",                      // optional
      "url": "https://...",                       // required, the event page you actually opened
      "organizer": "...",                         // optional
      "description": "One or two sentences.",     // optional, max 300 chars
      "source": "where you found it"              // search query or listing page URL
    }

    ## Rules

    - Only real, verified, upcoming events located in Beijing. Skip online-only events
      unless they are organized by a Beijing community.
    - Skip anything that matches a known event above (same page, or same title and date).
    - At most 10 events. Quality over quantity.
    - Only write `tmp/discovered_events.json`. Do not modify any other file, do not run
      shell commands, do not create issues or pull requests.
  PROMPT
  puts "wrote #{BeijingEvents.relative(PROMPT_PATH)} (#{known_entries.size} known events)"
end

# The page must exist; sites that block bots (403 etc.) still count as reachable.
def reachable?(url, limit = 5)
  return false if limit.zero?

  uri = URI.parse(url)
  response = Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == "https",
                             open_timeout: 10, read_timeout: 15) do |http|
    http.request_get(uri.request_uri.empty? ? "/" : uri.request_uri,
                     "User-Agent" => "beijing-events-bot (+#{BeijingEvents::REPO_URL})")
  end
  if response.is_a?(Net::HTTPRedirection) && response["location"]
    reachable?(URI.join(url, response["location"]).to_s, limit - 1)
  else
    !%w[404 410].include?(response.code)
  end
rescue StandardError => e
  warn "  #{url}: #{e.class}: #{e.message}"
  false
end

def to_event_data(candidate)
  data = {}
  FIELD_LABELS.each_key do |key|
    value = candidate[key]
    next if value.nil? || value == "" || value == []

    data[key] =
      case key
      when "date", "end_date" then (Date.iso8601(value.to_s) rescue value)
      when "online" then value == true || value == "true"
      when "language", "category" then Array(value).map(&:to_s)
      when "description" then value.to_s.gsub(/\s+/, " ")
      else value.to_s
      end
  end
  data
end

def rejection_reason(data, known_urls, known_keys)
  return "invalid or missing date" unless data["date"].is_a?(Date)
  return "event is in the past" if (data["end_date"].is_a?(Date) ? data["end_date"] : data["date"]) < BeijingEvents.today
  return "more than #{HORIZON_DAYS * 2} days away" if data["date"] > BeijingEvents.today + HORIZON_DAYS * 2
  return "already listed (same link)" if known_urls.include?(normalize_url(data["url"]))
  return "already listed (same title and date)" if known_keys.include?(BeijingEvents.duplicate_key(data))

  slug = data["title"].to_s.downcase.gsub(/[^a-z0-9]+/, "-").gsub(/\A-+|-+\z/, "")[0, 50].sub(/-+\z/, "")
  slug = "event" if slug.empty?
  path = File.join(BeijingEvents::EVENTS_DIR, data["date"].year.to_s, "#{data['date'].iso8601}-#{slug}.yml")
  errors = BeijingEvents.validate(path, data)
  return "invalid event data: #{errors.join('; ')}" if errors.any?
  return "event page is not reachable" unless reachable?(data["url"])

  nil
end

def issue_body(data, source)
  sections = FIELD_LABELS.filter_map do |key, label|
    value = data[key]
    next if value.nil?

    text =
      case key
      when "date", "end_date" then value.iso8601
      when "online" then value ? "Yes" : "No"
      when "language" then value.map { |v| LANGUAGE_NAMES.fetch(v, v) }.join(", ")
      when "category" then value.join(", ")
      else value.to_s
      end
    "### #{label}\n\n#{text}"
  end
  sections << "### Source\n\nFound automatically by the daily event discovery workflow. #{source}".strip
  sections.join("\n\n")
end

def create_issues
  abort "#{BeijingEvents.relative(RESULTS_PATH)} is missing - did the discovery step run?" unless File.exist?(RESULTS_PATH)
  candidates = JSON.parse(File.read(RESULTS_PATH))
  abort "#{BeijingEvents.relative(RESULTS_PATH)} must contain a JSON array" unless candidates.is_a?(Array)

  known = known_entries
  known_urls = known.filter_map { |e| normalize_url(e["url"]) unless BeijingEvents.blank?(e["url"]) }
  known_keys = known.map { |e| BeijingEvents.duplicate_key(e) }
  summary = []
  created = 0

  candidates.sort_by { |c| c["date"].to_s }.each do |candidate|
    data = to_event_data(candidate)
    name = "#{data['date']} #{data['title']}".strip
    if created >= MAX_ISSUES
      summary << "- skipped (max #{MAX_ISSUES} issues per run): #{name}"
      next
    end
    if (reason = rejection_reason(data, known_urls, known_keys))
      summary << "- skipped (#{reason}): #{name}"
      next
    end

    known_urls << normalize_url(data["url"])
    known_keys << BeijingEvents.duplicate_key(data)
    created += 1
    if DRY_RUN
      summary << "- would create issue: #{name} (#{data['url']})"
      next
    end

    body_path = File.join(TMP_DIR, "issue_body.md")
    File.write(body_path, issue_body(data, candidate["source"].to_s))
    out, status = Open3.capture2("gh", "issue", "create", "--title", "[Event] #{data['title']}",
                                 "--label", "new-event", "--label", "ai-discovered",
                                 "--body-file", body_path)
    abort "gh issue create failed for #{name}" unless status.success?
    summary << "- created #{out.strip}: #{name}"
  end

  summary << "- nothing new found" if summary.empty?
  report = "## Event discovery#{' (dry run)' if DRY_RUN}\n\n#{summary.join("\n")}\n"
  puts report
  File.write(ENV["GITHUB_STEP_SUMMARY"], report, mode: "a") if ENV["GITHUB_STEP_SUMMARY"]
end

case ARGV.first
when "prompt" then write_prompt
when "issues" then create_issues
else abort "usage: ruby scripts/discover_events.rb prompt|issues"
end
