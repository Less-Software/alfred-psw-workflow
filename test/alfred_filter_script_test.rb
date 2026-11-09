# Run: "$(brew --prefix ruby)/bin/ruby" test/alfred_filter_script_test.rb
# macOS only: the cache key is bound to the hardware UUID read via ioreg.
require 'minitest/autorun'
require 'open3'
require 'tmpdir'
require 'json'
require 'fileutils'

class AlfredFilterScriptTest < Minitest::Test
  def setup
    @home = Dir.mktmpdir # scripts write under ~, so a fake HOME protects the real seed/cache
    @seed = File.join(@home, '.config/alfred-pw-workflow/seed')
    @cache = File.join(@home, '.cache/alfred-pw-workflow/apw_cache.enc')
  end

  def teardown = FileUtils.rm_rf(@home)

  def run_script(name, *args)
    Open3.capture3({ 'HOME' => @home }, RbConfig.ruby, '-x', File.expand_path("../#{name}", __dir__), *args)
  end

  # Build the cache with the real setup script, so both sides share the format
  def build_cache
    csv = File.join(@home, 'pw.csv')
    File.write(csv, <<~CSV)
      Title,URL,Username,Password,Notes,OTPAuth
      GitHub,https://github.com/login,octo,secret,,
      ,https://gitlab.com/,alice,pw,,
      Work Mail,https://mail.example.com/,github-bot,pw,,
      ,,solo,pw,,
    CSV
    _, err, st = run_script('setup_cache.rb', csv)
    assert st.success?, err
  end

  def search(query)
    out, err, st = run_script('alfred_filter_script.rb', query)
    assert st.success?, err
    JSON.parse(out)['items']
  end

  def test_short_query
    items = search(' abc ')
    assert_equal 'Please type at least 4 characters...', items[0]['title']
    assert_match(/1 characters remaining/, items[0]['subtitle'])
    assert_equal false, items[0]['valid']
  end

  def test_missing_cache
    items = search('github')
    assert_equal 'Seed or Cache missing. Please run sync.', items[0]['title']
  end

  def test_corrupt_cache
    build_cache
    File.write(@cache, 'not json')
    assert_equal 'Decryption or Parsing Error', search('github')[0]['title']
  end

  def test_wrong_seed
    build_cache
    File.write(@seed, 'f' * 64) # a copied cache must not open with another seed
    assert_equal 'Decryption or Parsing Error', search('github')[0]['title']
  end

  def test_matches_title_domain_or_username_with_title_matches_first
    build_cache
    assert_equal ['GitHub', 'Work Mail'], search('github').map { _1['title'] }
  end

  def test_case_insensitive_and_falls_back_to_domain
    build_cache
    item = search('GITLAB').first
    assert_equal 'gitlab.com', item['title']
    assert_equal 'user: alice | domain: gitlab.com', item['subtitle']
    assert_equal 'alice|gitlab.com', item['arg']
    assert_equal 'gitlab.com', item['text']['copy']
  end

  def test_username_only_entry
    build_cache
    item = search('solo').first
    assert_equal 'solo', item['title']
    assert_equal 'user: solo', item['subtitle']
    assert_equal 'solo|', item['arg']
  end

  def test_no_match
    build_cache
    items = search('nothing-here')
    assert_equal "No credentials found for 'nothing-here'", items[0]['title']
    assert_equal false, items[0]['valid']
  end
end
