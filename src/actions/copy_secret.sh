#!/bin/bash
# Copies stdin to the clipboard marked as secret, then clears it after $CLEAR_CLIPBOARD_AFTER seconds (default 30)
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

COUNT=$(osascript -l JavaScript -e "$COPY_JS") || exit 1

# Detached, with every stream closed, so Alfred doesn't wait for it; it holds the change count, never the secret
(sleep "${CLEAR_CLIPBOARD_AFTER:-30}"; osascript -l JavaScript -e "$CLEAR_JS" "$COUNT") </dev/null >/dev/null 2>&1 &
