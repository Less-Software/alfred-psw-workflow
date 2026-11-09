# macOS only: the cache key is bound to the hardware UUID read via ioreg.
require 'minitest/autorun'
require 'open3'
require 'tmpdir'
require 'json'
require 'fileutils'

ROOT = File.expand_path('..', __dir__)

class SetupCacheTest < Minitest::Test
  parallelize_me! # each test uses its own temp dir or pasteboard, so they can share the process
  def setup
    @home = Dir.mktmpdir # scripts write under ~, so a fake HOME protects the real seed/cache
    @csv = File.join(@home, 'pw.csv')
    @seed = File.join(@home, '.config/alfred-psw-workflow/seed')
    @cache = File.join(@home, '.cache/alfred-psw-workflow/apw_cache.enc')
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
    File.write(@csv, "Title,URL,Username,Password\n\"unclosed,x\n")
    _, err, st = run_script('setup_cache.rb', @csv)
    assert_equal 1, st.exitstatus
    assert_match(/unable to parse/, err)
    refute File.exist?(@csv)   # still deleted on failure
    refute File.exist?(@cache)
  end

  def test_other_csv_left_untouched
    File.write(@csv, "Date,Amount\n2026-01-01,12.50\n") # e.g. a bank export picked by mistake
    _, err, st = run_script('setup_cache.rb', @csv)
    assert_equal 1, st.exitstatus
    assert_match(/not a Passwords export/, err)
    assert File.exist?(@csv)
    refute File.exist?(@cache)
  end

  def test_unparsable_url_keeps_raw_host
    File.write(@csv, "Title,URL,Username,Password\nBooks,https://bücher.de/a b,reader,pw\n") # URI rejects both
    _, err, st = run_script('setup_cache.rb', @csv)
    assert st.success?, err
    out, = run_script('alfred_filter_script.rb', 'books')
    assert_equal 'reader|bücher.de', JSON.parse(out)['items'].first['arg']
  end

  def test_failed_write_keeps_previous_cache
    write_csv
    assert run_script('setup_cache.rb', @csv)[2].success?
    previous = File.read(@cache)
    FileUtils.mkdir("#{@cache}.tmp") # makes the next write fail
    write_csv
    refute run_script('setup_cache.rb', @csv)[2].success?
    assert_equal previous, File.read(@cache)
  end

  # Runs setup_cache.rb with a fake osascript first on PATH; returns the notifications it got as [message, title].
  # The fake file picker answers `picked`, or cancels when it is nil. Sets @status, @err and @picker_calls.
  def notifications_from(*args, alfred: true, picked: nil)
    bin = File.join(@home, 'bin')
    log = File.join(@home, 'notifications')
    picker_log = File.join(@home, 'picker_calls')
    FileUtils.mkdir_p(bin)
    File.write(File.join(bin, 'osascript'), <<~SH)
      #!/bin/bash
      case "$*" in
        *"choose file"*) printf '%s\\n' "$*" >> "#{picker_log}"; [ -n "$PICKED" ] || exit 1; echo "$PICKED"; exit 0 ;;
      esac
      printf '%s\\n' "${@: -2}" >> "#{log}"
    SH
    File.chmod(0o755, File.join(bin, 'osascript'))
    env = { 'PATH' => "#{bin}:#{ENV['PATH']}", 'alfred_version' => (alfred ? '5.5' : nil), 'PICKED' => picked }
    _, @err, @status = run_script('setup_cache.rb', *args, env: env)
    @picker_calls = File.exist?(picker_log) ? File.readlines(picker_log, chomp: true) : []
    File.exist?(log) ? File.readlines(log, chomp: true).each_slice(2).to_a : []
  end

  def test_alfred_notifies_success
    write_csv
    assert_equal [['Cache updated: 2 items', 'Apple Passwords']], notifications_from(@csv)
  end

  def test_alfred_notifies_failure
    File.write(@csv, "Title,URL,Username,Password\n\"unclosed,x\n")
    (message, title), = notifications_from(@csv)
    assert_equal 'Error', title
    assert_match(/unable to parse/, message)
    refute File.exist?(@csv) # still deleted on failure
  end

  def test_alfred_without_file_uses_picker
    write_csv
    assert_equal [['Cache updated: 2 items', 'Apple Passwords']], notifications_from('', picked: @csv) # keyword passes ''
    refute File.exist?(@csv)
  end

  def test_alfred_without_argument_uses_picker
    dir = File.join(@home, 'RAM Disk é') # picked paths can hold spaces and non-ASCII characters
    FileUtils.mkdir(dir)
    @csv = File.join(dir, 'Passwords.csv')
    write_csv
    assert_equal [['Cache updated: 2 items', 'Apple Passwords']], notifications_from(picked: @csv)
    assert @status.success?, @err
    assert File.exist?(@cache)
    refute File.exist?(@csv)
  end

  def test_alfred_picker_asks_for_a_csv
    notifications_from
    assert_equal 1, @picker_calls.size
    assert_includes @picker_calls[0], 'Select your Passwords CSV export'
    assert_includes @picker_calls[0], 'public.comma-separated-values-text'
  end

  def test_alfred_picker_canceled
    assert_empty notifications_from # no error notification either
    assert @status.success?
    assert_empty @err
    refute File.exist?(@cache)
    refute File.exist?(@seed) # canceled before anything is created
  end

  def test_alfred_picked_file_missing
    (message, title), = notifications_from(picked: File.join(@home, 'gone.csv'))
    assert_equal 'Error', title
    assert_match(/CSV file not found/, message)
    assert_equal 1, @status.exitstatus
  end

  def test_terminal_without_argument_does_not_open_picker
    notifications_from(alfred: false)
    assert_empty @picker_calls
    assert_equal 1, @status.exitstatus
    assert_match(/Usage/, @err)
  end

  def test_terminal_does_not_notify
    write_csv
    assert_empty notifications_from(@csv, alfred: false)
  end
end
