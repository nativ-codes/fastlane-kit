# Shared deploy lanes. Installed as a package and imported from <project>/fastlane/Fastfile:
#   import("../node_modules/fastlane-kit/Fastfile")
#
#   fastlane deploy platform:ios stage:dev
#   fastlane deploy platform:android stage:prod bump:minor
#   fastlane certs stage:dev   # one-time: create missing iOS profiles in the match repo
#   fastlane play_key          # one-time: create the Play service account JSON key (gcloud)
#
# Everything else is in <project>/fastlane/ too:
#   .env.deploy + .env.<stage>      config (gitignored, see node_modules/fastlane-kit/.env.example)
#   keys/                           key files (gitignored)
#   versioning/.<platform>-versions committed
require "dotenv"
require_relative "versioning"

skip_docs # fastlane would otherwise write a README.md into fastlane/ on every run

def kit_env!(name)
  ENV[name].to_s.empty? ? UI.user_error!("Missing #{name} in .env.deploy or .env.<stage>") : ENV[name]
end

# Loads fastlane/.env.deploy then fastlane/.env.<stage>. Returns [project root, keys dir].
def kit_load_env!(stage)
  UI.user_error!("stage is required, e.g. stage:dev") if stage.to_s.empty?
  # Lane bodies run inside <project>/fastlane.
  dir = Dir.pwd
  root = File.expand_path("..")
  keys = ENV["KIT_KEYS_DIR"] || File.join(dir, "keys")
  env_files = [".env.deploy", ".env.#{stage}"].map { |f| File.join(dir, f) }.select { |f| File.exist?(f) }
  UI.user_error!("No .env.deploy or .env.#{stage} found in #{dir}") if env_files.empty?
  Dotenv.overload(*env_files)
  [root, keys]
end

# Target name => bundle id. Extension ids derive from the app id, so each stage gets its own
# (Apple requires an extension id to be prefixed by its app's id).
def kit_ios_targets(app_target, bundle_id)
  targets = { app_target => bundle_id }
  ENV["IOS_EXTENSIONS"].to_s.split(",").each do |entry|
    target, suffix = entry.split(":", 2).map(&:strip)
    UI.user_error!("IOS_EXTENSIONS entry '#{entry}' must be Target:suffix") if suffix.to_s.empty?
    targets[target] = "#{bundle_id}.#{suffix}"
  end
  targets
end

def kit_asc_api_key(keys)
  app_store_connect_api_key(
    key_id: kit_env!("ASC_KEY_ID"),
    issuer_id: kit_env!("ASC_ISSUER_ID"),
    key_content: ENV["ASC_KEY_CONTENT"],
    key_filepath: ENV["ASC_KEY_CONTENT"] ? nil : File.join(keys, ENV["ASC_KEY_FILE"] || "AuthKey.p8"),
    duration: 1200
  )
end

desc "One-time per stage: create missing iOS distribution cert/profiles in the match repo. Params: stage:<name>"
lane :certs do |options|
  _, keys = kit_load_env!(options[:stage])
  bundle_ids = kit_ios_targets(nil, kit_env!("IOS_BUNDLE_ID")).values
  # Not readonly: reuses the team's existing cert, creates only what is missing. Never use nuke here.
  match(type: "appstore", git_url: kit_env!("MATCH_GIT_URL"), app_identifier: bundle_ids, readonly: false, api_key: kit_asc_api_key(keys))
end

