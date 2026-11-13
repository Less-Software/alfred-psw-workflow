<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<!-- Filled in by generate.rb: its placeholders get XML-escaped values -->
<plist version="1.0">
<dict>
	<key>Label</key>
	<string>%{label}</string>
	<!-- Deleting the workflow deletes agent_script.sh: the agent then deletes its plist and unloads itself.
	     Exit code 126: macOS privacy protection refused to read agent_script.sh, so say why nothing happens.
	     Arguments: $0 agent_script.sh, $1 this plist, $2 the label -->
	<key>ProgramArguments</key>
	<array>
		<string>/bin/bash</string>
		<string>-c</string>
		<string>
			if [ ! -f "$0" ]; then
				rm -f "$1"
				launchctl bootout "gui/$(id -u)/$2"
				exit 0
			fi

			/bin/bash "$0"
			[ $? -eq 126 ] || exit 0

			message="macOS blocks the apw agent from reading the workflow folder. Move Alfred's preferences"
			message+=" out of Documents, Desktop or a cloud folder, or uncheck APW Launch Agent and run pswsetup."
			osascript -e 'on run {message}' \
				-e 'display dialog message with title "Passwords.app Workflow" ¬
					buttons {"OK"} default button "OK" with icon caution' \
				-e 'end run' "$message" >/dev/null
		</string>
		<string>%{script}</string>
		<string>%{plist}</string>
		<string>%{label}</string>
	</array>
	<!-- launchd's PATH lacks Homebrew, which agent_script.sh calls like the workflow's other scripts -->
	<key>EnvironmentVariables</key>
	<dict>
		<key>PATH</key>
		<string>%{path}</string>
		<key>AGENT_LAUNCHES_CHROME</key>
		<string>%{launches_chrome}</string>
	</dict>
	<key>RunAtLoad</key>
	<true/>
	<key>StartInterval</key>
	<integer>900</integer>
</dict>
</plist>
