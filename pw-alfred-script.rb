#!/bin/sh
# A shebang can't call brew: re-run with Homebrew's ruby; -x makes ruby skip to the #!ruby line
exec "$(brew --prefix ruby)/bin/ruby" -x "$0" "$@"
#!ruby
# encoding: utf-8

require 'json'
require 'openssl'
require 'base64'

SEED_PATH = File.expand_path('~/.config/pw-alfred-workflow/seed')
CACHE_PATH = File.expand_path('~/.cache/pw-alfred-workflow/apw_cache.enc')
SALT = 'pw-alfred-workflow'

query = ARGV[0].to_s.strip

# Rule: Wait for at least 4 characters before searching
if query.length < 4
  response = {
    items: [
      {
        title: "Please type at least 4 characters...",
        subtitle: "Current search: '#{query}' (#{4 - query.length} characters remaining)",
        valid: false
      }
    ]
  }
  puts JSON.generate(response)
  exit 0
end

unless File.exist?(SEED_PATH) && File.exist?(CACHE_PATH)
  response = {
    items: [{ title: "Seed or Cache missing. Please run sync.", valid: false }]
  }
  puts JSON.generate(response)
  exit 0
end

begin
  # Derive decryption key
  seed = File.read(SEED_PATH).strip
  raise "seed file #{SEED_PATH} is empty" if seed.empty?
  # Bind the key to this Mac: a copied seed + cache is useless elsewhere
  hw_uuid = `/usr/sbin/ioreg -rd1 -c IOPlatformExpertDevice`[/"IOPlatformUUID" = "([^"]+)"/, 1]
  raise 'cannot read hardware UUID' unless hw_uuid
  key = OpenSSL::PKCS5.pbkdf2_hmac(seed, "#{SALT}|#{hw_uuid}", 10000, 32, OpenSSL::Digest.new('SHA1'))

  # Read and decrypt cache
  encrypted_store = JSON.parse(File.read(CACHE_PATH))
  iv = Base64.strict_decode64(encrypted_store['iv'])
  encrypted_data = Base64.strict_decode64(encrypted_store['data'])

  cipher = OpenSSL::Cipher.new('AES-256-CBC')
  cipher.decrypt
  cipher.key = key
  cipher.iv = iv

  decrypted_json = cipher.update(encrypted_data) + cipher.final
  items_data = JSON.parse(decrypted_json)
rescue => e
  response = {
    items: [{ title: "Decryption or Parsing Error", subtitle: e.message, valid: false }]
  }
  puts JSON.generate(response)
  exit 0
end

# Filter and sort locally
q = query.downcase
filtered_items = items_data.select do |item|
  domain = item['domain'].to_s.downcase
  username = item['username'].to_s.downcase
  title = item['title'].to_s.downcase.strip
  domain.include?(q) || username.include?(q) || title.include?(q)
end

sorted_items = filtered_items.sort_by do |item|
  domain = item['domain'].to_s.downcase
  username = item['username'].to_s.downcase
  title = item['title'].to_s.downcase.strip

  match_title = title.include?(q) ? 0 : 1
  match_domain = domain.include?(q) ? 0 : 1
  match_username = username.include?(q) ? 0 : 1

  [match_title, match_domain, match_username, domain, username]
end

alfred_items = sorted_items.map do |item|
  username = item['username']
  domain = item['domain']
  title = item['title']

  # Cleanup here
  display_title = "#{title}: #{username}@#{domain}"
  subtitle = "Title: #{title} | User: #{username} | Domain: #{domain}"

  # Pass 'username::domain' directly into arg so we don't need to parse the cache again
  pass_arg = "#{username}|#{domain}"

  {
    title: display_title,
    subtitle: subtitle,
    arg: pass_arg,
    text: {
      copy: display_title,
      largeType: display_title
    }
  }
end

if alfred_items.empty?
  alfred_items = [{
    title: "No credentials found for '#{query}'",
    valid: false
  }]
end

response = { items: alfred_items }
puts JSON.generate(response)