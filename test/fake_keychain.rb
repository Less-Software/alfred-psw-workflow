require 'fileutils'

# A throwaway login keychain under the fake HOME, where cache_key.rb looks for it: the tests never touch your real one.
# Never delete it during a test: security adds to your default keychain when the keychain it's given doesn't exist.
module FakeKeychain
  SECURITY = '/usr/bin/security'
  SEED_ITEM = ['-s', 'alfred-psw-workflow', '-a', 'seed']
  LOCK = Mutex.new

  # A copy of a keychain named login can't be unlocked, so each test creates its own. create-keychain adds it to your
  # search list: restore the list at once, one test at a time, so that parallel tests don't race on it.
  def create_keychain
    @keychain = File.join(@home, 'Library/Keychains/login.keychain-db')
    FileUtils.mkdir_p(File.dirname(@keychain))
    LOCK.synchronize do
      search_list = IO.popen([SECURITY, 'list-keychains', '-d', 'user'], &:read).scan(/"(.+)"/).flatten
      raise 'cannot read the keychain search list' unless $?.success? # restoring an unread list would empty it
      begin
        system(SECURITY, 'create-keychain', '-p', '', @keychain, exception: true)
      ensure
        system(SECURITY, 'list-keychains', '-d', 'user', '-s', *search_list, exception: true)
      end
    end
  end

  # The seed in the keychain, or nil when there is none
  def seed
    out = IO.popen([SECURITY, 'find-generic-password', *SEED_ITEM, '-w', @keychain], err: File::NULL, &:read)
    out.strip if $?.success?
  end

  def delete_seed
    system(SECURITY, 'delete-generic-password', *SEED_ITEM, @keychain, out: File::NULL, err: File::NULL, exception: true)
  end

  def add_seed(seed) = system(SECURITY, 'add-generic-password', *SEED_ITEM, '-w', seed, @keychain, exception: true)
end
