# encoding: utf-8

# Matches cache entries ({'title', 'domain', 'username'} hashes) against a query, as Alfred items
class AlfredQuery
  def initialize(query)
    @words = query.downcase.split
  end

  def match(items)
    filtered_items = filter_items(items)
    sorted_items = sort_items(filtered_items)
    formatted_items = format_items(sorted_items)
    formatted_items
  end

  private

  def filter_items(items)
    items.select do |item|
      fields = item.values_at('title', 'domain', 'username')
      @words.all? { |word| fields.any? { _1.downcase.include?(word) } }
    end
  end

  def sort_items(items)
    items.sort_by do |item|
      title, domain, username = item.values_at('title', 'domain', 'username').map(&:downcase)
      [title, domain, username].map { matches?(_1) ? 0 : 1 } + [domain, username]
    end
  end

  def format_items(items) = items.map { format_item(_1) }

  def format_item(item)
    title, domain, username = item.values_at('title', 'domain', 'username')

    # setup_workflow.rb stores stripped strings, so empty? is enough
    display_title = [title, domain, username].find { !_1.empty? }

    subtitle = [
      ("user: #{username}" unless username.empty?),
      ("domain: #{domain}" unless domain.empty?)
    ].compact.join(' | ')

    {
      title: display_title,
      # apw looks entries up by website: for one without, the actions open Passwords.app instead
      subtitle: domain.empty? ? "#{subtitle} (can't copy without website, ↩ open Passwords app)" : subtitle,
      # Pass 'username|domain' directly into arg so we don't need to parse the cache again
      arg: "#{username}|#{domain}",
      text: {
        copy: display_title,
        largeType: display_title
      }
    }
  end

  def matches?(field) = @words.any? { field.include?(_1) }
end
