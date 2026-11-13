# encoding: utf-8

# Shared by setup_workflow.rb and main.rb: both must derive the same key to read the cache

require 'openssl'

PROJECT_NAME = 'alfred-psw-workflow'
SEED_PATH = File.expand_path("~/.config/#{PROJECT_NAME}/seed")
CACHE_PATH = File.expand_path("~/.cache/#{PROJECT_NAME}/apw_cache.enc")
CIPHER = 'AES-256-CBC'
CIPHER_SALT = ENV.fetch('cipher_salt', PROJECT_NAME)

# Raises if the seed is missing or empty, or if the hardware UUID can't be read
def cache_key
  seed = File.read(SEED_PATH).strip
  raise "seed file #{SEED_PATH} is empty" if seed.empty?

  # Bind the key to this Mac: a copied seed + cache is useless elsewhere
  ioreg = `/usr/sbin/ioreg -rd1 -c IOPlatformExpertDevice`
  hw_uuid = ioreg[/"IOPlatformUUID" = "([^"]+)"/, 1]
  raise 'cannot read hardware UUID' unless hw_uuid

  OpenSSL::PKCS5.pbkdf2_hmac(
    seed,                         # password
    "#{CIPHER_SALT}|#{hw_uuid}",  # salt
    10000,                        # iterations
    32,                           # key size
    OpenSSL::Digest.new('SHA1')   # digest
  )
end
