# encoding: utf-8

# Shared by setup_workflow.rb and main.rb: both must derive the same key to read the cache

require 'openssl'
require 'open3'

PROJECT_NAME = 'alfred-psw-workflow'
CACHE_PATH = File.expand_path("~/.cache/#{PROJECT_NAME}/apw_cache.enc")
CIPHER = 'AES-256-CBC'
CIPHER_SALT = ENV.fetch('cipher_salt', PROJECT_NAME)

SECURITY = '/usr/bin/security'
# Named by its path under HOME, so the tests' fake HOME points it at a throwaway keychain
KEYCHAIN = File.expand_path('~/Library/Keychains/login.keychain-db')
SEED_ITEM = ['-s', PROJECT_NAME, '-a', 'seed']

# The seed stored in the Keychain, or nil when there is none
def read_seed
  out, err, st = Open3.capture3(SECURITY, 'find-generic-password', *SEED_ITEM, '-w', KEYCHAIN)
  return out.strip if st.success?
  return nil if st.exitstatus == 44 # item (or keychain) not found
  raise "cannot read the seed from the Keychain: #{err.strip}"
end

def store_seed(seed)
  raise 'the seed must be hex' unless seed.match?(/\A\h+\z/) # it goes into a security command line
  # security -i reads the command from stdin: the seed never appears in a command line, which other processes can read
  _, err, st = Open3.capture3(SECURITY, '-i', stdin_data: "add-generic-password #{SEED_ITEM.join(' ')} -w #{seed} \"#{KEYCHAIN}\"\n")
  raise "cannot store the seed in the Keychain: #{err.strip}" unless st.success?
end

# Raises if the seed is missing or empty, or if the hardware UUID can't be read
def cache_key
  seed = read_seed or raise 'no seed in the Keychain: run pswsetup'
  raise 'the seed in the Keychain is empty' if seed.empty?

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
