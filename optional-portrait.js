const { withAndroidManifest } = require("expo/config-plugins");

// orientation: "portrait" makes Android imply a *required* android.hardware.screen.portrait,
// which Play uses to hide the app from tablets/desktop/XR. Declaring it optional keeps the lock
// but drops the install restriction.
const FEATURE = "android.hardware.screen.portrait";

function addOptionalPortrait(manifest) {
  const features = (manifest["uses-feature"] ??= []);
  if (!features.some((feature) => feature.$["android:name"] === FEATURE)) {
    features.push({ $: { "android:name": FEATURE, "android:required": "false" } });
  }
  return manifest;
}

module.exports = function withOptionalPortrait(config) {
  return withAndroidManifest(config, (config) => {
    addOptionalPortrait(config.modResults.manifest);
    return config;
  });
};
module.exports.addOptionalPortrait = addOptionalPortrait;
