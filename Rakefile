require 'rake/testtask'

Rake::TestTask.new { _1.pattern = 'test/*_test.rb' }

task default: :test

WORKFLOW_FILES = %w[info.plist icon.png alfred_filter_script.rb setup_cache.rb action.sh alternative_action.sh copy_secret.sh]

def version
  @version ||= `plutil -extract version raw info.plist`.strip.tap do |v|
    abort 'No version in info.plist' unless $?.success? && !v.empty?
  end
end

def package_path = "releases/alfred-psw-workflow-#{version}.alfredworkflow"

def tag?(name) = system('git', 'rev-parse', '-q', '--verify', "refs/tags/#{name}", out: File::NULL)

desc 'Set info.plist version in a dedicated commit, tagged with it: rake "bump[v1.0.0]"'
task :bump, [:version] do |_, args|
  v = args[:version] or abort 'Usage: rake "bump[v1.0.0]"'
  abort "Tag #{v} already exists" if tag?(v)
  abort 'info.plist has uncommitted changes' unless system('git', 'diff', '--quiet', 'HEAD', '--', 'info.plist')
  sh 'plutil', '-replace', 'version', '-string', v, 'info.plist'
  sh 'git', 'commit', '-q', '-m', "Release #{v}", '--', 'info.plist'
  sh 'git', 'tag', '-a', v, '-m', v
end

desc 'Build releases/alfred-psw-workflow-<version>.alfredworkflow from the git tag named after the info.plist version'
task :package do
  abort "No tag #{version}: run rake \"bump[#{version}]\"" unless tag?(version)
  mkdir_p 'releases'
  sh 'git', 'archive', '--format=zip', '-o', package_path, version, '--', *WORKFLOW_FILES
end

desc 'Create a GitHub release from the pushed <version> tag with the package (built only if missing)'
task :release do
  # A tag never moves, so an existing package for this version is already the tag's content.
  Rake::Task[:package].invoke unless File.exist?(package_path)
  args = ['gh', 'release', 'create', version, package_path, '--verify-tag', '--title', version, '--generate-notes']
  args << '--prerelease' if version.include?('-')
  sh(*args)
end