desc "One-time: create a Play service account + JSON key via gcloud. Params: project:<gcp id> (default <app>-fastlane), stage:<name> (default prod)"
lane :play_key do |options|
  # Play keys are shared by all stages; stage only picks which .env.<stage> overrides to load.
  _, keys = kit_load_env!(options[:stage] || "prod")
  UI.user_error!("gcloud not found: brew install --cask gcloud-cli") unless system("command -v gcloud >/dev/null 2>&1")
  project = options[:project] || ENV["PLAY_GCP_PROJECT"] || "#{kit_env!("ANDROID_PACKAGE").split(".").last}-fastlane"
  email = "fastlane@#{project}.iam.gserviceaccount.com"
  file = File.join(keys, ENV["PLAY_JSON_KEY_FILE"] || "play-service-account.json")
  quiet = { out: File::NULL, err: File::NULL }
  run = ->(*cmd) { system("gcloud", *cmd) || UI.user_error!("Failed: gcloud #{cmd.join(" ")}") }

  # system, not sh: login opens a browser and must stay interactive.
  run.call("auth", "login") if `gcloud config get-value account 2>/dev/null`.strip.empty?
  run.call("projects", "create", project) unless system("gcloud", "projects", "describe", project, **quiet)
  run.call("services", "enable", "androidpublisher.googleapis.com", "--project", project)
  unless system("gcloud", "iam", "service-accounts", "describe", email, "--project", project, **quiet)
    run.call("iam", "service-accounts", "create", "fastlane", "--display-name", "fastlane Play uploads", "--project", project)
  end
  if File.exist?(file)
    File.rename(file, "#{file}.old") # keep the previous key instead of overwriting it
    UI.important("Moved existing key to #{file}.old")
  end
  FileUtils.mkdir_p(keys)
  run.call("iam", "service-accounts", "keys", "create", file, "--iam-account", email, "--project", project)

  UI.success("Key written to #{file}")
  UI.important("Now in Play Console > Users and permissions > Invite new user: #{email}")
  UI.important("Grant app access to #{ENV["ANDROID_PACKAGE"]} with release permissions, then verify (may take a few hours):")
  UI.message("  bundle exec fastlane run validate_play_store_json_key json_key:#{file}")
end

# Everything a deploy needs, checked before the slow steps. Returns the ASC api key (iOS).
def kit_preflight!(platform, root, keys, versions_file:, git:)
  missing_tools = (platform == "ios" ? %w[yarn pod xcodebuild] : %w[yarn]).reject { |t| system("command -v #{t} >/dev/null 2>&1") }
  UI.user_error!("Missing tools on PATH: #{missing_tools.join(", ")}") if missing_tools.any?
  if git && !system("git", "-C", File.dirname(versions_file), "ls-files", "--error-unmatch", versions_file, out: File::NULL, err: File::NULL)
    UI.user_error!("#{versions_file} is not committed; commit fastlane/ first or pass skip_git:true")
  end

  if platform == "android"
    %w[ANDROID_PACKAGE ANDROID_KEYSTORE_PASSWORD ANDROID_KEY_ALIAS ANDROID_KEY_PASSWORD].each { |v| kit_env!(v) }
    [ENV["ANDROID_KEYSTORE_FILE"] || "release.keystore", ENV["PLAY_JSON_KEY_FILE"] || "play-service-account.json"].each do |f|
      UI.user_error!("Missing #{File.join(keys, f)}") unless File.exist?(File.join(keys, f))
    end
    UI.success("Preflight ok: android")
    return nil
  end

  %w[IOS_BUNDLE_ID APPLE_TEAM_ID MATCH_GIT_URL MATCH_PASSWORD ASC_KEY_ID ASC_ISSUER_ID].each { |v| kit_env!(v) }
  key_file = File.join(keys, ENV["ASC_KEY_FILE"] || "AuthKey.p8")
  UI.user_error!("Missing #{key_file}") unless ENV["ASC_KEY_CONTENT"] || File.exist?(key_file)
  api_key = kit_asc_api_key(keys)

  # A real API call: proves the key works and the app exists, before building anything.
  bundle_id = ENV["IOS_BUNDLE_ID"]
  Spaceship::ConnectAPI.token = Spaceship::ConnectAPI::Token.from(hash: api_key)
  UI.user_error!("App #{bundle_id} not found in App Store Connect") unless Spaceship::ConnectAPI::App.find(bundle_id)

  # Readonly match fails on an expired/missing cert or profile, and installs them for the build.
  bundle_ids = kit_ios_targets(nil, bundle_id).values
  match(type: "appstore", git_url: ENV["MATCH_GIT_URL"], app_identifier: bundle_ids, readonly: true, api_key: api_key)
  UI.success("Preflight ok: ios (#{bundle_ids.join(", ")})")
  api_key
end

desc "Check everything a deploy needs, without building. Params: platform:ios|android stage:<name> [skip_git:true]"
lane :check do |options|
  platform = options[:platform].to_s
  UI.user_error!("platform must be ios or android") unless %w[ios android].include?(platform)
  root, keys = kit_load_env!(options[:stage])
  kit_preflight!(platform, root, keys, versions_file: File.expand_path("versioning/.#{platform}-versions"), git: options[:skip_git].to_s != "true")
