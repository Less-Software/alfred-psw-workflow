# Covers agent_script.sh, run by the LaunchAgent pswsetup installs.
require 'minitest/autorun'
require 'open3'
require 'tmpdir'
require 'fileutils'

class AgentTest < Minitest::Test
  parallelize_me! # each test uses its own temp dir

  # Fakes prepended to PATH, logging their calls to $FAKE_DIR/calls. apw: `pw list` exits LIST_STATUS (9: not
  # authenticated), `auth request` exits REQUEST_STATUS, and PIN 111111 is wrong. Dialogs add their text to
  # $FAKE_DIR/dialogs; the Nth one answers the Nth line of PIN, or is canceled when there is none.
  # sleep returns at once.
  FAKES = {
    'brew' => %(echo "$FAKE_DIR"),
    'ruby' => %(echo "ruby ${1##*/}" >> "$FAKE_DIR/calls"),
    'apw' => <<~'SH',
      echo "apw $*" >> "$FAKE_DIR/calls"
      case "$*" in
        'pw list'*) exit "$LIST_STATUS" ;;
        'auth request') exit "${REQUEST_STATUS:-0}" ;;
        'auth response --pin 111111') exit 9 ;;
      esac
    SH
    'osascript' => <<~'SH',
      echo dialog >> "$FAKE_DIR/calls"; echo "${@: -1}" >> "$FAKE_DIR/dialogs"
      pin=$(printf '%s\n' "$PIN" | sed -n "$(grep -c dialog "$FAKE_DIR/calls")p")
      [ -n "$pin" ] || exit 1; echo "$pin"
    SH
    'sleep' => 'exit 0'
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

  # Returns the fakes' calls
  def run_script(list_status:, pin: '', request_status: 0)
    env = {
      'PATH' => "#{@dir}/bin:#{ENV['PATH']}",
      'FAKE_DIR' => @dir,
      'LIST_STATUS' => list_status.to_s,
      'REQUEST_STATUS' => request_status.to_s,
      'PIN' => pin
    }
    FileUtils.rm_f(%w[calls dialogs].map { File.join(@dir, _1) }) # this run only
    _, err, st = Open3.capture3(env, File.expand_path('../src/launch_agent/agent_script.sh', __dir__))
    assert st.success?, err
    File.readlines(File.join(@dir, 'calls'), chomp: true)
  end

  UPDATE = 'ruby generate.rb'

  def test_authenticated
    assert_equal [UPDATE, 'apw pw list example.invalid'], run_script(list_status: 3) # 3: no results
  end

  def test_not_authenticated
    assert_equal [UPDATE, 'apw pw list example.invalid', 'apw auth request', 'dialog', 'apw auth response --pin 123456'],
      run_script(list_status: 9, pin: " 123456\n")
  end

  def test_wrong_pin_asks_again_with_a_new_pin
    assert_equal [UPDATE, 'apw pw list example.invalid',
                  'apw auth request', 'dialog', 'apw auth response --pin 111111',
                  'apw auth request', 'dialog', 'apw auth response --pin 123456'],
      run_script(list_status: 9, pin: "111111\n123456")
    assert_match(/\AWrong PIN/, File.readlines(File.join(@dir, 'dialogs')).last)
  end

  def test_daemon_not_answering # not running, or still starting (at login): retried for 30 seconds
    assert_equal [UPDATE, 'apw pw list example.invalid', *['apw auth request'] * 6, 'dialog'],
      run_script(list_status: 9, request_status: 9)
    dialog = File.read(File.join(@dir, 'dialogs'))
    assert_includes dialog, 'brew services restart apw'
    assert_includes dialog, 'apw start'
  end

  def test_dialog_canceled
    assert_equal [UPDATE, 'apw pw list example.invalid', 'apw auth request', 'dialog'], run_script(list_status: 9)
  end
end
