# Covers main.sh (password) and alt.sh (OTP). Uses the system /usr/bin/jq (macOS 15+).
require 'minitest/autorun'
require 'open3'
require 'tmpdir'
require 'json'
require 'fileutils'

class ActionTest < Minitest::Test
  parallelize_me! # each test uses its own temp dir or pasteboard, so they can share the process

  # Fakes prepended to PATH: brew points `--prefix apw` at a fake apw. osascript stands in for copy_secret.sh's
  # JavaScript: the copy writes stdin to a file (fails if COPY_FAILS is set) and the delayed clear does nothing.
  # copy_secret_test.rb covers the real JavaScript. Notifications go to stdout, for Alfred's Post Notification.
  FAKES = {
    'osascript' => <<~'SH',
      if [ "$1" = -l ]; then
        case "$*" in *clearContents*) exit 0 ;; esac
        [ -z "$COPY_FAILS" ] || exit 1
        cat > "$FAKE_DIR/clipboard"; echo 1; exit 0
      fi
      echo "unexpected osascript call: $*" >&2; exit 1
    SH
    'brew' => %(echo "$FAKE_DIR"),
    'open' => %(printf '%s\\n' "$*" > "$FAKE_DIR/open_args"; exit "${OPEN_STATUS:-0}"),
    'apw' => %(printf '%s\\n' "$*" > "$FAKE_DIR/apw_args"; printf '%s' "$APW_OUTPUT"; exit "${APW_STATUS:-0}")
  }.freeze

  def setup
    @dir = Dir.mktmpdir
    FileUtils.mkdir(File.join(@dir, 'bin'))
    FAKES.each do |name, body|
      path = File.join(@dir, 'bin', name)
      File.write(path, "#!/bin/bash\n#{body}\n")
      File.chmod(0o755, path)
    end
  end

  def teardown = FileUtils.rm_rf(@dir)

  def run_action(script, arg, apw_output:, apw_status: 0, env: {})
    env = { 'PATH' => "#{@dir}/bin:#{ENV['PATH']}", 'FAKE_DIR' => @dir, 'CLEAR_CLIPBOARD_AFTER' => '0',
            'APW_OUTPUT' => apw_output, 'APW_STATUS' => apw_status.to_s, **env }
    @out, err, st = Open3.capture3(env, File.expand_path("../src/actions/#{script}", __dir__), arg)
    [st, err]
  end

  def read(name) = File.exist?(f = File.join(@dir, name)) ? File.read(f) : nil
  # Alfred reads the whole stdout as one JSON object: returns [message, title]
  def notification = JSON.parse(@out)['alfredworkflow'].then { [_1['arg'], _1['variables']['notification_title']] }

  def pw_json(**passwords) = JSON.generate(results: passwords.map { |u, p| { username: u.to_s, password: p } })

  def otp_json(**codes) = JSON.generate(results: codes.map { |u, c| { username: u.to_s, code: c } })

  def test_password_copied_for_matching_username
    st, err = run_action('main.sh', 'octo|github.com', apw_output: pw_json(alice: 'other', octo: 's3cr3t'))
    assert st.success?, err
    assert_equal "pw get github.com octo\n", read('apw_args') # domain before username
    assert_equal 's3cr3t', read('clipboard')                  # matching account, no trailing newline
    assert_equal ['Password copied to clipboard!', 'Apple Passwords'], notification
  end

  def test_username_with_quote_and_pipe
    user = %q(o'brien|"x")
    st, err = run_action('main.sh', "#{user}|github.com", apw_output: pw_json(user => 's3cr3t'))
    assert st.success?, err
    assert_equal "pw get github.com #{user}\n", read('apw_args')
    assert_equal 's3cr3t', read('clipboard')
  end

  def test_password_apw_failure
    st, err = run_action('main.sh', 'octo|github.com', apw_output: pw_json(octo: 's3cr3t'), apw_status: 1)
    assert st.success?, err # exits 0 so that Alfred still shows the notification
    assert_nil read('clipboard')
    assert_equal ['apw execution failed or canceled', 'Error'], notification
  end

  def test_password_empty_output
    st, err = run_action('main.sh', 'octo|github.com', apw_output: '')
    assert st.success?, err
    assert_equal ['apw execution failed or canceled', 'Error'], notification
  end

  def test_password_missing_in_json
    [JSON.generate(results: []), pw_json(alice: 'other')].each do |output|
      st, err = run_action('main.sh', 'octo|github.com', apw_output: output)
      assert st.success?, err
      assert_nil read('clipboard')
      assert_equal ['No Password found for this username', 'Error'], notification
    end
  end

  def test_otp_copied_for_matching_username
    st, err = run_action('alt.sh', 'octo|github.com',
                         apw_output: otp_json(alice: '111111', octo: '222222'))
    assert st.success?, err
    assert_equal "otp get github.com\n", read('apw_args')
    assert_equal '222222', read('clipboard')
    assert_equal ['OTP copied to clipboard!', 'Apple Passwords'], notification
  end

  def test_otp_apw_failure
    st, err = run_action('alt.sh', 'octo|github.com', apw_output: '', apw_status: 1)
    assert st.success?, err
    assert_nil read('clipboard')
    assert_equal ['apw execution failed or canceled', 'Error'], notification
  end

  def test_copy_failure_is_reported
    [['main.sh', pw_json(octo: 's3cr3t')], ['alt.sh', otp_json(octo: '222222')]].each do |script, output|
      st, err = run_action(script, 'octo|github.com', apw_output: output, env: { 'COPY_FAILS' => '1' })
      assert st.success?, err
      assert_equal ['Failed to copy to clipboard', 'Error'], notification, script
    end
  end

  def test_no_website_opens_passwords
    %w[main.sh alt.sh].each do |script|
      st, err = run_action(script, 'solo|', apw_output: '')
      assert st.success?, err
      assert_equal "-b com.apple.Passwords\n", read('open_args'), script
      assert_nil read('apw_args'), script # apw can't look up an entry without a website
      assert_empty @out, script           # Passwords opening is the feedback: no notification
    end
  end

  def test_no_website_open_failure_is_reported
    st, err = run_action('main.sh', 'solo|', apw_output: '', env: { 'OPEN_STATUS' => '1' })
    assert st.success?, err
    assert_equal ["Couldn't open Passwords", 'Error'], notification
  end

  def test_otp_no_matching_username
    st, err = run_action('alt.sh', 'octo|github.com', apw_output: otp_json(alice: '111111'))
    assert st.success?, err
    assert_nil read('clipboard')
    assert_equal ['No OTP found for this username', 'Error'], notification
  end
end
