# frozen_string_literal: true

class RemoveDirectusValidationFromTicketValidTo < ActiveRecord::Migration[8.1]
  def up
    execute(<<~SQL)
      UPDATE directus_fields
      SET validation = NULL, validation_message = NULL
      WHERE collection = 'tickets' AND field = 'valid_to'
    SQL
  end

  def down
    execute(<<~SQL)
      UPDATE directus_fields
      SET validation = '{"_or":[{"valid_from":{"_null":true}},{"valid_to":{"_gte":"$FIELD(valid_from)"}}]}'::json,
          validation_message = 'valid_to must be on or after valid_from'
      WHERE collection = 'tickets' AND field = 'valid_to'
    SQL
  end
end
