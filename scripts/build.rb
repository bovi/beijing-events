#!/usr/bin/env ruby
# frozen_string_literal: true

# Regenerates the README event tables, calendar/events.ics and the past/ archive.
require "fileutils"
require_relative "../lib/beijing_events"

START_MARK = "<!-- EVENTS:START -->"
END_MARK = "<!-- EVENTS:END -->"
ADD_URL = "#{BeijingEvents::REPO_URL}/issues/new?template=new-event.yml"

def cell(text) = text.to_s.gsub(/\s+/, " ").gsub("|", "\\|").strip

def link(event)
  title = cell(event.title).gsub(/[\[\]]/) { |c| "\\#{c}" }
  "[#{title}](#{event.url.gsub(' ', '%20').gsub(')', '%29')})"
end

def when_text(event, today)
  format = event.date.year == today.year ? "%a %b %-d" : "%a %b %-d, %Y"
  text = event.date.strftime(format)
  if event.end_date != event.date
    text += " – #{event.end_date.strftime(event.end_date.month == event.date.month ? '%-d' : '%b %-d')}"
  end
  text += ", #{event.time}" if event.time
  text
end

def where(event)
  return cell(event.location) unless event.online? && !event.location.match?(/online/i)

  "#{cell(event.location)} (+ online)"
end

def price(event)
  value = event.price.to_s
  value.casecmp?("free") ? "Free" : cell(value)
end

def table(events, today)
  rows = events.map do |e|
    "| #{when_text(e, today)} | #{link(e)} | #{where(e)} | #{e.categories.join(', ')} | " \
      "#{e.languages.map(&:upcase).join('/')} | #{price(e)} |"
  end
  ["| When | Event | Where | Topics | Lang | Price |", "|---|---|---|---|---|---|", *rows].join("\n")
end

def readme_block(upcoming, today)
  return "_No upcoming events yet. [Add the first one!](#{ADD_URL})_" if upcoming.empty?

  week, rest = upcoming.partition { |e| e.date <= today + 6 }
  month, later = rest.partition { |e| e.date <= today + 30 }
  [["Next 7 days", week], ["Next 30 days", month], ["Later", later]].filter_map do |heading, events|
    "### #{heading}\n\n#{table(events, today)}" if events.any?
  end.join("\n\n")
end

def ics_text(text) = text.to_s.gsub(/[\\;,]/) { |c| "\\#{c}" }.gsub(/\r?\n/) { "\\n" }

def fold(line)
  out = +""
  current = +""
  line.each_char do |char|
    if current.bytesize + char.bytesize > 73
      out << current << "\r\n "
      current = +""
    end
    current << char
  end
  out << current
end

def beijing_time(date, hour_min)
  hour, min = hour_min.split(":").map(&:to_i)
  Time.new(date.year, date.month, date.day, hour, min, 0, "+08:00").utc
end

def ics_event(event)
  utc = ->(time) { time.strftime("%Y%m%dT%H%M%SZ") }
  lines = ["BEGIN:VEVENT", "UID:#{event.id}@beijing-events", "DTSTAMP:#{event.date.strftime('%Y%m%d')}T000000Z"]
  if event.time
    from, to = event.time.split("-")
    starts = beijing_time(event.date, from)
    ends = beijing_time(event.end_date, to || from)
    ends += 2 * 3600 unless to
    ends += 24 * 3600 if ends <= starts
    lines << "DTSTART:#{utc.call(starts)}" << "DTEND:#{utc.call(ends)}"
  else
    lines << "DTSTART;VALUE=DATE:#{event.date.strftime('%Y%m%d')}"
    lines << "DTEND;VALUE=DATE:#{(event.end_date + 1).strftime('%Y%m%d')}"
  end
  lines << "SUMMARY:#{ics_text(event.title)}"
  lines << "LOCATION:#{ics_text([event.location, event.address].compact.join(', '))}"
  lines << "URL:#{event.url}"
  lines << "DESCRIPTION:#{ics_text([event.description, event.url].compact.join("\n\n"))}"
  lines << "CATEGORIES:#{event.categories.map { |c| ics_text(c) }.join(',')}"
  lines << "END:VEVENT"
end

def calendar(events)
  lines = ["BEGIN:VCALENDAR", "VERSION:2.0", "PRODID:-//beijing-events//EN", "CALSCALE:GREGORIAN",
           "X-WR-CALNAME:Beijing Tech Events", "X-WR-TIMEZONE:Asia/Shanghai"]
  events.each { |event| lines.concat(ics_event(event)) }
  lines << "END:VCALENDAR"
  lines.map { |line| fold(line) }.join("\r\n") + "\r\n"
end

today = BeijingEvents.today
events = BeijingEvents.all.sort_by { |e| [e.date, e.time.to_s, e.title.downcase] }
upcoming, past = events.partition { |e| e.end_date >= today }

readme_path = File.join(BeijingEvents::ROOT, "README.md")
readme = File.read(readme_path)
abort "README.md is missing the #{START_MARK} / #{END_MARK} markers" unless readme.include?(START_MARK) && readme.include?(END_MARK)
readme = readme.sub(/#{Regexp.escape(START_MARK)}.*#{Regexp.escape(END_MARK)}/m) do
  "#{START_MARK}\n#{readme_block(upcoming, today)}\n#{END_MARK}"
end
File.write(readme_path, readme)

calendar_dir = File.join(BeijingEvents::ROOT, "calendar")
FileUtils.mkdir_p(calendar_dir)
File.write(File.join(calendar_dir, "events.ics"), calendar(events))

past_dir = File.join(BeijingEvents::ROOT, "past")
FileUtils.rm_f(Dir.glob(File.join(past_dir, "????-??.md")))
past.group_by { |e| e.date.strftime("%Y-%m") }.each do |month, month_events|
  FileUtils.mkdir_p(past_dir)
  heading = "# Past events: #{month_events.first.date.strftime('%B %Y')}"
  File.write(File.join(past_dir, "#{month}.md"), "#{heading}\n\n#{table(month_events, Date.new(0))}\n")
end

puts "Built #{upcoming.size} upcoming and #{past.size} past event(s)."
