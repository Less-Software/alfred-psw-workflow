#!/bin/sh
# A shebang can't call brew: re-run with Homebrew's ruby; -x makes ruby skip to the #!ruby line
exec "$(brew --prefix ruby)/bin/ruby" -x "$0" "$@"
#!ruby
# encoding: utf-8

require 'json'
require 'base64'
require_relative 'cache_key'
require_relative 'alfred_query'
require_relative 'alfred_output'

# Without a locale (LANG unset), ARGV is tagged BINARY and non-ASCII queries fail to compare
query = ARGV[0].to_s.dup.force_encoding(Encoding::UTF_8).strip

# Rule: Wait for at least 4 characters before searching
if query.length < 4
  AlfredOutput.render_error("Please type at least 4 characters...",
    "Current search: '#{query}' (#{4 - query.length} characters remaining)")
  exit 0
end

unless File.exist?(SEED_PATH) && File.exist?(CACHE_PATH)
  AlfredOutput.render_error("Seed or Cache missing. Please run pswsetup.",
    "Type pswsetup in Alfred and select your Passwords CSV export")
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
  AlfredOutput.render_error("Decryption or Parsing Error", e.message)
  exit 0
end

formatted_items = AlfredQuery.new(query).match(items_data)
if formatted_items.any?
  AlfredOutput.render(formatted_items)
else
  AlfredOutput.render_error("No credentials found for '#{query}'")
end
