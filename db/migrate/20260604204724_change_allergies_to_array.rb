# frozen_string_literal: true

class ChangeAllergiesToArray < ActiveRecord::Migration[8.1]
  CHOICES = [
    { text: 'Gluten',    value: 'gluten' },
    { text: 'Lactose',   value: 'lactose' },
    { text: 'Nuts',      value: 'nuts' },
    { text: 'Eggs',      value: 'eggs' },
    { text: 'Soy',       value: 'soy' },
    { text: 'Fish',      value: 'fish' },
    { text: 'Shellfish', value: 'shellfish' }
  ].freeze

  def up
    remove_column :attendees, :allergies, :integer
    add_column :attendees, :allergies, :jsonb, default: [], null: false

    conn = ActiveRecord::Base.connection
    options = JSON.generate({ choices: CHOICES.map { |c| { 'text' => c[:text], 'value' => c[:value] } } })

    execute("DELETE FROM directus_fields WHERE collection = 'attendees' AND field = 'allergies'")
    execute(<<~SQL)
      INSERT INTO directus_fields (collection, field, interface, hidden, readonly, special, options, width)
      VALUES ('attendees', 'allergies', 'checkboxes', false, false, 'cast-json',
              #{conn.quote(options)}::json, 'full')
    SQL
  end

  def down
    remove_column :attendees, :allergies, :jsonb
    add_column :attendees, :allergies, :integer, default: 0, null: false

    conn = ActiveRecord::Base.connection
    old_options = JSON.generate({
      choices: [
        { 'text' => 'No allergies', 'value' => 0 }, { 'text' => 'Gluten', 'value' => 1 },
        { 'text' => 'Lactose', 'value' => 2 }, { 'text' => 'Nuts', 'value' => 3 },
        { 'text' => 'Eggs', 'value' => 4 }, { 'text' => 'Soy', 'value' => 5 },
        { 'text' => 'Fish', 'value' => 6 }, { 'text' => 'Shellfish', 'value' => 7 }
      ]
    })

    execute("DELETE FROM directus_fields WHERE collection = 'attendees' AND field = 'allergies'")
    execute(<<~SQL)
      INSERT INTO directus_fields (collection, field, interface, hidden, readonly, special, options, width)
      VALUES ('attendees', 'allergies', 'select-radio', false, false, NULL,
              #{conn.quote(old_options)}::json, 'full')
    SQL
  end
end