end

# iOS: any stage other than prod ships stage_version from the versions file (<build+1>) to TestFlight only.
#      stage:prod ships the release train, optionally bumped, and attaches the build
#      to the App Store version in App Store Connect (not submitted for review).
desc "Build, sign, version and upload. Params: platform:ios|android stage:<name> [bump:major|minor|patch] [skip_git:true] [skip_upload:true]"
lane :deploy do |options|
  platform = options[:platform].to_s
  stage = options[:stage].to_s
  UI.user_error!("platform must be ios or android") unless %w[ios android].include?(platform)
  root, keys = kit_load_env!(stage)
  # The JS bundle is built inside the native build; the stage must be set before it.
  ENV[ENV["KIT_APP_ENV_VAR"] || "EXPO_PUBLIC_APP_ENV"] = stage

  release = stage == "prod"
  upload = options[:skip_upload].to_s != "true" # skip_upload: run every step up to the built .ipa/.aab, for testing
  app_id = kit_env!(platform == "ios" ? "IOS_BUNDLE_ID" : "ANDROID_PACKAGE")
  versions_file = File.expand_path("versioning/.#{platform}-versions")
  store, version, build = begin
    KitVersioning.next(KitVersioning.read(versions_file), release: release, bump: options[:bump], separate_stage_counter: platform == "ios")
  rescue ArgumentError => e
    UI.user_error!(e.message)
  end
  UI.important("#{platform} #{stage} (#{app_id}): #{version} (#{build})")
  git = upload && options[:skip_git].to_s != "true"
  api_key = kit_preflight!(platform, root, keys, versions_file: versions_file, git: git)

  if platform == "ios"
    kit_ios(root: root, api_key: api_key, bundle_id: app_id, version: version, build: build, release: release, upload: upload)
  else
    kit_android(root: root, keys: keys, package: app_id, version: version, build: build, upload: upload)
  end

  next UI.important("skip_upload: built #{version} (#{build}), nothing uploaded, versions file and git untouched") unless upload

  # Persist only after a successful upload, so failed builds don't burn numbers.
  FileUtils.mkdir_p(File.dirname(versions_file))
  KitVersioning.write(versions_file, store)
  next unless git

  commit_paths = [versions_file]
  commit_paths << File.join(root, "app.json") if platform == "ios"
  git_commit(path: commit_paths, message: "#{stage} version bump #{version} (#{build}) on #{platform}")
  push_to_git_remote
  add_git_tag(tag: "#{stage}_v#{version}_#{build}_#{platform}")
  push_git_tags
end

private_lane :kit_ios do |o|
  root, api_key, bundle_id, version, build = o[:root], o[:api_key], o[:bundle_id], o[:version], o[:build]

  # app.json drives prebuild, which writes version/build into the app and extension targets.
  begin
    KitVersioning.write_app_json(File.join(root, "app.json"), version: version, build: build)
  rescue ArgumentError, JSON::ParserError, Errno::ENOENT => e
    UI.user_error!(e.message)
  end
  sh("cd '#{root}' && yarn prebuild --platform ios")
  # Outside bundler: `pod` must not load this Gemfile (it has no cocoapods).
  Bundler.with_unbundled_env { sh("cd '#{root}/ios' && pod install") }

  workspace = ENV["IOS_WORKSPACE"] ? File.join(root, ENV["IOS_WORKSPACE"]) : Dir[File.join(root, "ios/*.xcworkspace")].first
  UI.user_error!("No ios/*.xcworkspace found (run expo prebuild first or set IOS_WORKSPACE)") unless workspace
  xcodeproj = workspace.sub(/\.xcworkspace\z/, ".xcodeproj")
  scheme = ENV["IOS_SCHEME"] || File.basename(workspace, ".xcworkspace")

  # shortcut: assumes the app target is named like the scheme (true for Expo prebuild); add IOS_TARGET if not.
  targets = kit_ios_targets(scheme, bundle_id)
  # Names match actually installed (preflight): it appends a timestamp when the plain name is taken in the portal,
  # and stale profiles with the plain name may still sit on disk.
  mapping = lane_context[SharedValues::MATCH_PROVISIONING_PROFILE_MAPPING] || {}
  profiles = targets.values.to_h { |id| [id, mapping[id] || UI.user_error!("match installed no profile for #{id}")] }
  # Per target: without `targets:` this would stamp the app's id/profile onto every extension.
  targets.each do |target, id|
    update_code_signing_settings(
      path: xcodeproj,
      use_automatic_signing: false,
      team_id: kit_env!("APPLE_TEAM_ID"),
      code_sign_identity: "Apple Distribution",
      profile_name: profiles[id],
      bundle_identifier: id,
      targets: [target]
    )
  end

  build_ios_app(
    workspace: workspace,
    scheme: scheme,
    clean: true,
    export_method: "app-store",
    export_options: { provisioningProfiles: profiles },
    output_directory: File.join(root, "build/ios")
  )

  # Prod waits for processing so the build can be attached to the App Store version.
  next unless o[:upload]
  upload_to_testflight(api_key: api_key, app_identifier: bundle_id, skip_waiting_for_build_processing: !o[:release])
  kit_attach_to_app_store(api_key, bundle_id, version, build) if o[:release]
