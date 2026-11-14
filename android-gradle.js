// Rewrites an Expo app/build.gradle so versionCode/versionName and release signing
// come from Gradle properties (-PkitVersionCode=... passed by the Fastfile).
// No secrets end up in build.gradle; without the properties, local builds keep
// the defaults and debug signing.
const MARKER = "kitStoreFile";

function replaceOrThrow(contents, pattern, replacement, what) {
  const next = contents.replace(pattern, replacement);
  if (next === contents) {
    throw new Error(`[fastlane-kit] Could not find ${what} in app/build.gradle; the Expo template may have changed.`);
  }
  return next;
}

function applyKitToGradle(contents) {
  if (contents.includes(MARKER)) return contents;

  contents = replaceOrThrow(
    contents,
    /versionCode\s+(\d+)/,
    'versionCode((findProperty("kitVersionCode") ?: "$1").toInteger())',
    "versionCode"
  );
  contents = replaceOrThrow(
    contents,
    /versionName\s+("[^"\n]*")/,
    'versionName(findProperty("kitVersionName") ?: $1)',
    "versionName"
  );
  contents = replaceOrThrow(
    contents,
    /signingConfigs\s*\{/,
    `signingConfigs {
        release {
            if (findProperty("${MARKER}")) {
                storeFile file(findProperty("${MARKER}"))
                storePassword findProperty("kitStorePassword")
                keyAlias findProperty("kitKeyAlias")
                keyPassword findProperty("kitKeyPassword")
            }
        }`,
    "signingConfigs"
  );
  contents = replaceOrThrow(
    contents,
    /(buildTypes\s*\{[\s\S]*?release\s*\{[\s\S]*?)signingConfig signingConfigs\.\w+/,
    `$1signingConfig findProperty("${MARKER}") ? signingConfigs.release : signingConfigs.debug`,
    "buildTypes.release.signingConfig"
  );
  return contents;
}

module.exports = { applyKitToGradle };
