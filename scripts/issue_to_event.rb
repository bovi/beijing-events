#!/usr/bin/env ruby
# frozen_string_literal: true

# Turns a "new event" issue form (ISSUE_BODY, ISSUE_NUMBER) into an event file.
# On success prints the file path (and writes it to GITHUB_OUTPUT); on failure writes issue_errors.md.
require "fileutils"
require_relative "../lib/beijing_events"

FIELDS = {
  "Event title" => "title",
  "Date" => "date",
  "End date" => "end_date",
  "Time" => "time",
  "Location" => "location",
  "Address" => "address",
  "Online" => "online",
  "Language" => "language",
  "Category" => "category",
  "Price" => "price",
  "Link" => "url",
  "Organizer" => "organizer",
  "Description" => "description"
}.freeze
LANGUAGE_NAMES = { "English" => "en", "中文" => "zh" }.freeze

def fail_with(errors)
  File.write("issue_errors.md", <<~MD)
    Thanks for suggesting an event! A few details need fixing before it can be added:

    #{errors.map { |e| "- #{e}" }.join("\n")}

    Please edit this issue. The check runs again automatically.
  MD
  warn errors
  exit 1
end

number = ENV.fetch("ISSUE_NUMBER", "")
abort "ISSUE_NUMBER must be a number" unless number.match?(/\A\d+\z/)

answers = ENV.fetch("ISSUE_BODY", "").gsub("\r\n", "\n").split(/^### /).drop(1).to_h do |section|
  label, value = section.split("\n", 2)
  [label.strip, value.to_s.strip]
end

data = {}
FIELDS.each do |label, key|
  value = answers[label]
  next if value.nil? || value.empty? || value == "_No response_"

  data[key] =
    case key
    when "date", "end_date" then (Date.iso8601(value) rescue value)
    when "online" then value == "Yes"
    when "language" then value.split(/,\s*/).map { |v| LANGUAGE_NAMES.fetch(v, v) }
    when "category" then value.split(/,\s*/)
    when "description" then value.gsub(/\s+/, " ")
    else value
    end
end

fail_with(["'Date' must look like 2026-11-15"]) unless data["date"].is_a?(Date)

slug = data["title"].to_s.downcase.gsub(/[^a-z0-9]+/, "-").gsub(/\A-+|-+\z/, "")[0, 50].sub(/-+\z/, "")
slug = "event-#{number}" if slug.empty?
path = File.join(BeijingEvents::EVENTS_DIR, data["date"].year.to_s, "#{data['date'].iso8601}-#{slug}.yml")

errors = BeijingEvents.validate(path, data)
errors << "the event is in the past" if errors.empty? && (data["end_date"] || data["date"]) < BeijingEvents.today
duplicate = BeijingEvents.all.find do |e|
  e.path != path && BeijingEvents.duplicate_key(e.data) == BeijingEvents.duplicate_key(data)
end
errors << "this event already exists: #{BeijingEvents.relative(duplicate.path)}" if duplicate
fail_with(errors) if errors.any?

FileUtils.mkdir_p(File.dirname(path))
File.write(path, data.to_yaml.delete_prefix("---\n"))
rel = BeijingEvents.relative(path)
File.write(ENV["GITHUB_OUTPUT"], "path=#{rel}\n", mode: "a") if ENV["GITHUB_OUTPUT"]
puts rel
