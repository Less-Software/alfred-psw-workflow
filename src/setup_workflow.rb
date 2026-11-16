#!/bin/sh
# A shebang can't call brew: re-run with Homebrew's ruby; -x makes ruby skip to the #!ruby line
exec "$(brew --prefix ruby)/bin/ruby" -x "$0" "$@"
#!ruby
# encoding: utf-8

require 'csv'
require 'json'
require 'base64'
require 'fileutils'
require 'securerandom'
require 'uri'
require_relative 'cache_key'
require_relative 'launch_agent/generate'

# In Alfred, stdout goes to the Post Notification output (which shows the workflow icon), so it must hold
# only that message: progress lines go to stderr, shown in Alfred's debugger. Terminal keeps both streams.
NOTIFICATION_OUT = $stdout
$stdout = $stderr if ENV['alfred_version']

def notify(message, title)
  return unless ENV['alfred_version']
  NOTIFICATION_OUT.puts JSON.generate(alfredworkflow: { arg: message, variables: { notification_title: title } })
end

def fail!(message)
  STDERR.puts message
  notify(message, 'Error')
  exit(ENV['alfred_version'] ? 0 : 1) # Alfred may not run the notification after a failed script
end

begin
  generate_launch_agent if ENV['alfred_version']
rescue => e # the agent is optional: it must never block the cache
  STDERR.puts "Couldn't install the apw auth LaunchAgent: #{e.message}"
end

csv_arg = ARGV[0].to_s

# The pswsetup keyword passes no file: ask for one with a file picker
if csv_arg.empty? && ENV['alfred_version']
  # activate brings osascript's dialog in front of other windows
  csv_arg = IO.popen(['osascript', '-e', 'activate', '-e', 'POSIX path of (choose file with prompt ' \
                      '"Select your Passwords CSV export" of type {"public.comma-separated-values-text"})'], &:read).strip
  exit 0 unless $?.success? # picker canceled
end

fail! "Usage: #{File.basename($0)} <Passwords.csv>" if csv_arg.empty?

csv_path = File.expand_path(csv_arg)

fail! "Error: Passwords CSV file not found at #{csv_path}" unless File.exist?(csv_path)

# Only a Passwords export holds secrets that must be deleted: leave any other CSV untouched
begin
  headers = CSV.open(csv_path, encoding: 'utf-8', &:shift)
rescue CSV::MalformedCSVError => e
  fail! "Error: unable to parse #{csv_path}: #{e.message}"
end
fail! "Error: #{csv_path} is not a Passwords export (no Password column), left untouched" unless headers&.include?('Password')

# CRITICAL SECURITY STEP: overwrite then remove the CSV however the script ends (failed seed, parse error, exception…)
at_exit do
  if File.exist?(csv_path)
    # shortcut: one in-place overwrite; SSD wear leveling or an APFS snapshot can still keep the old data, only a RAM disk avoids that
    begin
      File.open(csv_path, 'r+b') { |f| f.write("\0" * f.size); f.fsync }
    rescue SystemCallError => e # e.g. a read-only file: still delete it below
      STDERR.puts "Couldn't overwrite #{csv_path}: #{e.message}"
    end
    File.delete(csv_path)
    puts "Secure cleanup: CSV file overwritten and removed successfully."
  end
end

# 1. Derive encryption key from seed (generated on first run)
begin
  unless read_seed
    store_seed(SecureRandom.hex(32))
    puts 'Generated new seed in the Keychain'
  end
  key = cache_key
rescue => e
  fail! "Error reading seed: #{e.message}"
end

# 2. Parse the CSV file efficiently
cache_items = []
begin
  # CSV headers: Title,URL,Username,Password,Notes,OTPAuth
  CSV.foreach(csv_path, headers: true, encoding: 'utf-8') do |row|
    title = row['Title']
    url = row['URL'].to_s
    domain = begin
      uri = URI.parse(url)
      uri.port == uri.default_port ? uri.host : "#{uri.host}:#{uri.port}"
    rescue URI::InvalidURIError
      url[%r{//([^/?#]+)}, 1] # URI rejects non-ASCII hosts and spaces: keep the raw host instead of failing the sync
    end
    username = row['Username']

    next if title.nil? && domain.nil? && username.nil?

    cache_items << {
      'title' => title.to_s.strip,
      'domain' => domain.to_s.strip,
      'username' => username.to_s.strip
    }
  end
rescue CSV::MalformedCSVError => e
  fail! "Error: unable to parse #{csv_path}: #{e.message}"
end

# 3. Encrypt the parsed metadata payload (No passwords are ever stored in cache)
cipher = OpenSSL::Cipher.new(CIPHER)
cipher.encrypt
cipher.key = key
iv = cipher.random_iv
cipher.iv = iv

json_payload = JSON.generate(cache_items)
encrypted_data = cipher.update(json_payload) + cipher.final

store_payload = {
  'iv' => Base64.strict_encode64(iv),
  'data' => Base64.strict_encode64(encrypted_data)
}

# Write aside (mode 600 from creation) then rename: a failed write keeps the previous cache intact
FileUtils.mkdir_p(File.dirname(CACHE_PATH))
File.write("#{CACHE_PATH}.tmp", JSON.generate(store_payload), perm: 0600)
File.rename("#{CACHE_PATH}.tmp", CACHE_PATH)

puts "Cache updated and securely encrypted successfully at #{CACHE_PATH} (#{cache_items.size} items processed)."
notify("Cache updated: #{cache_items.size} items", 'Apple Passwords')
