class AddDescriptionToEventsTranslations < ActiveRecord::Migration[8.1]
  def change
    add_column :events_translations, :description, :text
  end
end
