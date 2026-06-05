# frozen_string_literal: true

class AddAllergiesToDirectusAttendees < ActiveRecord::Migration[8.1]
  CHOICES = [
    { text: 'No allergies',  value: 0 },
    { text: 'Gluten',        value: 1 },
    { text: 'Lactose',       value: 2 },
    { text: 'Nuts',          value: 3 },
    { text: 'Eggs',          value: 4 },
    { text: 'Soy',           value: 5 },
    { text: 'Fish',          value: 6 },
    { text: 'Shellfish',     value: 7 }
  ].freeze

  def up
    conn = ActiveRecord::Base.connection
    options = JSON.generate({ choices: CHOICES.map { |c| { 'text' => c[:text], 'value' => c[:value] } } })

    execute("DELETE FROM directus_fields WHERE collection = 'attendees' AND field = 'allergies'")
    execute(<<~SQL)
      INSERT INTO directus_fields (collection, field, interface, hidden, readonly, special, options, width)
      VALUES ('attendees', 'allergies', 'select-radio', false, false, NULL,
              #{conn.quote(options)}::json, 'full')
    SQL
  end

  def down
    execute("DELETE FROM directus_fields WHERE collection = 'attendees' AND field = 'allergies'")
  end
end
