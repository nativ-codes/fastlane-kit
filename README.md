# fastlane-kit

One command to ship an Expo / React Native app to TestFlight, the App Store or Google Play.

```sh
bundle exec fastlane deploy platform:ios stage:dev
```

That one line picks the next version, prebuilds the native project, signs it, builds it, uploads it, then commits and tags the new version. Every app that installs the kit gets the same lanes, so you set up deploys once and reuse them everywhere.

It ships these pieces:

| Piece | What it does |
|---|---|
| `Fastfile` | The fastlane lanes: `deploy`, `check`, `certs`, `play_key`. |
| `app.plugin.js` | An Expo config plugin that lets the lanes set the Android version and signing at build time. |
| `optional-portrait.js` | Optional Expo config plugin for portrait-locked apps: stops Play hiding the app from tablets, desktop and XR. |

---

## Quick start

**1. Install the kit** in your app (the folder with `app.json`):

```sh
yarn add -D github:nativ-codes/fastlane-kit#v0.1.1
```

**2. Add the config plugin** to `app.json`, then prebuild:

```json
{ "expo": { "plugins": ["fastlane-kit"] } }
```

**3. Create `fastlane/Fastfile`** with one line:

```ruby
import("../node_modules/fastlane-kit/Fastfile")
```

**4. Create `fastlane/Gemfile`**, then run `cd fastlane && bundle install`:

```ruby
source "https://rubygems.org"
gem "fastlane"
gem "dotenv"
```

**5. Add your config and keys:**

```sh
cp node_modules/fastlane-kit/.env.example fastlane/.env.deploy   # then fill it in
mkdir fastlane/keys                                              # put key files here
```

**6. Gitignore the secrets:**

```gitignore
fastlane/.env.*
fastlane/keys/
fastlane/report.xml
fastlane/README.md
```

**7. Check, then deploy:**

```sh
cd fastlane
bundle exec fastlane check  platform:ios stage:dev   # checks everything, builds nothing
bundle exec fastlane deploy platform:ios stage:dev
```

If `check` passes, `deploy` will run. `deploy` runs `check` first anyway.

---

## Your project layout

Everything deploy-related lives in `<project>/fastlane/`:

```
fastlane/
  Fastfile            import("../node_modules/fastlane-kit/Fastfile")
  Gemfile             fastlane + dotenv
  .env.deploy         shared config                       gitignored
  .env.<stage>        optional per-stage overrides         gitignored
  keys/                                                    gitignored
    AuthKey.p8                  App Store Connect API key
    play-service-account.json   Play Console service account
    release.keystore            Android upload keystore
  versioning/         .ios-versions, .android-versions     committed (created on first deploy)
```

---

## Commands

Run all of them from `<project>/fastlane`.

| Command | When | What it does |
|---|---|---|
| `fastlane deploy platform:<ios\|android> stage:<name>` | Every release | Versions, builds, signs, uploads, commits and tags. |
| `fastlane check platform:<ios\|android> stage:<name>` | Anytime | Builds nothing. Checks env vars, key files, tools and git state, then proves access works. iOS: calls App Store Connect and runs read-only `match`. Android: unlocks the keystore with `keytool` and calls the Play API for your package and track. |
| `fastlane certs stage:<name>` | Once per stage, before the first iOS deploy | Creates any missing iOS certificates and profiles in your match repo. |
| `fastlane play_key [project:<gcp-id>]` | Once, before the first Android deploy | Creates a Play service account and its JSON key with `gcloud`. Then invite the printed email in Play Console > Users and permissions. |

Options for `deploy`:

| Option | Effect |
|---|---|
| `bump:major\|minor\|patch` | Bumps the release version. Only allowed on `stage:prod`. |
| `skip_git:true` | Uploads, but doesn't commit, push or tag. |
| `skip_upload:true` | Stops after the build. Nothing is uploaded, saved or committed. Handy for testing the build. |

Examples:

```sh
bundle exec fastlane deploy platform:ios     stage:dev
bundle exec fastlane deploy platform:android stage:prod bump:minor
bundle exec fastlane deploy platform:ios     stage:prod skip_upload:true
```

---

## How a deploy works

```
deploy platform:ios stage:dev
  │
  ├─ 1. Load config      fastlane/.env.deploy, then fastlane/.env.dev on top
  ├─ 2. Next version     read versioning/.ios-versions  →  999.99 (4)
  ├─ 3. Check            env, keys, tools, clean git, certs/profiles
  ├─ 4. Build            iOS: app.json → prebuild → pod install → match → build
  │                      Android: app.json → prebuild → Gradle gets version + signing as properties
  ├─ 5. Upload           TestFlight / App Store, or Google Play
  └─ 6. Save             write the versions file, commit, push, tag dev_v999.99_4_ios
```

The versions file is written **only after the upload succeeds**, so a failed build never burns a version or build number.

### Stages

A stage is any name you pass: `dev`, `stage`, `qa`, `prod`… The kit loads `fastlane/.env.deploy` and then `fastlane/.env.<stage>` on top of it, so a stage file only needs the values that differ.

The stage name is also set as `EXPO_PUBLIC_APP_ENV` before the build, so your JS can read it. To use a different variable, set `KIT_APP_ENV_VAR`.

