class RenameDescriptionToTagLineOnEventsTranslations < ActiveRecord::Migration[7.0]
  def change
    rename_column :events_translations, :description, :tag_line

    execute <<-SQL
      UPDATE "public"."directus_fields" SET "field" = 'tag_line' WHERE "collection" = 'events_translations' AND "field" = 'description';
    SQL
  end
end
