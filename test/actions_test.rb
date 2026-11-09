# Run: "$(brew --prefix ruby)/bin/ruby" test/actions_test.rb
# Covers action.sh (password) and alternative_action.sh (OTP). Uses the system /usr/bin/jq (macOS 15+).
require 'minitest/autorun'
require 'open3'
require 'tmpdir'
require 'json'
require 'fileutils'

class ActionTest < Minitest::Test
  # Fakes prepended to PATH: osascript and pbcopy record what they get, brew points `--prefix apw` at a fake apw
  FAKES = {
    'osascript' => %(printf '%s\\n' "$2" >> "$FAKE_DIR/notifications"),
    'pbcopy' => %(cat > "$FAKE_DIR/clipboard"),
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

  def run_action(script, arg, apw_output:, apw_status: 0)
    env = { 'PATH' => "#{@dir}/bin:#{ENV['PATH']}", 'FAKE_DIR' => @dir,
            'APW_OUTPUT' => apw_output, 'APW_STATUS' => apw_status.to_s }
    _, err, st = Open3.capture3(env, File.expand_path("../#{script}", __dir__), arg)
    [st, err]
  end

  def read(name) = File.exist?(f = File.join(@dir, name)) ? File.read(f) : nil
  def notification = read('notifications')&.lines&.last.to_s

  def pw_json(*passwords) = JSON.generate(results: passwords.map { { password: _1 } })

  def otp_json(**codes) = JSON.generate(results: codes.map { |u, c| { username: u.to_s, code: c } })

  def test_password_copied
    st, err = run_action('action.sh', ' octo | github.com ', apw_output: pw_json('s3cr3t', 'other'))
    assert st.success?, err
    assert_equal "pw get github.com octo\n", read('apw_args') # spaces trimmed, domain before username
    assert_equal 's3cr3t', read('clipboard')                  # first result, no trailing newline
    assert_match(/Password copied to clipboard!/, notification)
  end

  def test_password_apw_failure
    st, = run_action('action.sh', 'octo|github.com', apw_output: pw_json('s3cr3t'), apw_status: 1)
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
    st, err = run_action('action.sh', 'octo|github.com', apw_output: JSON.generate(results: []))
    assert st.success?, err
    assert_nil read('clipboard')
    assert_match(/Failed to parse password from JSON/, notification)
  end

  def test_otp_copied_for_matching_username
    st, err = run_action('alternative_action.sh', ' octo | github.com ',
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

  def test_otp_no_matching_username
    st, err = run_action('alternative_action.sh', 'octo|github.com', apw_output: otp_json(alice: '111111'))
    assert st.success?, err
    assert_nil read('clipboard')
    assert_match(/No OTP found for this username/, notification)
  end
end
