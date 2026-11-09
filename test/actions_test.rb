# Covers action.sh (password) and alternative_action.sh (OTP). Uses the system /usr/bin/jq (macOS 15+).
require 'minitest/autorun'
require 'open3'
require 'tmpdir'
require 'json'
require 'fileutils'

class ActionTest < Minitest::Test
  parallelize_me! # each test uses its own temp dir or pasteboard, so they can share the process
  # Fakes prepended to PATH: brew points `--prefix apw` at a fake apw, osascript records notifications.
  # osascript also stands in for copy_secret.sh's JavaScript: the copy writes stdin to a file (fails if COPY_FAILS
  # is set) and the delayed clear does nothing. copy_secret_test.rb covers the real JavaScript.
  FAKES = {
    'osascript' => <<~'SH',
      if [ "$1" = -l ]; then
        case "$*" in *clearContents*) exit 0 ;; esac
        [ -z "$COPY_FAILS" ] || exit 1
        cat > "$FAKE_DIR/clipboard"; echo 1; exit 0
      fi
      printf '%s\n' "$2" >> "$FAKE_DIR/notifications"
    SH
    'brew' => %(echo "$FAKE_DIR"),
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
    _, err, st = Open3.capture3(env, File.expand_path("../#{script}", __dir__), arg)
    [st, err]
  end

  def read(name) = File.exist?(f = File.join(@dir, name)) ? File.read(f) : nil
  def notification = read('notifications')&.lines&.last.to_s

  def pw_json(**passwords) = JSON.generate(results: passwords.map { |u, p| { username: u.to_s, password: p } })

  def otp_json(**codes) = JSON.generate(results: codes.map { |u, c| { username: u.to_s, code: c } })

  def test_password_copied_for_matching_username
    st, err = run_action('action.sh', 'octo|github.com', apw_output: pw_json(alice: 'other', octo: 's3cr3t'))
    assert st.success?, err
    assert_equal "pw get github.com octo\n", read('apw_args') # domain before username
    assert_equal 's3cr3t', read('clipboard')                  # matching account, no trailing newline
    assert_match(/Password copied to clipboard!/, notification)
  end

  def test_username_with_quote_and_pipe
    user = %q(o'brien|"x")
    st, err = run_action('action.sh', "#{user}|github.com", apw_output: pw_json(user => 's3cr3t'))
    assert st.success?, err
    assert_equal "pw get github.com #{user}\n", read('apw_args')
    assert_equal 's3cr3t', read('clipboard')
  end

  def test_password_apw_failure
    st, = run_action('action.sh', 'octo|github.com', apw_output: pw_json(octo: 's3cr3t'), apw_status: 1)
    refute st.success?
    assert_nil read('clipboard')
    assert_match(/apw execution failed or canceled/, notification)
  end

  def test_password_empty_output
    st, = run_action('action.sh', 'octo|github.com', apw_output: '')
    refute st.success?
    assert_match(/apw execution failed or canceled/, notification)
  end

  def test_password_missing_in_json
    [JSON.generate(results: []), pw_json(alice: 'other')].each do |output|
      st, err = run_action('action.sh', 'octo|github.com', apw_output: output)
      assert st.success?, err
      assert_nil read('clipboard')
      assert_match(/No Password found for this username/, notification)
    end
  end

  def test_otp_copied_for_matching_username
    st, err = run_action('alternative_action.sh', 'octo|github.com',
                         apw_output: otp_json(alice: '111111', octo: '222222'))
    assert st.success?, err
    assert_equal "otp get github.com\n", read('apw_args')
    assert_equal '222222', read('clipboard')
    assert_match(/OTP copied to clipboard!/, notification)
  end

  def test_otp_apw_failure
    st, = run_action('alternative_action.sh', 'octo|github.com', apw_output: '', apw_status: 1)
    refute st.success?
    assert_nil read('clipboard')
    assert_match(/apw execution failed or canceled/, notification)
  end

  def test_copy_failure_is_reported
    [['action.sh', pw_json(octo: 's3cr3t')], ['alternative_action.sh', otp_json(octo: '222222')]].each do |script, output|
      st, err = run_action(script, 'octo|github.com', apw_output: output, env: { 'COPY_FAILS' => '1' })
      assert st.success?, err
      assert_match(/Failed to copy to clipboard/, notification, script)
    end
  end

  def test_otp_no_matching_username
    st, err = run_action('alternative_action.sh', 'octo|github.com', apw_output: otp_json(alice: '111111'))
    assert st.success?, err
    assert_nil read('clipboard')
    assert_match(/No OTP found for this username/, notification)
  end
end
