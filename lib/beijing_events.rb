# frozen_string_literal: true

# Shared loading and validation for event files. Ruby standard library only.
require "yaml"
require "date"

module BeijingEvents
  ROOT = File.expand_path("..", __dir__)
  EVENTS_DIR = File.join(ROOT, "events")
  EVENTS_GLOB = File.join(EVENTS_DIR, "*", "*.yml")
  REPO_URL = "https://github.com/bovi/beijing-events"

  CATEGORIES = %w[ai web mobile cloud devops data security hardware open-source startup design gaming other].freeze
  LANGUAGES = %w[en zh].freeze
  REQUIRED = %w[title date location url category].freeze
  OPTIONAL = %w[end_date time address online language price organizer description].freeze
  TEXT_FIELDS = %w[title location address organizer description].freeze

  FILE_NAME = /\A(\d{4}-\d{2}-\d{2})-[a-z0-9]+(?:-[a-z0-9]+)*\.yml\z/
  HOUR_MIN = /(?:[01]\d|2[0-3]):[0-5]\d/
  TIME = /\A#{HOUR_MIN}(?:-#{HOUR_MIN})?\z/

  class Event
    attr_reader :path, :data

    def initialize(path, data)
      @path = path
      @data = data
    end

    def id = File.basename(path, ".yml")
    def title = data["title"].to_s.strip
    def date = data["date"]
    def end_date = data["end_date"] || date
    def time = data["time"]
    def url = data["url"].to_s
    def location = data["location"].to_s
    def address = data["address"]
    def online? = data["online"] == true
    def categories = Array(data["category"])
    def languages = Array(data["language"])
    def price = data["price"]
    def organizer = data["organizer"]
    def description = data["description"]
  end

  module_function

  def today = (Time.now.utc + 8 * 3600).to_date

  def read(path) = YAML.safe_load_file(path, permitted_classes: [Date])

  def all = Dir.glob(EVENTS_GLOB).sort.map { |path| Event.new(path, read(path)) }

  def relative(path) = File.expand_path(path).delete_prefix("#{ROOT}/")

  def duplicate_key(data) = [data["date"], data["title"].to_s.downcase.gsub(/[^\p{Alnum}]/, "")]

  def validate(path, data)
    return ["file must contain fields like 'title: ...' (see events/_template.yml)"] unless data.is_a?(Hash)

    errors = []
    match = FILE_NAME.match(File.basename(path))
    errors << "file name must look like YYYY-MM-DD-short-title.yml (lowercase letters, digits, dashes)" unless match

    unknown = data.keys - REQUIRED - OPTIONAL
    errors << "unknown field(s): #{unknown.join(', ')}" if unknown.any?
    REQUIRED.each { |key| errors << "missing required field '#{key}'" if blank?(data[key]) }

    %w[date end_date].each do |key|
      next if data[key].nil? || data[key].is_a?(Date)

      errors << "'#{key}' must be a date like 2026-11-15"
    end

    date = data["date"]
    if date.is_a?(Date)
      errors << "file name must start with the event date #{date.iso8601}" if match && match[1] != date.iso8601
      errors << "file must be in events/#{date.year}/" unless File.basename(File.dirname(path)) == date.year.to_s
      end_date = data["end_date"]
      errors << "'end_date' must not be before 'date'" if end_date.is_a?(Date) && end_date < date
    end

    # Unquoted 19:00 is parsed by YAML as a number, so it fails here too.
    if !data["time"].nil? && !(data["time"].is_a?(String) && TIME.match?(data["time"]))
      errors << %('time' must be quoted and look like "19:00" or "19:00-21:30")
    end

    if !blank?(data["url"]) && !data["url"].to_s.match?(%r{\Ahttps?://\S+\z})
      errors << "'url' must start with http:// or https://"
    end

    check_list(errors, data, "category", CATEGORIES)
    check_list(errors, data, "language", LANGUAGES)
    errors << "'online' must be true or false" unless [nil, true, false].include?(data["online"])

    TEXT_FIELDS.each do |key|
      errors << "'#{key}' must be text" unless data[key].nil? || data[key].is_a?(String)
    end
    errors << "'price' must be text like free or ¥50" unless data["price"].nil? || data["price"].is_a?(String) || data["price"].is_a?(Numeric)
    errors << "'title' must be at most 100 characters" if data["title"].is_a?(String) && data["title"].length > 100
    errors << "'description' must be at most 300 characters" if data["description"].is_a?(String) && data["description"].length > 300
    errors
  end

  def check_list(errors, data, key, allowed)
    return if data[key].nil?

    values = Array(data[key])
    bad = values.reject { |value| allowed.include?(value) }
    return if bad.empty? && values.any?

    errors << "'#{key}' has invalid value(s) #{bad.join(', ')} - allowed: #{allowed.join(', ')}"
  end

  def blank?(value)
    value.nil? || (value.respond_to?(:empty?) && value.empty?) || value.to_s.strip.empty?
  end
end
