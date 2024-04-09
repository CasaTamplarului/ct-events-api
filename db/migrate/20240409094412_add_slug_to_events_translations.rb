class AddSlugToEventsTranslations < ActiveRecord::Migration[7.1]
  def change
    add_column :events_translations, :slug, :string
    add_index :events_translations, :slug, unique: true

    EventsTranslation.where(slug: nil).find_each do |events_translation|
      events_translation.update(slug: events_translation.name.parameterize)
    end
  end
end
