# frozen_string_literal: true

class AddStaffRole < ActiveRecord::Migration[8.1]
  def up
    execute(<<~SQL)
      UPDATE directus_fields
      SET options = '{"choices":[{"text":"Admin","value":"admin"},{"text":"Volunteer","value":"volunteer"},{"text":"Attendee","value":"attendee"},{"text":"Leader","value":"leader"},{"text":"Staff","value":"staff"}]}'::json
      WHERE collection = 'users' AND field = 'role'
    SQL
  end

  def down
    execute(<<~SQL)
      UPDATE directus_fields
      SET options = '{"choices":[{"text":"Admin","value":"admin"},{"text":"Volunteer","value":"volunteer"},{"text":"Attendee","value":"attendee"}]}'::json
      WHERE collection = 'users' AND field = 'role'
    SQL
  end
end
