# frozen_string_literal: true

class AddUploadEnabledToEventTemplateDocs < ActiveRecord::Migration[8.1]
  def up
    add_column :event_template_docs, :upload_enabled, :boolean, default: true, null: false

    ActiveRecord::Base.connection
    execute("DELETE FROM directus_fields WHERE collection = 'event_template_docs' AND field = 'upload_enabled'")
    execute(<<~SQL)
      INSERT INTO directus_fields (collection, field, interface, hidden, readonly, special, options, width)
      VALUES ('event_template_docs', 'upload_enabled', 'boolean', false, false, 'cast-boolean',
              '{"label":"Upload enabled"}'::json, 'half')
    SQL
  end

  def down
    remove_column :event_template_docs, :upload_enabled
    execute("DELETE FROM directus_fields WHERE collection = 'event_template_docs' AND field = 'upload_enabled'")
  end
end
