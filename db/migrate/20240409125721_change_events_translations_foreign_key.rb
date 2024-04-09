class ChangeEventsTranslationsForeignKey < ActiveRecord::Migration[7.1]
  def up
    rename_column :events_translations, :events_id, :event_id

    remove_foreign_key :events_translations, column: :event_id
  end

  def down
    add_foreign_key :events_translations, :events, column: :events_id, primary_key: :id, on_delete: :nullify

    rename_column :events_translations, :event_id, :events_id
  end
end
