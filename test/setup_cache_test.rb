# Run: "$(brew --prefix ruby)/bin/ruby" test/setup_cache_test.rb
# macOS only: the cache key is bound to the hardware UUID read via ioreg.
require 'minitest/autorun'
require 'open3'
require 'tmpdir'
require 'json'
require 'fileutils'

ROOT = File.expand_path('..', __dir__)

class SetupCacheTest < Minitest::Test
  def setup
    @home = Dir.mktmpdir # scripts write under ~, so a fake HOME protects the real seed/cache
    @csv = File.join(@home, 'pw.csv')
    @seed = File.join(@home, '.config/alfred-pw-workflow/seed')
    @cache = File.join(@home, '.cache/alfred-pw-workflow/apw_cache.enc')
  end

  def teardown = FileUtils.rm_rf(@home)

  def run_script(name, *args, env: {})
    Open3.capture3({ 'HOME' => @home, **env }, RbConfig.ruby, '-x', File.join(ROOT, name), *args)
  end

  def write_csv
    File.write(@csv, <<~CSV)
      Title,URL,Username,Password,Notes,OTPAuth
      GitHub,https://github.com/login,octo,secret,,
      Local,http://localhost:8080/,admin,pw,,
      ,,,,,
    CSV
  end

  def test_round_trip
    write_csv
    out, err, st = run_script('setup_cache.rb', @csv)
    assert st.success?, err
    assert_match(/2 items processed/, out) # the empty row is skipped
    refute File.exist?(@csv)               # input CSV is deleted
    [@seed, @cache].each { |f| assert_equal 0o600, File.stat(f).mode & 0o777 }

    out, = run_script('alfred_filter_script.rb', 'local')
    assert_equal 'admin|localhost:8080', JSON.parse(out)['items'].first['arg'] # non-default port kept
  end

  def test_unicode_round_trip
    File.write(@csv, <<~CSV)
      Title,URL,Username,Password,Notes,OTPAuth
      Café Crème ☕,https://example.com/,zoë@例え.jp,pw,,
    CSV
    _, err, st = run_script('setup_cache.rb', @csv)
    assert st.success?, err

    # No locale set, as Alfred may run scripts: the query must still be read as UTF-8
    no_locale = { 'LANG' => nil, 'LC_ALL' => nil, 'LC_CTYPE' => nil }
    out, err, st = run_script('alfred_filter_script.rb', 'CRÈME', env: no_locale) # matches case-insensitively
    assert st.success?, err
    item = JSON.parse(out)['items'].first
    assert_equal 'Café Crème ☕', item['title']
    assert_equal 'user: zoë@例え.jp | domain: example.com', item['subtitle']
    assert_equal 'zoë@例え.jp|example.com', item['arg']
  end

  def test_seed_reused
    write_csv
    assert run_script('setup_cache.rb', @csv)[2].success?
    seed = File.read(@seed)

    write_csv
    out, err, st = run_script('setup_cache.rb', @csv)
    assert st.success?, err
    refute_match(/Generated new seed/, out)
    assert_equal seed, File.read(@seed)
  end

  def test_missing_argument
    _, err, st = run_script('setup_cache.rb')
    assert_equal 1, st.exitstatus
    assert_match(/Usage/, err)
  end

  def test_missing_csv
    _, err, st = run_script('setup_cache.rb', @csv)
    assert_equal 1, st.exitstatus
    assert_match(/CSV file not found/, err)
    refute File.exist?(@cache)
  end

  def test_malformed_csv
    File.write(@csv, "Title,URL\n\"unclosed,x\n")
    _, err, st = run_script('setup_cache.rb', @csv)
    assert_equal 1, st.exitstatus
    assert_match(/unable to parse/, err)
    refute File.exist?(@csv)   # still deleted on failure
    refute File.exist?(@cache)
  end
end
