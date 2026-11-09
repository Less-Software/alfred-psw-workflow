# Runs copy_secret.sh's real JavaScript on a private pasteboard, so the real clipboard is never touched.
require 'minitest/autorun'
require 'open3'
require 'json'
require 'securerandom'

class CopySecretTest < Minitest::Test
  SCRIPT = File.expand_path('../copy_secret.sh', __dir__)

  # Reads or writes the private pasteboard named argv[0]; with argv[1], replaces its text like another app would
  PASTEBOARD_JS = <<~JS
    ObjC.import('AppKit')
    function run(argv) {
      const pb = $.NSPasteboard.pasteboardWithName(argv[0])
      if (argv[1] === 'release') return pb.releaseGlobally
      if (argv[1] !== undefined) { pb.clearContents; pb.setStringForType(argv[1], $.NSPasteboardTypeString) }
      return JSON.stringify({ text: ObjC.unwrap(pb.stringForType($.NSPasteboardTypeString)) ?? null,
                              types: ObjC.deepUnwrap(pb.types) ?? [] })
    }
  JS

  def setup = @name = "alfred-pw-workflow-test-#{SecureRandom.hex(4)}"
  def teardown = pasteboard('release')

  def pasteboard(*args)
    out, err, st = Open3.capture3('/usr/bin/osascript', '-l', 'JavaScript', '-e', PASTEBOARD_JS, @name, *args)
    assert st.success?, err
    args.empty? ? JSON.parse(out) : out
  end

  def copy(secret, clear_after: 30)
    _, err, st = Open3.capture3({
        'PASTEBOARD_NAME' => @name,
        'CLEAR_CLIPBOARD_AFTER' => clear_after.to_s
      },
      SCRIPT,
      stdin_data: secret
    )
    assert st.success?, err
  end

  def wait_until(seconds = 5)
    deadline = Time.now + seconds
    sleep 0.1 until yield || Time.now > deadline
  end

  def test_copies_text_marked_as_secret
    copy("pä$$ \"wörd\" ☕\n")
    board = pasteboard
    assert_equal "pä$$ \"wörd\" ☕\n", board['text'] # copied as is, quotes and newline included
    assert_includes board['types'], 'org.nspasteboard.ConcealedType'
    assert_includes board['types'], 'org.nspasteboard.TransientType'
  end

  def test_clears_after_delay
    copy('s3cr3t', clear_after: 1)
    assert_equal 's3cr3t', pasteboard['text']
    wait_until { pasteboard['text'].nil? }
    assert_nil pasteboard['text']
  end

  def test_keeps_a_later_copy
    copy('s3cr3t', clear_after: 1)
    pasteboard('copied later')
    sleep 2.5 # past the delay plus osascript's startup
    assert_equal 'copied later', pasteboard['text']
  end
end
