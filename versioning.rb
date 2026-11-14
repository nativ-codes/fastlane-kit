# Pure version math, no fastlane dependency, so it is unit-testable.
#
# Versions file (one per platform, committed): fastlane/versioning/.<platform>-versions
#   version=1.4.2          <- the real release train, shipped by prod
#   build=57               <- prod build counter
#   stage_version=999.99   <- fixed version name for every other stage
#   stage_build=12         <- stage build counter (iOS only, see separate_stage_counter)
#
# iOS only needs build numbers unique within one version name, so stage (999.99) counts on its own.
# Android needs versionCode to grow across ALL uploads of a package, so there stage and prod share build.
# shortcut: one counter set per platform file, i.e. all stages ship to the same store app; per-app keys if that changes.
require "json"

module KitVersioning
  def self.read(path)
    return {} unless File.exist?(path)
    File.readlines(path, chomp: true).reject { |l| l.strip.empty? }.to_h { |l| l.split("=", 2).map(&:strip) }
  end

  def self.write(path, store)
    File.write(path, store.map { |k, v| "#{k}=#{v}" }.join("\n") + "\n")
  end

  # Returns [new_store, version_to_ship, build_number].
  # release: true for prod (ships the train, optionally bumped); false ships stage_version, never touching the train.
  def self.next(store, release:, bump: nil, separate_stage_counter: false)
    bump = nil if bump.to_s.strip.empty?
    build_key = !release && separate_stage_counter ? "stage_build" : "build"
    build = store.fetch(build_key, "0").to_i + 1

    unless release
      raise ArgumentError, "bump:#{bump} is only allowed on stage:prod" if bump
      stage_version = store.fetch("stage_version", "999.99")
      return [store.merge("stage_version" => stage_version, build_key => build.to_s), stage_version, build]
    end

    version = store.fetch("version", "1.0.0")
    version = bumped(version, bump) if bump
    [store.merge("version" => version, build_key => build.to_s), version, build]
  end

  # Writes the shipped version into app.json so `expo prebuild` stamps it on every iOS target
  # (app + extensions). shortcut: app.json only; app.config.js projects need their own version source.
  def self.write_app_json(path, version:, build:)
    json = JSON.parse(File.read(path))
    expo = json["expo"] or raise ArgumentError, "#{path} has no \"expo\" key"
    expo["version"] = version
    (expo["ios"] ||= {})["buildNumber"] = build.to_s
    File.write(path, JSON.pretty_generate(json) + "\n")
  end

  def self.bumped(version, type)
    major, minor, patch = version.split(".").map(&:to_i)
    case type.to_s
    when "major" then "#{major + 1}.0.0"
    when "minor" then "#{major}.#{minor + 1}.0"
    when "patch" then "#{major}.#{minor}.#{patch.to_i + 1}"
    else raise ArgumentError, "Invalid bump: #{type} (major|minor|patch)"
    end
  end
end
