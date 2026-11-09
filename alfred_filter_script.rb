#!/bin/sh
# A shebang can't call brew: re-run with Homebrew's ruby; -x makes ruby skip to the #!ruby line
exec "$(brew --prefix ruby)/bin/ruby" -x "$0" "$@"
#!ruby
# encoding: utf-8

require 'json'
require 'base64'
require_relative 'cache_key'

# Without a locale (LANG unset), ARGV is tagged BINARY and non-ASCII queries fail to compare
query = ARGV[0].to_s.dup.force_encoding(Encoding::UTF_8).strip

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
    items: [{ title: "Seed or Cache missing. Please run sync.",
              subtitle: "Type pswsync in Alfred and select your Passwords CSV export", valid: false }]
  }
  puts JSON.generate(response)
  exit 0
end

begin
  # Read and decrypt cache
  encrypted_store = JSON.parse(File.read(CACHE_PATH))
  iv = Base64.strict_decode64(encrypted_store['iv'])
  encrypted_data = Base64.strict_decode64(encrypted_store['data'])

  cipher = OpenSSL::Cipher.new(CIPHER)
  cipher.decrypt
  cipher.key = cache_key
  cipher.iv = iv

  decrypted_json = cipher.update(encrypted_data) + cipher.final
  
  # Parse items from cache
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
  title = item['title'].to_s.downcase
  domain = item['domain'].to_s.downcase
  username = item['username'].to_s.downcase
 
  match_title = title.include?(q) ? 0 : 1
  match_domain = domain.include?(q) ? 0 : 1
  match_username = username.include?(q) ? 0 : 1

  [match_title, match_domain, match_username, domain, username]
end

displayed_items = sorted_items.map do |item|
  title = item['title']
  domain = item['domain']
  username = item['username']
 
  # setup_cache.rb stores stripped strings, so empty? is enough
  display_title = [title, domain, username].find { !_1.empty? }

  subtitle = [
    ("user: #{username}" unless username.empty?),
    ("domain: #{domain}" unless domain.empty?)
  ].compact.join(' | ')

  # Pass 'username|domain' directly into arg so we don't need to parse the cache again
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

if displayed_items.empty?
  displayed_items = [{
    title: "No credentials found for '#{query}'",
    valid: false
  }]
end

response = { items: displayed_items }
puts JSON.generate(response)
