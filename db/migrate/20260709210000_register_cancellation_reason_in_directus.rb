# frozen_string_literal: true

class RegisterCancellationReasonInDirectus < ActiveRecord::Migration[7.1]
  CHOICES = '[{"text":"Nu pot participa","value":"cant_attend"},{"text":"Motive de sănătate","value":"health"},' \
            '{"text":"Motive financiare","value":"financial"},{"text":"Schimbare de planuri","value":"plans_changed"},' \
            '{"text":"Altele","value":"other"}]'

  def up
    execute(<<~SQL)
      INSERT INTO directus_fields (collection, field, interface, options, hidden, readonly, width)
      VALUES (
        'attendees', 'cancellation_reason', 'select-dropdown',
        '{"choices": #{CHOICES}}',
        false, true, 'half'
      )
      ON CONFLICT DO NOTHING
    SQL

    execute(<<~SQL)
      INSERT INTO directus_fields (collection, field, interface, hidden, readonly, width)
      VALUES ('attendees', 'cancellation_reason_text', 'input', false, true, 'half')
      ON CONFLICT DO NOTHING
    SQL
  end

  def down
    execute(<<~SQL)
      DELETE FROM directus_fields
      WHERE collection = 'attendees'
        AND field IN ('cancellation_reason', 'cancellation_reason_text')
    SQL
  end
end
