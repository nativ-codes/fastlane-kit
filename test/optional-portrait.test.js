const assert = require("node:assert");
const { addOptionalPortrait } = require("../optional-portrait");

const portrait = { $: { "android:name": "android.hardware.screen.portrait", "android:required": "false" } };

assert.deepStrictEqual(addOptionalPortrait({})["uses-feature"], [portrait]);

const camera = { $: { "android:name": "android.hardware.camera" } };
assert.deepStrictEqual(addOptionalPortrait({ "uses-feature": [camera] })["uses-feature"], [camera, portrait]);

const once = addOptionalPortrait({});
assert.deepStrictEqual(addOptionalPortrait(once)["uses-feature"], [portrait], "idempotent");

console.log("optional-portrait ok");
