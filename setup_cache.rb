#!/bin/sh
# A shebang can't call brew: re-run with Homebrew's ruby; -x makes ruby skip to the #!ruby line
exec "$(brew --prefix ruby)/bin/ruby" -x "$0" "$@"
#!ruby
# encoding: utf-8

require 'csv'
require 'json'
require 'openssl'
require 'base64'
require 'fileutils'
require 'securerandom'
require 'uri'

PROJECT_NAME = 'alfred-pw-workflow'
SEED_PATH = File.expand_path("~/.config/#{PROJECT_NAME}/seed")
CACHE_PATH = File.expand_path("~/.cache/#{PROJECT_NAME}/apw_cache.enc")
CIPHER = 'AES-256-CBC'
DIGEST = OpenSSL::Digest.new('SHA1')
SALT = PROJECT_NAME

# Alfred's File Action shows no output, so report there with a notification; Terminal has stdout/stderr
def notify(message, title)
  return unless ENV['alfred_version']
  # Pass the text as arguments, not inside the AppleScript source, so quotes in paths can't break it
  system('osascript', '-e', 'on run argv', '-e', 'display notification (item 1 of argv) with title (item 2 of argv)',
         '-e', 'end run', message, title)
end

def fail!(message)
  STDERR.puts message
  notify(message, 'Error')
  exit 1
end

csv_arg = ARGV[0].to_s

# The pwsync keyword passes no file: ask for one with a file picker
if csv_arg.empty? && ENV['alfred_version']
  # activate brings osascript's dialog in front of other windows
  csv_arg = IO.popen(['osascript', '-e', 'activate', '-e', 'POSIX path of (choose file with prompt ' \
                      '"Select your Passwords CSV export" of type {"public.comma-separated-values-text"})'], &:read).strip
  exit 0 unless $?.success? # picker canceled
end

fail! "Usage: #{File.basename($0)} <Passwords.csv>" if csv_arg.empty?

csv_path = File.expand_path(csv_arg)

fail! "Error: Passwords CSV file not found at #{csv_path}" unless File.exist?(csv_path)

# 1. Derive encryption key from seed (generated on first run)
begin
  unless File.exist?(SEED_PATH)
    FileUtils.mkdir_p(File.dirname(SEED_PATH), mode: 0700)
    File.open(SEED_PATH, File::WRONLY | File::CREAT | File::EXCL, 0600) { |f| f.write(SecureRandom.hex(32)) }
    puts "Generated new seed at #{SEED_PATH}"
  end
  seed = File.read(SEED_PATH).strip
  raise "seed file #{SEED_PATH} is empty" if seed.empty?
  # Bind the key to this Mac: a copied seed + cache is useless elsewhere
  hw_uuid = `/usr/sbin/ioreg -rd1 -c IOPlatformExpertDevice`[/"IOPlatformUUID" = "([^"]+)"/, 1]
  raise 'cannot read hardware UUID' unless hw_uuid
  key = OpenSSL::PKCS5.pbkdf2_hmac(seed, "#{SALT}|#{hw_uuid}", 10000, 32, DIGEST)
rescue => e
  fail! "Error reading seed: #{e.message}"
end

# 2. Parse the CSV file efficiently
cache_items = []
begin
  # CSV headers: Title,domain,Username,Password,Notes,OTPAuth
  CSV.foreach(csv_path, headers: true, encoding: 'utf-8') do |row|
    title = row['Title']
    if row['URL'] && !row['URL'].empty?
      url = URI.parse(row['URL'])
      domain = url.host
      domain = "#{domain}:#{url.port}" unless url.port == url.default_port
    end
    username = row['Username']

    next if title.nil? && domain.nil? && username.nil?

    # Generate a unique identifier based on title/domain/username combination
    id_string = "#{title}|#{domain}|#{username}"
    item_id = Digest::SHA1.hexdigest(id_string)[0..12]

    cache_items << {
      'id' => item_id,
      'title' => title.to_s.strip,
      'domain' => domain.to_s.strip,
      'username' => username.to_s.strip
    }
  end
rescue CSV::MalformedCSVError, URI::InvalidURIError => e
  fail! "Error: unable to parse #{csv_path}: #{e.message}"
ensure
  # CRITICAL SECURITY STEP: Remove the CSV file immediately after parsing, 
  # even if an exception occurs during parsing.
  if File.exist?(csv_path)
    File.delete(csv_path)
    puts "Secure cleanup: CSV file removed successfully."
  end
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

# Ensure directory exists and write encrypted cache
FileUtils.mkdir_p(File.dirname(CACHE_PATH))
File.write(CACHE_PATH, JSON.generate(store_payload))

# CRITICAL: Strict file permission hardening (chmod 600)
File.chmod(0600, CACHE_PATH)

puts "Cache updated and securely encrypted successfully at #{CACHE_PATH} (#{cache_items.size} items processed)."
notify("Cache updated: #{cache_items.size} items", 'Apple Passwords')
