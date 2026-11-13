require 'minitest/autorun'
require 'json'
require_relative '../src/alfred_output'

class AlfredOutputTest < Minitest::Test
  def rendered_items
    out, = capture_io { yield }
    JSON.parse(out)['items']
  end

  def test_render_prints_items_as_alfred_json
    items = rendered_items { AlfredOutput.render([{ title: 'GitHub', arg: 'octo|github.com' }]) }
    assert_equal [{ 'title' => 'GitHub', 'arg' => 'octo|github.com' }], items
  end

  def test_render_error_prints_a_single_invalid_item
    items = rendered_items { AlfredOutput.render_error('Oops', 'details') }
    assert_equal [{ 'title' => 'Oops', 'subtitle' => 'details', 'valid' => false }], items
  end

  def test_render_error_without_subtitle
    items = rendered_items { AlfredOutput.render_error('Oops') }
    assert_equal [{ 'title' => 'Oops', 'valid' => false }], items
  end
end