end

# Creates/renames the editable App Store version and selects this build on it. No review submission:
# deliver only attaches a build as part of submitting, so the attach is done via the ASC API.
def kit_attach_to_app_store(api_key, bundle_id, version, build)
  upload_to_app_store(
    api_key: api_key,
    app_identifier: bundle_id,
    app_version: version,
    skip_binary_upload: true,
    skip_metadata: true,
    skip_screenshots: true,
    submit_for_review: false,
    run_precheck_before_submit: false,
    force: true # no HTML preview prompt
  )

  Spaceship::ConnectAPI.token = Spaceship::ConnectAPI::Token.from(hash: api_key)
  app = Spaceship::ConnectAPI::App.find(bundle_id) || UI.user_error!("App #{bundle_id} not found in App Store Connect")
  store_version = app.get_edit_app_store_version(platform: Spaceship::ConnectAPI::Platform::IOS) ||
    UI.user_error!("No editable App Store version for #{bundle_id}")
  uploaded = Spaceship::ConnectAPI::Build.all(app_id: app.id, version: version, build_number: build.to_s).first ||
    UI.user_error!("Build #{version} (#{build}) not found in App Store Connect")
  store_version.select_build(build_id: uploaded.id)
  UI.success("Attached #{version} (#{build}) to App Store version #{store_version.version_string}")
end

private_lane :kit_android do |o|
  root, keys = o[:root], o[:keys]
  android_dir = File.join(root, "android")

  # Avoid `gradlew clean`: with the New Architecture it re-runs CMake after codegen
  # dirs are gone and fails. Wiping outputs on disk has the same effect.
  sh("rm -rf '#{android_dir}/app/.cxx' '#{android_dir}/app/build' '#{android_dir}/build'")

  # Read by the fastlane-kit Expo config plugin in app/build.gradle.
  build_android_app(
    task: "bundle",
    build_type: "Release",
    project_dir: android_dir,
    properties: {
      "kitVersionCode" => o[:build].to_s,
      "kitVersionName" => o[:version].to_s,
      "kitStoreFile" => File.join(keys, ENV["ANDROID_KEYSTORE_FILE"] || "release.keystore"),
      "kitStorePassword" => kit_env!("ANDROID_KEYSTORE_PASSWORD"),
      "kitKeyAlias" => kit_env!("ANDROID_KEY_ALIAS"),
      "kitKeyPassword" => kit_env!("ANDROID_KEY_PASSWORD")
    }
  )

  next unless o[:upload]
  upload_to_play_store(
    package_name: o[:package],
    json_key: File.join(keys, ENV["PLAY_JSON_KEY_FILE"] || "play-service-account.json"),
    track: ENV["PLAY_TRACK"] || "internal",
    release_status: ENV["PLAY_RELEASE_STATUS"] || "draft",
    aab: lane_context[SharedValues::GRADLE_AAB_OUTPUT_PATH],
    skip_upload_metadata: true,
    skip_upload_changelogs: true,
    skip_upload_images: true,
    skip_upload_screenshots: true
  )
end
