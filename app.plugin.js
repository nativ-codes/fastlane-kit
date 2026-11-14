const { withAppBuildGradle } = require("expo/config-plugins");
const { applyKitToGradle } = require("./android-gradle");

module.exports = function withFastlaneKit(config) {
  return withAppBuildGradle(config, (config) => {
    if (config.modResults.language !== "groovy") {
      throw new Error("[fastlane-kit] Only Groovy app/build.gradle is supported.");
    }
    config.modResults.contents = applyKitToGradle(config.modResults.contents);
    return config;
  });
};
