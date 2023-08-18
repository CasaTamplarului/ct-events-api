class InsertDirectusRecordsEventsTranslations < ActiveRecord::Migration[7.0]
  def up
    execute <<-SQL
      INSERT INTO "public"."directus_fields" ("collection", "field", "special", "interface", "options", "display", "display_options", "readonly", "hidden", "sort", "width", "translations", "note", "conditions", "required", "group", "validation", "validation_message")
      VALUES ('events_translations', 'id', NULL, NULL, NULL, NULL, NULL, 'f', 't', 1, 'full', NULL, NULL, NULL, 'f', NULL, NULL, NULL),
              ('events_translations', 'events_id', NULL, NULL, NULL, NULL, NULL, 'f', 't', 2, 'full', NULL, NULL, NULL, 'f', NULL, NULL, NULL),
              ('events_translations', 'languages_code', NULL, NULL, NULL, NULL, NULL, 'f', 't', 3, 'full', NULL, NULL, NULL, 'f', NULL, NULL, NULL),
              ('events_translations', 'name', NULL, 'input', '{"placeholder":"Tabara Impact 2024"}', NULL, NULL, 'f', 'f', 4, 'full', NULL, NULL, NULL, 't', NULL, NULL, NULL),
              ('events_translations', 'description', NULL, 'input', NULL, NULL, NULL, 'f', 'f', 5, 'full', NULL, NULL, NULL, 't', NULL, NULL, NULL);
    SQL

    execute <<-SQL
    INSERT INTO "public"."directus_fields" ("collection", "field", "special", "interface", "options", "display", "display_options", "readonly", "hidden", "sort", "width", "translations", "note", "conditions", "required", "group", "validation", "validation_message")
    VALUES ('events_translations', 'created_at', 'date-created', NULL, NULL, NULL, NULL, 'f', 't', NULL, 'full', NULL, NULL, NULL, 'f', NULL, NULL, NULL),
            ('events_translations', 'updated_at', 'date-created,date-updated', NULL, NULL, NULL, NULL, 'f', 't', NULL, 'full', NULL, NULL, NULL, 'f', NULL, NULL, NULL);
    SQL
  end

  def down
    execute <<-SQL
      DELETE FROM "public"."directus_fields" WHERE "collection" = 'events_translations' AND "field" IN ('id', 'events_id', 'languages_code', 'name', 'description', 'created_at', 'updated_at');
    SQL
  end
end


