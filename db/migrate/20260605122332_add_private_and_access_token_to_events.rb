# frozen_string_literal: true

class AddPrivateAndAccessTokenToEvents < ActiveRecord::Migration[8.1]
  def up
    add_column :events, :is_private, :boolean, default: false, null: false
    # gen_random_uuid() auto-assigns a UUID to every existing and future event row
    add_column :events, :access_token, :uuid, default: -> { 'gen_random_uuid()' }, null: false

    conn = ActiveRecord::Base.connection

    execute("DELETE FROM directus_fields WHERE collection = 'events' AND field IN ('is_private','access_token')")

    execute(<<~SQL)
      INSERT INTO directus_fields (collection, field, interface, hidden, readonly, special, options, width)
      VALUES ('events', 'is_private', 'boolean', false, false, 'cast-boolean',
              '{"label":"Private event"}'::json, 'half')
    SQL

    # access_token shown as readonly so staff can copy it to build the share link
    execute(<<~SQL)
      INSERT INTO directus_fields (collection, field, interface, hidden, readonly, special, options, width)
      VALUES ('events', 'access_token', 'input', false, true, NULL, NULL, 'half')
    SQL
  end

  def down
    remove_column :events, :is_private
    remove_column :events, :access_token
    execute("DELETE FROM directus_fields WHERE collection = 'events' AND field IN ('is_private','access_token')")
  end
end
