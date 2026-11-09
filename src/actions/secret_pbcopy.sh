#!/bin/bash
# Copies stdin to the clipboard marked as secret, then clears it after $KEEP_CLIPBOARD_DELAY seconds (default 30)
# unless something else was copied meanwhile. PASTEBOARD_NAME (tests only) uses a private pasteboard instead.

# Marks the copy as concealed and transient (nspasteboard.org) so clipboard managers don't record it,
# and keeps it off Universal Clipboard. Prints the pasteboard change count, to detect later copies.
COPY_JS=$(cat <<'JS'
ObjC.import('AppKit')
function run() {
  const name = ObjC.unwrap($.NSProcessInfo.processInfo.environment.objectForKey('PASTEBOARD_NAME'))
  const pb = name ? $.NSPasteboard.pasteboardWithName(name) : $.NSPasteboard.generalPasteboard
  const data = $.NSFileHandle.fileHandleWithStandardInput.readDataToEndOfFile
  const secret = $.NSString.alloc.initWithDataEncoding(data, $.NSUTF8StringEncoding)
  pb.prepareForNewContentsWithOptions($.NSPasteboardContentsCurrentHostOnly)
  if (!pb.setStringForType(secret, $.NSPasteboardTypeString)) throw new Error('cannot write to the clipboard')
  pb.setStringForType($(''), 'org.nspasteboard.ConcealedType')
  pb.setStringForType($(''), 'org.nspasteboard.TransientType')
  return pb.changeCount
}
JS
)

CLEAR_JS=$(cat <<'JS'
ObjC.import('AppKit')
function run(argv) {
  const name = ObjC.unwrap($.NSProcessInfo.processInfo.environment.objectForKey('PASTEBOARD_NAME'))
  const pb = name ? $.NSPasteboard.pasteboardWithName(name) : $.NSPasteboard.generalPasteboard
  if (pb.changeCount == Number(argv[0])) pb.clearContents
}
JS
)

DELAY=${KEEP_CLIPBOARD_DELAY:-30}
# Checked before copying: if sleep rejected it, the secret would never be cleared
[[ $DELAY =~ ^[0-9]+(\.[0-9]+)?$ ]] || { echo "KEEP_CLIPBOARD_DELAY must be a number of seconds: $DELAY" >&2; exit 1; }

COUNT=$(osascript -l JavaScript -e "$COPY_JS") || exit 1

# Detached, with every stream closed, so Alfred doesn't wait for it; it holds the change count, never the secret
(sleep "$DELAY"; osascript -l JavaScript -e "$CLEAR_JS" "$COUNT") </dev/null >/dev/null 2>&1 &
