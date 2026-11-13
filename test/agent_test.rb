# Covers agent.sh, run by the LaunchAgent pswsetup installs.
require 'minitest/autorun'
require 'open3'
require 'tmpdir'
require 'fileutils'

class AgentTest < Minitest::Test
  parallelize_me! # each test uses its own temp dir

  # Fakes prepended to PATH, logging their calls to $FAKE_DIR/calls. `apw pw list` exits LIST_STATUS (9: not
  # authenticated); dialogs save their text to $FAKE_DIR/dialog, and the PIN one answers PIN, or is canceled when it
  # is empty; pgrep lists PROCESSES, and finds the apw daemon unless DAEMON_STOPPED is set.
  FAKES = {
    'brew' => %(echo "$FAKE_DIR"),
    'ruby' => %(echo "ruby ${1##*/}" >> "$FAKE_DIR/calls"),
    'apw' => %(echo "apw $*" >> "$FAKE_DIR/calls"; [ "$1" = pw ] && exit "$LIST_STATUS"; exit 0),
    'osascript' => %(echo "dialog" >> "$FAKE_DIR/calls"; echo "${@: -1}" > "$FAKE_DIR/dialog"
                     [ -n "$PIN" ] || exit 1; echo "$PIN"),
    'pgrep' => %([ "$*" = '-qf apw start' ] && exit "${DAEMON_STOPPED:-0}"; printf '%s' "$PROCESSES"),
    'open' => %(echo "open $*" >> "$FAKE_DIR/calls")
  }.freeze

  def setup
    @dir = Dir.mktmpdir
    FileUtils.mkdir(File.join(@dir, 'bin'))
    FAKES.each do |name, body|
      File.write(path = File.join(@dir, 'bin', name), "#!/bin/bash\n#{body}\n")
      File.chmod(0o755, path)
    end
  end

  def teardown = FileUtils.rm_rf(@dir)

  CHROME = '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome'
  USER_CHROME = "101 #{CHROME}\n"
  # apw's headless Chrome, as `pgrep -lf "Google Chrome.app"` lists it
  APW_CHROME = <<~PS
    201 #{CHROME} --user-data-dir=/Users/me/.apw/browser/chrome --headless=new
    202 /Applications/Google Chrome.app/Contents/Frameworks/Helpers/chrome_crashpad_handler --database=/Users/me/Library/Application Support/Google/Chrome/Crashpad
    203 /Applications/Google Chrome.app/Contents/Frameworks/Helpers/Google Chrome Helper --type=renderer --user-data-dir=/Users/me/.apw/browser/chrome
  PS

  # Returns the fakes' calls
  def run_script(list_status:, pin: '', processes: USER_CHROME + APW_CHROME, daemon_stopped: false)
    env = { 'PATH' => "#{@dir}/bin:#{ENV['PATH']}", 'FAKE_DIR' => @dir, 'LIST_STATUS' => list_status.to_s,
            'PIN' => pin, 'PROCESSES' => processes, 'DAEMON_STOPPED' => (daemon_stopped ? '1' : nil) }
    FileUtils.rm_f(File.join(@dir, 'calls')) # calls of this run only
    _, err, st = Open3.capture3(env, File.expand_path('../src/agent.sh', __dir__))
    assert st.success?, err
    File.readlines(File.join(@dir, 'calls'), chomp: true)
  end

  UPDATE = 'ruby generate_launch_agent.rb'

  def test_authenticated
    assert_equal [UPDATE, 'apw pw list example.invalid'], run_script(list_status: 3) # 3: no results
  end

  def test_not_authenticated
    assert_equal [UPDATE, 'apw pw list example.invalid', 'apw auth request', 'dialog', 'apw auth response --pin 123456'],
      run_script(list_status: 9, pin: " 123456\n")
  end

  def test_daemon_not_running
    assert_equal [UPDATE, 'apw pw list example.invalid', 'dialog'], run_script(list_status: 9, daemon_stopped: true)
    dialog = File.read(File.join(@dir, 'dialog'))
    assert_includes dialog, 'brew services start apw'
    assert_includes dialog, 'apw start'
  end

  def test_dialog_canceled
    assert_equal [UPDATE, 'apw pw list example.invalid', 'apw auth request', 'dialog'], run_script(list_status: 9)
  end

  def test_opens_chrome_when_only_apw_chrome_runs
    assert_equal 'open -n -g -a Google Chrome', run_script(list_status: 3, processes: APW_CHROME)[1]
    assert_equal 'open -n -g -a Google Chrome', run_script(list_status: 3, processes: '')[1]
  end
end
