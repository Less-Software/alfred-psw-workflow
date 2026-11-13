# encoding: utf-8

# Installs, updates or removes the LaunchAgent that runs agent_script.sh at login and every 15 minutes
# to keep apw authenticated. setup_workflow.rb (pswsetup) calls it, and agent_script.sh runs it
# directly so that a workflow update that changes the template also updates the installed agent.

require 'fileutils'

LAUNCH_AGENT_TEMPLATE = File.expand_path('sh.less-software.psw-workflow.apw-auth.plist.tpl', __dir__)

# The "APW Launch Agent" checkbox (APW_LAUNCH_SCRIPT: "1" or "0") installs it, or removes it when unchecked.
# Under launchd, which doesn't pass the workflow's variables, it is unset: the agent keeps itself installed.
def generate_launch_agent
  label = File.basename(LAUNCH_AGENT_TEMPLATE, '.plist.tpl')
  path = File.expand_path("~/Library/LaunchAgents/#{label}.plist")
  service = "gui/#{Process.uid}/#{label}"
  installed = File.exist?(path)

  if ENV['APW_LAUNCH_SCRIPT'] == '0'
    return unless installed
    system('launchctl', 'bootout', service, err: File::NULL)
    return File.delete(path)
  end

  # Without a locale (LANG unset, as under launchd), paths are tagged BINARY
  values = {
    label:,
    script: File.expand_path('agent_script.sh', __dir__),
    plist: path,
    path: ENV['PATH'].to_s
  }.transform_values { _1.dup.force_encoding(Encoding::UTF_8).encode(xml: :text) }

  # Interpolate variables
  plist = File.read(LAUNCH_AGENT_TEMPLATE, encoding: 'utf-8').gsub(/%\{(\w+)\}/) { values.fetch($1.to_sym) }
  # Rewritten when the template or a value changed, reloaded when launchd hasn't loaded it
  loaded = system('launchctl', 'print', service, out: File::NULL, err: File::NULL)
  return if installed && loaded && File.binread(path) == plist.b

  FileUtils.mkdir_p(File.dirname(path))
  File.write(path, plist)
  # Run from agent_script.sh, bootout kills the agent's process group: reload from a group of its own
  # so that bootstrap still runs. The new agent then runs at once (RunAtLoad).
  reload = ''
  reload += 'launchctl bootout "$0/$2" 2>/dev/null; ' if installed
  reload += 'launchctl bootstrap "$0" "$1"'

  Process.wait(spawn('/bin/sh', '-c', reload, "gui/#{Process.uid}", path, label, pgroup: true))

  STDERR.puts "Couldn't load the LaunchAgent #{path}" unless $?.success?
end

generate_launch_agent if __FILE__ == $0
