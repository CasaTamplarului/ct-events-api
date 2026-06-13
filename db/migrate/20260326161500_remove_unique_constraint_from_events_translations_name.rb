# frozen_string_literal: true

class RemoveUniqueConstraintFromEventsTranslationsName < ActiveRecord::Migration[8.1]
  def up
    remove_index :events_translations, name: :index_events_translations_on_name, if_exists: true
    execute 'ALTER TABLE events_translations DROP CONSTRAINT IF EXISTS events_translations_name_unique;'
  end

  def down
    add_index :events_translations, :name, unique: true, name: :index_events_translations_on_name
  end
end
