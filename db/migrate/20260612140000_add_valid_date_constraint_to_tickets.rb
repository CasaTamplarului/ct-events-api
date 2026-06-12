# frozen_string_literal: true

class AddValidDateConstraintToTickets < ActiveRecord::Migration[8.1]
  def up
    add_check_constraint :tickets,
                         'valid_from IS NULL OR valid_to IS NULL OR valid_to >= valid_from',
                         name: 'check_tickets_valid_dates_order',
                         validate: false
    validate_check_constraint :tickets, name: 'check_tickets_valid_dates_order'

    execute(<<~SQL)
      UPDATE directus_fields
      SET validation = '{"_or":[{"valid_from":{"_null":true}},{"valid_to":{"_gte":"$FIELD(valid_from)"}}]}'::json,
          validation_message = 'valid_to must be on or after valid_from'
      WHERE collection = 'tickets' AND field = 'valid_to'
    SQL
  end

  def down
    remove_check_constraint :tickets, name: 'check_tickets_valid_dates_order'

    execute(<<~SQL)
      UPDATE directus_fields
      SET validation = NULL, validation_message = NULL
      WHERE collection = 'tickets' AND field = 'valid_to'
    SQL
  end
end
