class InsertDirectusRecords < ActiveRecord::Migration[7.0]
  def up
    execute <<-SQL
      DELETE FROM directus_fields;
    SQL

    execute <<-SQL
      DELETE FROM directus_relations;
    SQL

    execute <<-SQL
      INSERT INTO "public"."directus_fields" ("collection", "field", "special", "interface", "options", "display", "display_options", "readonly", "hidden", "sort", "width", "translations", "note", "conditions", "required", "group", "validation", "validation_message")
      VALUES ('events', 'id', NULL, 'input', NULL, 'raw', NULL, 't', 'f', 1, 'full', NULL, NULL, NULL, 't', NULL, NULL, NULL),
              ('events', 'name', NULL, 'input', '{"placeholder":"Tabara Impact 2024"}', 'raw', NULL, 'f', 'f', 3, 'half', NULL, 'Name of event', NULL, 't', NULL, NULL, NULL),
              ('events', 'description', NULL, 'input', NULL, 'raw', NULL, 'f', 'f', 4, 'full', NULL, NULL, NULL, 'f', NULL, NULL, NULL),
              ('events', 'created_at', 'date-created', 'datetime', NULL, 'datetime', '{"relative":true}', 't', 'f', 11, 'full', NULL, NULL, NULL, 'f', NULL, NULL, NULL),
              ('events', 'updated_at', 'date-updated,date-created', 'datetime', NULL, 'datetime', '{"relative":true}', 't', 'f', 12, 'full', NULL, NULL, NULL, 'f', NULL, NULL, NULL),
              ('events', 'start_date', NULL, 'datetime', NULL, 'datetime', '{}', 'f', 'f', 5, 'half', NULL, NULL, NULL, 't', NULL, NULL, NULL),
              ('events', 'end_date', NULL, 'datetime', NULL, 'datetime', NULL, 'f', 'f', 6, 'half', NULL, NULL, NULL, 't', NULL, NULL, NULL),
              ('events', 'status', NULL, 'select-dropdown', '{"choices":[{"text":"Draft","value":0},{"text":"Live","value":1},{"text":"Cancelled","value":2},{"text":"Deleted","value":3}]}', 'formatted-value', '{"conditionalFormatting":[{"operator":"eq","value":0,"color":"#FFA439","icon":"circle","text":" "},{"operator":"eq","value":1,"color":"#2ECDA7","icon":"circle","text":" "},{"operator":"eq","value":2,"color":"#FFFFFF","icon":"circle","text":" "},{"operator":"eq","value":3,"color":"#E35169","icon":"circle","text":" "}]}', 'f', 'f', 2, 'half', NULL, NULL, NULL, 't', NULL, NULL, NULL),
              ('events', 'max_number_of_people', NULL, 'input', '{"min":0,"iconLeft":"emoji_people"}', 'raw', NULL, 'f', 'f', 7, 'half', NULL, NULL, NULL, 'f', NULL, NULL, NULL),
              ('events', 'min_age', NULL, 'input', '{"min":1,"max":99}', 'raw', NULL, 'f', 'f', 9, 'half', NULL, 'Leave empty if no age limit applies', NULL, 'f', NULL, '{"_and":[{"min_age":{"_gte":"1"}},{"min_age":{"_lte":"99"}}]}', 'Age needs to be between 1 to 99, if no age limit please leave empty'),
              ('events', 'max_age', NULL, 'input', '{"min":1,"max":99}', 'raw', NULL, 'f', 'f', 10, 'half', NULL, NULL, NULL, 'f', NULL, '{"_and":[{"max_age":{"_lte":"99"}},{"max_age":{"_gte":"1"}}]}', 'Age needs to be between 1 to 99, if no age limit please leave empty'),
              ('events', 'override_max_people', 'cast-boolean', 'boolean', NULL, 'boolean', '{"labelOn":"Yes","labelOff":"No"}', 'f', 'f', 8, 'half', NULL, 'Should more bookings be made if it reaches the max amount of people?', '[{"name":"Disable if no max people","rule":{"_and":[{"max_number_of_people":{"_lt":"1"}}]},"readonly":true,"options":{"iconOn":"check_box","iconOff":"check_box_outline_blank","label":"Enabled"}},{"name":"Disable if max people null","rule":{"_and":[{"max_number_of_people":{"_null":true}}]},"readonly":true,"options":{"iconOn":"check_box","iconOff":"check_box_outline_blank","label":"Enabled"}}]', 'f', NULL, NULL, NULL),
              ('events', 'translations', 'translations', 'translations', '{"languageField":"name","defaultLanguage":"ro-RO"}', NULL, NULL, 'f', 'f', 13, 'full', NULL, NULL, NULL, 'f', NULL, NULL, NULL),
              ('attendees', 'id', NULL, 'input', NULL, 'raw', NULL, 't', 'f', 1, 'full', NULL, NULL, NULL, 't', NULL, NULL, NULL),
              ('attendees', 'first_name', NULL, 'input', '{"placeholder":"John"}', 'raw', NULL, 'f', 'f', 3, 'full', NULL, NULL, NULL, 't', NULL, NULL, NULL),
              ('attendees', 'last_name', NULL, 'input', '{"placeholder":"Doe"}', 'raw', NULL, 'f', 'f', 4, 'full', NULL, NULL, NULL, 'f', NULL, NULL, NULL),
              ('attendees', 'email_address', NULL, 'input', '{"iconLeft":"alternate_email","trim":true,"placeholder":"example@email.com"}', 'raw', NULL, 'f', 'f', 5, 'full', NULL, NULL, '[]', 't', NULL, NULL, NULL),
              ('attendees', 'phone_number', NULL, 'input', '{"iconLeft":"phone_enabled"}', 'raw', NULL, 'f', 'f', 6, 'full', NULL, NULL, NULL, 'f', NULL, NULL, NULL),
              ('attendees', 'event_id', NULL, 'select-dropdown-m2o', '{"template":"{{name}}","enableCreate":false}', 'related-values', '{"template":"{{name}}"}', 'f', 'f', 7, 'full', NULL, NULL, NULL, 't', NULL, NULL, NULL),
              ('attendees', 'created_at', 'date-created', 'datetime', NULL, 'datetime', '{"relative":true}', 't', 'f', 9, 'full', NULL, NULL, NULL, 'f', NULL, NULL, NULL),
              ('attendees', 'updated_at', 'date-updated,date-created', 'datetime', NULL, 'datetime', '{"relative":true}', 't', 'f', 10, 'full', NULL, NULL, NULL, 'f', NULL, NULL, NULL),
              ('attendees', 'payment_status', NULL, 'select-dropdown', '{"choices":[{"text":"Payment Pending","value":0},{"text":"Paid","value":1},{"text":"Refunded","value":2}],"icon":"payments"}', 'formatted-value', '{"conditionalFormatting":[{"operator":"eq","value":0,"text":"Payment Pending"},{"operator":"eq","value":1,"text":"Paid"},{"operator":"eq","value":2,"text":"Refunded"}]}', 'f', 'f', 2, 'full', NULL, NULL, '[]', 't', NULL, NULL, NULL),
              ('attendees', 'dietary_preference', NULL, 'select-radio', '{"choices":[{"text":"No preference","value":0},{"text":"Vegetarian","value":1},{"text":"Vegan","value":2}]}', 'formatted-value', '{"conditionalFormatting":[{"operator":"eq","value":0,"text":"No preference"},{"operator":"eq","value":1,"text":"Vegetarian"},{"operator":"eq","value":2,"text":"Vegan"}]}', 'f', 'f', 8, 'full', NULL, NULL, NULL, 't', NULL, NULL, NULL),
              ('languages', 'code', NULL, 'input', NULL, NULL, NULL, 'f', 'f', NULL, 'full', NULL, NULL, NULL, 'f', NULL, NULL, NULL),
              ('languages', 'name', NULL, NULL, NULL, NULL, NULL, 'f', 'f', NULL, 'full', NULL, NULL, NULL, 'f', NULL, NULL, NULL),
              ('languages', 'created_at', 'date-created', 'datetime', '{}', 'datetime', '{"relative":true}', 't', 'f', NULL, 'full', NULL, NULL, NULL, 'f', NULL, NULL, NULL),
              ('languages', 'updated_at', 'date-created,date-updated', 'datetime', '{}', 'datetime', '{"relative":true}', 't', 'f', NULL, 'full', NULL, NULL, NULL, 'f', NULL, NULL, NULL);
    SQL

    execute <<-SQL
      INSERT INTO "public"."directus_relations" ("many_collection", "many_field", "one_collection", "one_field", "one_collection_field", "one_allowed_collections", "junction_field", "sort_field", "one_deselect_action")
      VALUES ('events_translations', 'languages_code', 'languages', NULL, NULL, NULL, 'events_id', NULL, 'nullify'),
              ('events_translations', 'events_id', 'events', 'translations', NULL, NULL, 'languages_code', NULL, 'nullify');
    SQL
  end

  def down
    execute <<-SQL
      DELETE FROM "public"."directus_fields" WHERE "collection" = 'events' AND "field" IN ('id', 'name', 'description', 'created_at', 'updated_at', 'start_date', 'end_date', 'status', 'max_number_of_people', 'min_age', 'max_age', 'override_max_people', 'translations');
      DELETE FROM "public"."directus_fields" WHERE "collection" = 'attendees' AND "field" IN ('id', 'first_name', 'last_name', 'email_address', 'phone_number', 'event_id', 'created_at', 'updated_at', 'dietary_preference', 'payment_status');
      DELETE FROM "public"."directus_fields" WHERE "collection" = 'languages' AND "field" IN ('code', 'name', 'created_at', 'updated_at');
      DELETE FROM "public"."directus_relations" WHERE "many_collection" = 'events_translations' AND "many_field" IN ('languages_code', 'events_id');
    SQL
  end
end
