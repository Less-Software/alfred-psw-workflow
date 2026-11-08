#!/usr/bin/env ruby
# encoding: utf-8

require 'csv'
require 'json'
require 'openssl'
require 'base64'
require 'fileutils'
require 'securerandom'
require 'uri'

SEED_PATH = File.expand_path('~/.config/pw-alfred-workflow/seed')
CACHE_PATH = File.expand_path('~/.cache/pw-alfred-workflow/apw_cache.enc')
SALT = 'pw-alfred-workflow'

if ARGV[0].to_s.empty?
  STDERR.puts "Usage: #{File.basename($0)} <Passwords.csv>"
  exit 1
end

csv_path = File.expand_path(ARGV[0])

unless File.exist?(csv_path)
  STDERR.puts "Error: Passwords CSV file not found at #{csv_path}"
  exit 1
end

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
  key = OpenSSL::PKCS5.pbkdf2_hmac(seed, "#{SALT}|#{hw_uuid}", 10000, 32, OpenSSL::Digest.new('SHA1'))
rescue => e
  STDERR.puts "Error reading seed: #{e.message}"
  exit 1
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
    item_id = Digest::SHA256.hexdigest(id_string)[0..12]

    cache_items << {
      'id' => item_id,
      'title' => title.to_s.strip,
      'domain' => domain.to_s.strip,
      'username' => username.to_s.strip
    }
  end
ensure
  # CRITICAL SECURITY STEP: Remove the CSV file immediately after parsing, 
  # even if an exception occurs during parsing.
  if File.exist?(csv_path)
    File.delete(csv_path)
    puts "Secure cleanup: CSV file removed successfully."
  end
end

# 3. Encrypt the parsed metadata payload (No passwords are ever stored in cache)
cipher = OpenSSL::Cipher.new('AES-256-CBC')
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