All stages ship to the same store app. Only `prod` is a real release.

### Versioning

Each platform has a small committed file, `fastlane/versioning/.<platform>-versions`:

```ini
version=1.3.0        # the real release version
build=42             # build number
stage_version=999.99 # what non-prod stages ship as
stage_build=7        # iOS only: separate counter for non-prod builds
```

| Stage | Version shipped | Build number |
|---|---|---|
| any non-prod | `stage_version` (default `999.99`) | iOS: `stage_build + 1`. Android: `build + 1` |
| `prod` | `version`, bumped by `bump:` | `build + 1` |

Why the split? iOS only needs builds to be unique per version, so test builds count on their own (`999.99 (1)`, `999.99 (2)`…) and never touch the release train. Android needs `versionCode` to grow across every upload of the package, so all stages share `build`.

After an upload the kit commits the file and tags it `<stage>_v<version>_<build>_<platform>`, for example `prod_v1.3.1_43_android`.

### iOS

1. Writes the version and build number into `app.json` (`expo.version`, `expo.ios.buildNumber`).
2. Runs `yarn prebuild --platform ios` and `pod install`, so the native project matches `app.json`.
3. `match` (read-only) installs the certificate and profiles, with manual signing per target.
4. Builds the app and uploads it:
   - **non-prod**: TestFlight only.
   - **prod**: waits for processing, creates or renames the App Store version (e.g. `1.3.1`) and attaches the build. It doesn't submit for review.

`app.json` is committed together with the versions file.

**App extensions**: list them as `IOS_EXTENSIONS=ShareExtension:share-extension`. Each one gets the bundle id `<IOS_BUNDLE_ID>.<suffix>` and its own profile. `deploy` is read-only, so run `certs stage:<name>` once to create those profiles.

### Android

The config plugin rewrites `android/app/build.gradle` during `expo prebuild` so that `versionCode`, `versionName` and release signing come from Gradle properties. The lane runs `yarn prebuild --platform android` first, so the native project matches `app.json`, then passes those properties at build time, so no secret ever lands in `build.gradle`. Without them, local builds keep the defaults and debug signing.

The lane builds an AAB, uploads it to Play on the `internal` track and rolls the release out to your internal testers (`completed`). Set `PLAY_RELEASE_STATUS=draft` to roll it out yourself in Play Console instead. A Play app that has never been published only accepts `draft`.

**Portrait-locked apps**: `"orientation": "portrait"` makes Android imply a required `android.hardware.screen.portrait` feature, and Play then blocks review with "Required hardware feature declarations are restricting your app's availability". Add the kit's second plugin to declare that feature optional. The app stays portrait on phones.

```json
{ "expo": { "plugins": ["fastlane-kit", "fastlane-kit/optional-portrait"] } }
```

---

## Configuration

Copy `node_modules/fastlane-kit/.env.example` to `fastlane/.env.deploy`. Key files are looked up in `fastlane/keys/` (override with `KIT_KEYS_DIR`). Any extra variable you add, such as `SENTRY_DISABLE_AUTO_UPLOAD=true`, also reaches the native build.

**iOS**

| Variable | Notes |
|---|---|
| `IOS_BUNDLE_ID` | e.g. `com.acme.app` |
| `APPLE_TEAM_ID` | |
| `MATCH_GIT_URL`, `MATCH_PASSWORD` | Your fastlane match repo |
| `ASC_KEY_ID`, `ASC_ISSUER_ID` | App Store Connect API key |
| `ASC_KEY_FILE` | Default `AuthKey.p8`. Or paste the key into `ASC_KEY_CONTENT` (useful in CI). |
| `IOS_WORKSPACE`, `IOS_SCHEME` | Optional. Auto-detected from `ios/*.xcworkspace`. |
| `IOS_EXTENSIONS` | Optional. `Target:suffix`, comma separated. |

**Android**

| Variable | Notes |
|---|---|
| `ANDROID_PACKAGE` | e.g. `com.acme.app` |
| `ANDROID_KEYSTORE_FILE` | Default `release.keystore` |
| `ANDROID_KEYSTORE_PASSWORD`, `ANDROID_KEY_ALIAS`, `ANDROID_KEY_PASSWORD` | Upload key |
| `PLAY_JSON_KEY_FILE` | Default `play-service-account.json` |
| `PLAY_TRACK` | Default `internal` |
| `PLAY_RELEASE_STATUS` | Default `completed` (rolled out to testers). `draft` leaves it for you to roll out. |

---

## Updating the kit

Pin a tag and bump it when you want the new lanes:

```sh
yarn add -D github:nativ-codes/fastlane-kit#v0.1.2
```

If this repo is private, the machine that runs `yarn install` (including CI) needs GitHub access, through an SSH key or a token.

## Requirements

- Expo with `app.json` (not `app.config.js`) and a Groovy `android/app/build.gradle` (the default template)
- Ruby + Bundler, Xcode + CocoaPods for iOS, a JDK for Android
- `gcloud`, only for `play_key`

## Development

```sh
yarn test   # node test for the config plugin + ruby test for versioning
```
