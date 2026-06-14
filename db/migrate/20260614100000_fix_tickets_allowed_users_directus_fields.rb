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
  end

  def down
    execute(<<~SQL)
      UPDATE directus_fields
      SET readonly = true, interface = null
      WHERE collection = 'tickets_allowed_users' AND field IN ('id', 'ticket_id', 'user_id')
    SQL
  end
end
