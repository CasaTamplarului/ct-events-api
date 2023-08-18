class InsertDirectusCollectionRecords < ActiveRecord::Migration[7.0]
  def up
    execute <<-SQL
      DELETE FROM directus_collections;
    SQL

    execute <<-SQL
      INSERT INTO "public"."directus_collections" ("collection", "icon", "note", "display_template", "hidden", "singleton", "translations", "archive_field", "archive_app_filter", "archive_value", "unarchive_value", "sort_field", "accountability", "color", "item_duplication_fields", "sort", "group", "collapse", "preview_url")
      VALUES ('attendees', 'person_add', NULL, NULL, 'f', 'f', NULL, NULL, 't', NULL, NULL, NULL, 'all', NULL, NULL, NULL, NULL, 'open', NULL),
              ('events', 'event', NULL, NULL, 'f', 'f', NULL, NULL, 't', NULL, NULL, NULL, 'all', NULL, NULL, NULL, NULL, 'open', NULL),
              ('languages', 'translate', NULL, NULL, 'f', 'f', NULL, NULL, 't', NULL, NULL, NULL, 'all', NULL, NULL, NULL, NULL, 'open', NULL);
    SQL
  end

  def down
    execute <<-SQL
      DELETE FROM "public"."directus_collections";
    SQL
  end
end