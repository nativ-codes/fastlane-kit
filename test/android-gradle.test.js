const assert = require("node:assert");
const { applyKitToGradle } = require("../android-gradle");

// Trimmed Expo 55 template shape.
const gradle = `android {
    defaultConfig {
        applicationId 'com.acme.app'
        versionCode 1
        versionName "1.0.0"
    }
    signingConfigs {
        debug {
            storeFile file('debug.keystore')
        }
    }
    buildTypes {
        debug {
            signingConfig signingConfigs.debug
        }
        release {
            signingConfig signingConfigs.debug
            minifyEnabled false
        }
    }
}`;

const out = applyKitToGradle(gradle);
assert.match(out, /versionCode\(\(findProperty\("kitVersionCode"\) \?: "1"\)\.toInteger\(\)\)/);
assert.match(out, /versionName\(findProperty\("kitVersionName"\) \?: "1\.0\.0"\)/);
assert.match(out, /release \{\n\s+if \(findProperty\("kitStoreFile"\)\)/);
// debug buildType untouched, release switched
assert.match(out, /debug \{\n\s+signingConfig signingConfigs\.debug\n/);
assert.match(out, /release \{\n\s+signingConfig findProperty\("kitStoreFile"\) \? signingConfigs\.release : signingConfigs\.debug/);
assert.strictEqual(applyKitToGradle(out), out, "idempotent");
assert.throws(() => applyKitToGradle("android {}"), /fastlane-kit/);
console.log("android-gradle ok");
