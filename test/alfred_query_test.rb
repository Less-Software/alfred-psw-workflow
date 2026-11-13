require 'minitest/autorun'
require_relative '../src/alfred_query'

class AlfredQueryTest < Minitest::Test
  def entry(title: '', domain: '', username: '')
    { 'title' => title, 'domain' => domain, 'username' => username }
  end

  def titles(query, items) = AlfredQuery.new(query).match(items).map { _1[:title] }

  def test_keeps_entries_matching_title_domain_or_username_case_insensitively
    items = [
      entry(title: 'GitHub'),
      entry(domain: 'github.com'),
      entry(username: 'github-bot'),
      entry(title: 'GitLab', domain: 'gitlab.com', username: 'alice')
    ]
    assert_equal ['GitHub', 'github.com', 'github-bot'], titles('GITHUB', items)
  end

  def test_keeps_entries_matching_every_word_of_the_query
    items = [
      entry(title: 'Acme Keystore Passphrase'),
      entry(title: 'Acme Portal'),
      entry(title: 'Passport')
    ]
    assert_equal ['Acme Keystore Passphrase'], titles('acme    pass', items)
  end

  def test_query_words_can_match_different_fields
    items = [entry(title: 'GitHub', username: 'octo'), entry(title: 'GitHub', username: 'bot')]
    assert_equal ['octo|'], AlfredQuery.new('github octo').match(items).map { _1[:arg] }
  end

  def test_sorts_title_matches_then_domain_then_username_matches
    items = [
      entry(title: 'U', username: 'git-u'),
      entry(title: 'D', domain: 'git.d'),
      entry(title: 'Git')
    ]
    assert_equal ['Git', 'D', 'U'], titles('git', items)
  end

  def test_sorts_equal_matches_by_domain_then_username
    items = [
      entry(title: 'Git 3', domain: 'b.com', username: 'a'),
      entry(title: 'Git 2', domain: 'a.com', username: 'b'),
      entry(title: 'Git 1', domain: 'a.com', username: 'a')
    ]
    assert_equal ['Git 1', 'Git 2', 'Git 3'], titles('git', items)
  end

  def test_formats_entry_as_alfred_item
    item = AlfredQuery.new('github').match([entry(title: 'GitHub', domain: 'github.com', username: 'octo')])
    assert_equal [{
      title: 'GitHub',
      subtitle: 'user: octo | domain: github.com',
      arg: 'octo|github.com',
      text: { copy: 'GitHub', largeType: 'GitHub' }
    }], item
  end

  def test_falls_back_to_domain_as_title
    item = AlfredQuery.new('gitlab').match([entry(domain: 'gitlab.com', username: 'alice')]).first
    assert_equal 'gitlab.com', item[:title]
    assert_equal 'user: alice | domain: gitlab.com', item[:subtitle]
    assert_equal 'gitlab.com', item[:text][:copy]
  end

  def test_entry_without_website_stays_selectable_and_says_so
    item = AlfredQuery.new('solo').match([entry(username: 'solo')]).first
    assert_equal 'solo', item[:title]
    assert_equal "user: solo (can't copy without website, ↩ open Passwords app)", item[:subtitle]
    assert_equal 'solo|', item[:arg] # selectable: the actions open Passwords.app for it
  end

  def test_no_match
    assert_empty AlfredQuery.new('nothing-here').match([entry(title: 'GitHub')])
  end
end
