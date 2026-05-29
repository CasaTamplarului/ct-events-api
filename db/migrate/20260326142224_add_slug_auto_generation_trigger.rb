# frozen_string_literal: true

class AddSlugAutoGenerationTrigger < ActiveRecord::Migration[8.1]
  def up
    # unaccent strips diacritics: ă→a, î→i, â→a, ș→s, ț→t etc.
    execute <<~SQL
      CREATE EXTENSION IF NOT EXISTS unaccent;
    SQL

    execute <<~SQL
      CREATE OR REPLACE FUNCTION slugify(text) RETURNS text AS $$
        SELECT regexp_replace(
          regexp_replace(
            trim(
              regexp_replace(
                lower(unaccent($1)),
                '[^a-z0-9\\s-]', '', 'g'
              )
            ),
            '\\s+', '-', 'g'
          ),
          '-+', '-', 'g'
        );
      $$ LANGUAGE sql IMMUTABLE STRICT;
    SQL

    execute <<~SQL
      CREATE OR REPLACE FUNCTION unique_slug_for_event_translation(
        base_name text,
        exclude_id bigint DEFAULT NULL
      ) RETURNS text AS $$
      DECLARE
        base_slug text;
        candidate  text;
        counter    int := 1;
      BEGIN
        base_slug := slugify(base_name);
        candidate := base_slug;

        WHILE EXISTS (
          SELECT 1 FROM events_translations
          WHERE slug = candidate
            AND (exclude_id IS NULL OR id <> exclude_id)
        ) LOOP
          candidate := base_slug || '-' || counter;
          counter   := counter + 1;
        END LOOP;

        RETURN candidate;
      END;
      $$ LANGUAGE plpgsql;
    SQL

    execute <<~SQL
      CREATE OR REPLACE FUNCTION trg_events_translations_slug()
      RETURNS trigger AS $$
      BEGIN
        -- Only generate when slug is absent or explicitly cleared
        IF NEW.slug IS NULL OR trim(NEW.slug) = '' THEN
          NEW.slug := unique_slug_for_event_translation(NEW.name, NEW.id);
        END IF;
        RETURN NEW;
      END;
      $$ LANGUAGE plpgsql;
    SQL

    execute <<~SQL
      CREATE OR REPLACE TRIGGER set_events_translations_slug
        BEFORE INSERT OR UPDATE ON events_translations
        FOR EACH ROW EXECUTE FUNCTION trg_events_translations_slug();
    SQL
  end

  def down
    execute "DROP TRIGGER IF EXISTS set_events_translations_slug ON events_translations;"
    execute "DROP FUNCTION IF EXISTS trg_events_translations_slug();"
    execute "DROP FUNCTION IF EXISTS unique_slug_for_event_translation(text, bigint);"
    execute "DROP FUNCTION IF EXISTS slugify(text);"
  end
end
