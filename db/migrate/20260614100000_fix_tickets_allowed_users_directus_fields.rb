# frozen_string_literal: true

class FixTicketsAllowedUsersDirectusFields < ActiveRecord::Migration[8.1]
  def up
    # id: must be readonly: false so Directus resolves junctionPrimaryKeyField correctly
    execute(<<~SQL)
      UPDATE directus_fields
      SET readonly = false, interface = null
      WHERE collection = 'tickets_allowed_users' AND field = 'id'
    SQL

    # FK fields: need select-dropdown-m2o interface so Directus resolves reverseJunctionField
    execute(<<~SQL)
      UPDATE directus_fields
      SET interface = 'select-dropdown-m2o', readonly = false
      WHERE collection = 'tickets_allowed_users' AND field IN ('ticket_id', 'user_id')
    SQL

    # Template must traverse the relation (user_id.field), not query junction table directly
    execute(<<~SQL)
      UPDATE directus_fields
      SET options = '{"template":"{{user_id.first_name}} {{user_id.last_name}} ({{user_id.email}})"}'::json
      WHERE collection = 'tickets' AND field = 'allowed_users'
    SQL
  end

  def down
    execute(<<~SQL)
      UPDATE directus_fields
      SET readonly = true, interface = null
      WHERE collection = 'tickets_allowed_users' AND field IN ('id', 'ticket_id', 'user_id')
    SQL
  end
end
