# macOS only: the cache key is bound to the hardware UUID read via ioreg.
require 'minitest/autorun'
require 'open3'
require 'tmpdir'
require 'json'
require 'fileutils'

ROOT = File.expand_path('../src', __dir__)

class SetupWorkflowTest < Minitest::Test
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
    out, err, st = run_script('setup_workflow.rb', @csv)
    assert st.success?, err
    assert_match(/2 items processed/, out) # the empty row is skipped
    refute File.exist?(@csv)               # input CSV is deleted
    [@seed, @cache].each { |f| assert_equal 0o600, File.stat(f).mode & 0o777 }

    out, = run_script('main.rb', 'local')
    assert_equal 'admin|localhost:8080', JSON.parse(out)['items'].first['arg'] # non-default port kept
  end

  def test_unicode_round_trip
    File.write(@csv, <<~CSV)
      Title,URL,Username,Password,Notes,OTPAuth
      Café Crème ☕,https://example.com/,zoë@例え.jp,pw,,
    CSV
    _, err, st = run_script('setup_workflow.rb', @csv)
    assert st.success?, err

    # No locale set, as Alfred may run scripts: the query must still be read as UTF-8
    no_locale = { 'LANG' => nil, 'LC_ALL' => nil, 'LC_CTYPE' => nil }
    out, err, st = run_script('main.rb', 'CRÈME', env: no_locale) # matches case-insensitively
    assert st.success?, err
    item = JSON.parse(out)['items'].first
    assert_equal 'Café Crème ☕', item['title']
    assert_equal 'user: zoë@例え.jp | domain: example.com', item['subtitle']
    assert_equal 'zoë@例え.jp|example.com', item['arg']
  end

  def test_seed_reused
    write_csv
    assert run_script('setup_workflow.rb', @csv)[2].success?
    seed = File.read(@seed)

    write_csv
    out, err, st = run_script('setup_workflow.rb', @csv)
    assert st.success?, err
    refute_match(/Generated new seed/, out)
    assert_equal seed, File.read(@seed)
  end

  def test_missing_argument
    _, err, st = run_script('setup_workflow.rb')
    assert_equal 1, st.exitstatus
    assert_match(/Usage/, err)
  end

  def test_missing_csv
    _, err, st = run_script('setup_workflow.rb', @csv)
    assert_equal 1, st.exitstatus
    assert_match(/CSV file not found/, err)
    refute File.exist?(@cache)
  end

  def test_malformed_csv
    File.write(@csv, "Title,URL,Username,Password\n\"unclosed,x\n")
    _, err, st = run_script('setup_workflow.rb', @csv)
    assert_equal 1, st.exitstatus
    assert_match(/unable to parse/, err)
    refute File.exist?(@csv)   # still deleted on failure
    refute File.exist?(@cache)
  end

  def test_other_csv_left_untouched
    File.write(@csv, "Date,Amount\n2026-01-01,12.50\n") # e.g. a bank export picked by mistake
    _, err, st = run_script('setup_workflow.rb', @csv)
    assert_equal 1, st.exitstatus
    assert_match(/not a Passwords export/, err)
    assert File.exist?(@csv)
    refute File.exist?(@cache)
  end

  def test_unparsable_url_keeps_raw_host
    File.write(@csv, "Title,URL,Username,Password\nBooks,https://bücher.de/a b,reader,pw\n") # URI rejects both
    _, err, st = run_script('setup_workflow.rb', @csv)
    assert st.success?, err
    out, = run_script('main.rb', 'books')
    assert_equal 'reader|bücher.de', JSON.parse(out)['items'].first['arg']
  end

  def test_failed_write_keeps_previous_cache
    write_csv
    assert run_script('setup_workflow.rb', @csv)[2].success?
    previous = File.read(@cache)
    FileUtils.mkdir("#{@cache}.tmp") # makes the next write fail
    write_csv
    refute run_script('setup_workflow.rb', @csv)[2].success?
    assert_equal previous, File.read(@cache)
  end

  # Runs setup_workflow.rb with a fake osascript (the file picker) and launchctl first on PATH; returns the notifications
  # printed for Alfred's Post Notification as [message, title]. The fake picker answers `picked`, or cancels when it
  # is nil. The fake `launchctl print` finds the agent loaded unless `loaded` is false, and isn't logged.
  # Sets @status, @err, @picker_calls and @launchctl_calls.
  def notifications_from(*args, alfred: true, picked: nil, launch_script: '1', loaded: true)
    bin = File.join(@home, 'bin')
    picker_log = File.join(@home, 'picker_calls')
    launchctl_log = File.join(@home, 'launchctl_calls')
    FileUtils.mkdir_p(bin)
    FileUtils.rm_f([picker_log, launchctl_log]) # calls of this run only
    File.write(File.join(bin, 'osascript'), <<~SH)
      #!/bin/bash
      case "$*" in
        *"choose file"*) printf '%s\\n' "$*" >> "#{picker_log}"; [ -n "$PICKED" ] || exit 1; echo "$PICKED"; exit 0 ;;
      esac
      echo "unexpected osascript call: $*" >&2; exit 1
    SH
    # Never the real launchctl: it would load the agent into this session
    File.write(File.join(bin, 'launchctl'), <<~SH)
      #!/bin/bash
      [ "$1" = print ] && exit "$PRINT_STATUS"
      printf '%s\\n' "$*" >> "#{launchctl_log}"
    SH
    %w[osascript launchctl].each { File.chmod(0o755, File.join(bin, _1)) }
    env = {
      'PATH' => "#{bin}:#{ENV['PATH']}",
      'alfred_version' => (alfred ? '5.5' : nil),
      'PICKED' => picked,
      'APW_LAUNCH_SCRIPT' => launch_script,
      'PRINT_STATUS' => (loaded ? '0' : '113') # 113: launchctl's "could not find service"
    }
    out, @err, @status = run_script('setup_workflow.rb', *args, env: env)
    @picker_calls = File.exist?(picker_log) ? File.readlines(picker_log, chomp: true) : []
    @launchctl_calls = File.exist?(launchctl_log) ? File.readlines(launchctl_log, chomp: true) : []
    return out.lines.grep(/alfredworkflow/) unless alfred # Terminal: plain progress output only
    # Alfred reads the whole stdout as one JSON object, so nothing else may be printed there
    if out.empty?
      []
    else
      [ JSON.parse(out)['alfredworkflow'].then { [_1['arg'], _1['variables']['notification_title']] } ]
    end
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
    assert @status.success? # exits 0 so that Alfred still shows the notification
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

  def agent = File.join(@home, 'Library/LaunchAgents/sh.less-software.psw-workflow.apw-auth.plist')

  def test_alfred_installs_apw_auth_agent_once
    notifications_from # even when the picker is canceled
    assert_equal ["bootstrap gui/#{Process.uid} #{agent}"], @launchctl_calls
    assert system('plutil', '-lint', '-s', agent), File.read(agent)
    assert_includes File.read(agent), File.join(ROOT, 'launch_agent/agent_script.sh')

    notifications_from
    assert_empty @launchctl_calls # already installed
  end

  def test_apw_auth_agent_uninstalls_itself_with_the_workflow
    notifications_from
    args = JSON.parse(IO.popen(['plutil', '-extract', 'ProgramArguments', 'json', '-o', '-', agent], &:read))
    assert_equal File.join(ROOT, 'launch_agent/agent_script.sh'), args[3]
    # Never runs the real agent_script.sh
    args[3] = File.join(@home, 'deleted-workflow/src/launch_agent/agent_script.sh')
    _, err, st = Open3.capture3({ 'PATH' => "#{@home}/bin:#{ENV['PATH']}" }, *args)
    assert st.success?, err
    refute File.exist?(agent)
    assert_equal "bootout gui/#{Process.uid}/sh.less-software.psw-workflow.apw-auth",
      File.readlines(File.join(@home, 'launchctl_calls'), chomp: true).last
  end

  def test_alfred_reinstalls_changed_apw_auth_agent
    notifications_from
    File.write(agent, File.read(agent).sub('900', '60'))
    notifications_from
    assert_equal ["bootout gui/#{Process.uid}/sh.less-software.psw-workflow.apw-auth", "bootstrap gui/#{Process.uid} #{agent}"], @launchctl_calls
    assert_includes File.read(agent), '900'
  end

  def test_alfred_reloads_unloaded_apw_auth_agent # for example after a manual bootout
    notifications_from
    notifications_from(loaded: false)
    assert_equal ["bootout gui/#{Process.uid}/sh.less-software.psw-workflow.apw-auth",
                  "bootstrap gui/#{Process.uid} #{agent}"], @launchctl_calls
  end

  def test_alfred_apw_auth_agent_failure_keeps_the_cache
    FileUtils.mkdir_p(File.dirname(agent))
    File.chmod(0o555, File.dirname(agent)) # e.g. ~/Library/LaunchAgents left owned by root
    write_csv
    assert_equal [['Cache updated: 2 items', 'Apple Passwords']], notifications_from(@csv)
    assert_match(/Couldn't install the apw auth LaunchAgent/, @err)
  end

  def test_alfred_apw_launch_script_unchecked
    notifications_from(launch_script: '0')
    refute File.exist?(agent)
    assert_empty @launchctl_calls

    notifications_from
    notifications_from(launch_script: '0') # removes an installed agent
    refute File.exist?(agent)
    assert_equal ["bootout gui/#{Process.uid}/sh.less-software.psw-workflow.apw-auth"], @launchctl_calls
  end

  # As agent_script.sh does, without a locale or the workflow's variables
  def test_generate_launch_agent_run_directly
    notifications_from(launch_script: '0') # only creates the fake launchctl
    env = {
      'HOME' => @home,
      'PATH' => "#{@home}/bin:#{ENV['PATH']}",
      'LANG' => nil,
      'LC_ALL' => nil,
      'LC_CTYPE' => nil
    }
    _, err, st = Open3.capture3(env, RbConfig.ruby, File.join(ROOT, 'launch_agent/generate.rb'))
    assert st.success?, err
    assert system('plutil', '-lint', '-s', agent), File.read(agent)
    assert_equal ["bootstrap gui/#{Process.uid} #{agent}"], File.readlines(File.join(@home, 'launchctl_calls'), chomp: true)
  end

  def test_terminal_does_not_install_apw_auth_agent
    notifications_from(alfred: false)
    refute File.exist?(agent)
  end
end
