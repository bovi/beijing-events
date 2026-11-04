#!/usr/bin/env ruby
# frozen_string_literal: true

# Usage: ruby scripts/validate.rb [changed event files...]
# Validates all events; files given as arguments must additionally not be in the past.
require_relative "../lib/beijing_events"

today = BeijingEvents.today
changed = ARGV.map { |path| File.expand_path(path) }
problems = Hash.new { |hash, key| hash[key] = [] }
seen = {}

Dir.glob(File.join(BeijingEvents::EVENTS_DIR, "**", "*")).sort.each do |path|
  next if File.directory?(path) || File.basename(path) == "_template.yml"
  next if File.fnmatch?(BeijingEvents::EVENTS_GLOB, path)

  problems[BeijingEvents.relative(path)] << "event files belong in events/YYYY/ and must end in .yml"
end

Dir.glob(BeijingEvents::EVENTS_GLOB).sort.each do |path|
  rel = BeijingEvents.relative(path)
  begin
    data = BeijingEvents.read(path)
  rescue Psych::Exception => e
    problems[rel] << "invalid YAML: #{e.message}"
    next
  end

  errors = BeijingEvents.validate(path, data)
  problems[rel].concat(errors)
  next unless errors.empty?

  key = BeijingEvents.duplicate_key(data)
  if seen[key]
    problems[rel] << "looks like a duplicate of #{seen[key]}"
  else
    seen[key] = rel
  end

  problems[rel] << "event is in the past" if changed.include?(path) && (data["end_date"] || data["date"]) < today
end

problems.reject! { |_, errors| errors.empty? }
if problems.empty?
  puts "All #{Dir.glob(BeijingEvents::EVENTS_GLOB).size} event file(s) are valid."
  exit
end

problems.each do |file, errors|
  errors.each do |error|
    puts ENV["GITHUB_ACTIONS"] ? "::error file=#{file}::#{error}" : "#{file}: #{error}"
  end
end
exit 1
