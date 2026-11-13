<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<!-- Filled in by generate_launch_agent.rb: its placeholders get XML-escaped values -->
<plist version="1.0">
<dict>
	<key>Label</key>
	<string>%{label}</string>
	<!-- Deleting the workflow deletes agent.sh: the agent then deletes its plist and unloads itself.
	     Arguments: $0 agent.sh, $1 this plist, $2 the label -->
	<key>ProgramArguments</key>
	<array>
		<string>/bin/bash</string>
		<string>-c</string>
		<string>if [ -f "$0" ]; then exec /bin/bash "$0"; fi; rm -f "$1"; launchctl bootout "gui/$(id -u)/$2"</string>
		<string>%{script}</string>
		<string>%{plist}</string>
		<string>%{label}</string>
	</array>
	<!-- launchd's PATH lacks Homebrew, which agent.sh calls like the workflow's other scripts -->
	<key>EnvironmentVariables</key>
	<dict>
		<key>PATH</key>
		<string>%{path}</string>
	</dict>
	<key>RunAtLoad</key>
	<true/>
	<key>StartInterval</key>
	<integer>900</integer>
</dict>
</plist>
