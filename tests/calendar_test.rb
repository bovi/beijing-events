# frozen_string_literal: true

# Standard-library-only integration tests. Build in isolation, not in the checkout.
require "tmpdir"
require "fileutils"
require "rbconfig"
require "yaml"
require "date"

root = File.expand_path("..", __dir__)
Dir.mktmpdir("beijing-calendar-test") do |dir|
  %w[lib scripts].each { |name| FileUtils.cp_r(File.join(root, name), dir) }
  File.write(File.join(dir, "README.md"), "<!-- EVENTS:START -->\n<!-- EVENTS:END -->\n")
  FileUtils.mkdir_p(File.join(dir, "events", "2026"))
  fixtures = {
    "start-only" => { "time" => "13:30" },
    "range" => { "time" => "13:30-15:30" },
    "overnight" => { "time" => "23:00-01:00" },
    "multi-day" => { "time" => "09:00-17:00", "end_date" => Date.new(2026, 11, 12) },
    "multi-start-only" => { "time" => "13:30", "end_date" => Date.new(2026, 11, 12) },
    "all-day" => {},
    "multi-all-day" => { "end_date" => Date.new(2026, 11, 12) }
  }
  fixtures.each do |name, extra|
    data = { "title" => name, "date" => Date.new(2026, 11, 11), "location" => "Beijing",
             "url" => "https://example.com", "category" => ["ai"] }.merge(extra)
    File.write(File.join(dir, "events", "2026", "2026-11-11-#{name}.yml"), data.to_yaml)
  end
  abort "Build failed" unless system(RbConfig.ruby, File.join(dir, "scripts", "build.rb"))
  ics = File.read(File.join(dir, "calendar", "events.ics")).gsub(/\r?\n[ \t]/, "")
  entries = ics.scan(/BEGIN:VEVENT\r?\n.*?END:VEVENT/m).to_h do |entry|
    [entry[/^SUMMARY:(.*)$/, 1].strip, entry]
  end
  checks = 0
  assert = lambda do |condition, message|
    raise message unless condition
    checks += 1
  end
  %w[start-only multi-start-only].each do |name|
    event = entries.fetch(name)
    assert.call(event.include?("DTSTART:20261111T053000Z"), "#{name}: preserve 13:30 Beijing start")
    assert.call(!event.include?("DTEND") && !event.include?("DURATION"), "#{name}: no invented finish")
    assert.call(event.include?("End time unconfirmed / 结束时间未确认"), "#{name}: bilingual uncertainty note")
  end
  {
    "range" => "DTEND:20261111T073000Z",
    "overnight" => "DTEND:20261111T170000Z",
    "multi-day" => "DTEND:20261112T090000Z",
    "all-day" => "DTEND;VALUE=DATE:20261112",
    "multi-all-day" => "DTEND;VALUE=DATE:20261113"
  }.each do |name, ending|
    assert.call(entries.fetch(name).include?(ending), "#{name}: preserve explicit/end-date semantics")
    assert.call(!entries.fetch(name).include?("End time unconfirmed"), "#{name}: no spurious timing note")
  end
  puts "Passed #{checks} calendar assertions."
end
