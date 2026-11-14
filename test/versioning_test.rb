require "minitest/autorun"
require "tmpdir"
require_relative "../versioning"

class VersioningTest < Minitest::Test
  def test_stage_keeps_train_and_counts_shared_build
    store, v, b = KitVersioning.next({ "version" => "1.2.3", "stage_version" => "888.1", "build" => "41" }, release: false)
    assert_equal ["888.1", 42], [v, b]
    assert_equal ["1.2.3", "42"], [store["version"], store["build"]]
  end

  def test_separate_stage_counter_leaves_prod_counter
    store, v, b = KitVersioning.next({ "build" => "9", "stage_build" => "1" }, release: false, separate_stage_counter: true)
    assert_equal ["999.99", 2], [v, b]
    assert_equal ["9", "2"], [store["build"], store["stage_build"]]
    _, _, prod_build = KitVersioning.next(store, release: true, separate_stage_counter: true)
    assert_equal 10, prod_build
  end

  def test_stage_version_defaults_and_is_persisted
    store, v, _ = KitVersioning.next({}, release: false)
    assert_equal "999.99", v
    assert_equal "999.99", store["stage_version"]
  end

  def test_prod_bumps_train
    store, v, b = KitVersioning.next({ "version" => "1.2.3", "build" => "41" }, release: true, bump: "minor")
    assert_equal ["1.3.0", 42], [v, b]
    assert_equal "1.3.0", store["version"]
  end

  def test_empty_store_and_blank_bump
    _, v, b = KitVersioning.next({}, release: true, bump: "")
    assert_equal ["1.0.0", 1], [v, b]
  end

  def test_bumps_and_errors
    assert_equal "2.0.0", KitVersioning.bumped("1.2.3", "major")
    assert_equal "1.2.4", KitVersioning.bumped("1.2.3", "patch")
    assert_raises(ArgumentError) { KitVersioning.bumped("1.2.3", "huge") }
    assert_raises(ArgumentError) { KitVersioning.next({}, release: false, bump: "patch") }
  end

  def test_roundtrip
    Dir.mktmpdir do |d|
      path = File.join(d, ".ios-versions")
      KitVersioning.write(path, { "version" => "1.0.0", "build" => "3" })
      assert_equal({ "version" => "1.0.0", "build" => "3" }, KitVersioning.read(path))
    end
  end

  def test_write_app_json
    Dir.mktmpdir do |d|
      path = File.join(d, "app.json")
      File.write(path, '{"expo":{"name":"x","version":"1.0.0","ios":{"buildNumber":"4","supportsTablet":true}}}')
      KitVersioning.write_app_json(path, version: "999.99", build: 7)
      expo = JSON.parse(File.read(path))["expo"]
      assert_equal ["x", "999.99", "7", true], [expo["name"], expo["version"], expo["ios"]["buildNumber"], expo["ios"]["supportsTablet"]]
      File.write(path, "{}")
      assert_raises(ArgumentError) { KitVersioning.write_app_json(path, version: "1", build: 1) }
    end
  end
end
