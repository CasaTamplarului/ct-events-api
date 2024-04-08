class AddUniqueConstraintToEventsTranslationsName < ActiveRecord::Migration[7.1]
  def up
    add_index :events_translations, :name, unique: true
  end

  def down
    remove_index :events_translations, :name
  end
end
