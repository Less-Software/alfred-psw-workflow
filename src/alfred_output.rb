# encoding: utf-8

require 'json'

# Prints Alfred Script Filter JSON: https://www.alfredapp.com/help/workflows/inputs/script-filter/json/
module AlfredOutput
  def self.render(items)
    puts JSON.generate({ items: })
  end

  def self.render_error(title, subtitle = nil)
    render([{ title:, subtitle:, valid: false }.compact])
  end
end
