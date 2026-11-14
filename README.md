# kit (fastlane-kit)

Shared deploy lanes for Expo/React Native apps, extracted from the Horexa setup.
One command builds, signs, versions, uploads and tags. Run from `<project>/fastlane`:

```sh
bundle exec fastlane deploy platform:ios stage:dev
bundle exec fastlane deploy platform:android stage:prod bump:minor
# optional: skip_git:true     (no commit/push/tag)
#           skip_upload:true  (stop after the build: no upload, no version save, no git)

# check everything (env, keys, tools, git, ASC key, certs/profiles) without building; deploy runs it first too
bundle exec fastlane check platform:ios stage:stage

# one-time per stage, before the first iOS deploy: create missing profiles in the match repo
bundle exec fastlane certs stage:prod

# one-time, before the first Android deploy: create a Play service account + JSON key (needs gcloud)
# then invite the printed email in Play Console > Users and permissions
bundle exec fastlane play_key            # optional: project:<gcp-project-id>
```

## What it does

- **Config**: loads `fastlane/.env.deploy`, then `fastlane/.env.<stage>` (overrides). Sets `EXPO_PUBLIC_APP_ENV=<stage>` before the native build.
- **Versioning** (`fastlane/versioning/.<platform>-versions`, committed):
  - any stage other than `prod` ships `stage_version=` (default `999.99`) and never touches the release train;
  - `stage:prod` ships the real `version=`, bumped by `bump:major|minor|patch`;
  - build numbers: prod uses `build=N`. On iOS, stages count separately in `stage_build=N` (`999.99 (1)`, `999.99 (2)`…), since iOS only needs builds unique per version name. Android needs `versionCode` to grow across every upload of a package, so there stage and prod share `build`. All stages are assumed to ship to the same store app.
  - The file is written only after the upload succeeds, then committed and tagged `<stage>_v<version>_<build>_<platform>`.
- **iOS**:
  1. writes the version and build number into `app.json` (`expo.version`, `expo.ios.buildNumber`);
  2. `yarn prebuild --platform ios` + `pod install`, so the native project matches app.json;
  3. `match` (readonly) installs the certificate and profiles; manual signing per target;
  4. `build_ios_app`, then upload:
     - non-prod stage: TestFlight only, e.g. `999.99 (1)`, `999.99 (2)`;
     - prod: waits for processing, creates/renames the App Store version (e.g. `1.3.1`) and attaches the build. Not submitted for review.
  `app.json` is committed with the versions file.
  Extensions (`IOS_EXTENSIONS=ShareExtension:share-extension`) get their own id `<IOS_BUNDLE_ID>.<suffix>`, profile and per-target signing. `deploy` is readonly, so run `certs stage:<name>` once to create their profiles.
- **Android**: the Expo config plugin makes `app/build.gradle` read `versionCode`, `versionName` and release signing from Gradle properties that the lane passes. Nothing secret is written to build.gradle. Builds the AAB and uploads it to Play (`internal` / `draft` by default).

## Add to a project

Everything for deployment lives in `<project>/fastlane/`:

```
<project>/fastlane/
  Fastfile            # import("./kit/Fastfile")
  Gemfile             # gem "fastlane", gem "dotenv"
  kit/                # this folder
  .env.deploy         # shared config, gitignored, see kit/.env.example
  .env.<stage>        # optional per-stage overrides, gitignored
  keys/               # gitignored
    AuthKey.p8                # App Store Connect API key
    play-service-account.json # Play Console service account
    release.keystore          # Android upload keystore
  versioning/         # committed; .<platform>-versions, created on first deploy
```

1. Copy this folder to `fastlane/kit/`, add `fastlane/Fastfile` and `fastlane/Gemfile` as above, `cd fastlane && bundle install`.
2. Plugin in `app.json`: `"plugins": ["./fastlane/kit/app.plugin.js"]`, then `expo prebuild`.
3. Gitignore `fastlane/.env.*`, `fastlane/keys/`, `fastlane/report.xml` and `fastlane/README.md`.

## Tests

```sh
yarn test   # node plugin test + ruby versioning test
```

## Migrating Horexa (not done)

Horexa's versions files use `dev=/staging=/build_number=` keys. To switch, rewrite them as
`version=<staging version>` + `build=<build_number>`, then replace the
`with-android-signing-config` and `with-android-fastlane-versions` plugins with `fastlane-kit`.
