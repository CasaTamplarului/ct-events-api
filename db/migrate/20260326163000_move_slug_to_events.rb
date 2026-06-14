# frozen_string_literal: true

class MoveSlugToEvents < ActiveRecord::Migration[8.1]
  def up
    # 1. Add slug to events table (no unique index yet — add after dedup)
    add_column :events, :slug, :string, limit: 255

    # 2. Migrate existing slugs: prefer Romanian translation, else first available
    execute <<~SQL
      UPDATE events e
      SET slug = (
        SELECT slugify(et.name)
        FROM events_translations et
        WHERE et.event_id = e.id
          AND et.name IS NOT NULL
          AND trim(et.name) <> ''
        ORDER BY (et.languages_code ILIKE 'ro%') DESC, et.id ASC
        LIMIT 1
      )
      WHERE EXISTS (
        SELECT 1 FROM events_translations
        WHERE event_id = e.id AND name IS NOT NULL AND trim(name) <> ''
      );
    SQL

    # 3. Fix any collisions introduced by the bulk migration above
    execute <<~SQL
      WITH dupes AS (
        SELECT id, slug,
               ROW_NUMBER() OVER (PARTITION BY slug ORDER BY id) AS rn
        FROM events
        WHERE slug IS NOT NULL
      )
      UPDATE events e
      SET slug = d.slug || '-' || (d.rn - 1)
      FROM dupes d
      WHERE e.id = d.id AND d.rn > 1;
    SQL

    # 4. Now it's safe to add the unique index
    add_index :events, :slug, unique: true

    # 5. Drop the old per-translation slug trigger and helpers
    execute 'DROP TRIGGER IF EXISTS set_events_translations_slug ON events_translations;'
    execute 'DROP FUNCTION IF EXISTS trg_events_translations_slug();'
    execute 'DROP FUNCTION IF EXISTS unique_slug_for_event_translation(text, bigint);'

    # 6. Drop slug column from events_translations (index is dropped automatically)
    remove_column :events_translations, :slug

    # 7. New helper: unique slug scoped to events table
    execute <<~SQL
      CREATE OR REPLACE FUNCTION unique_slug_for_event(
        base_name     text,
        exclude_id    bigint DEFAULT NULL
      ) RETURNS text AS $$
      DECLARE
        base_slug  text;
        candidate  text;
        counter    int := 1;
      BEGIN
        base_slug := slugify(base_name);
        candidate := base_slug;

        WHILE EXISTS (
          SELECT 1 FROM events
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

    # 8. New trigger: after any change to events_translations, re-derive events.slug
    execute <<~SQL
      CREATE OR REPLACE FUNCTION trg_sync_event_slug()
      RETURNS trigger AS $$
      DECLARE
        target_event_id bigint;
        source_name     text;
      BEGIN
        -- Works for INSERT/UPDATE (use NEW) and DELETE (use OLD)
        target_event_id := COALESCE(NEW.event_id, OLD.event_id);

        -- Prefer Romanian translation; fall back to earliest row
        SELECT name INTO source_name
        FROM events_translations
        WHERE event_id = target_event_id
          AND name IS NOT NULL
          AND trim(name) <> ''
        ORDER BY (languages_code ILIKE 'ro%') DESC, id ASC
        LIMIT 1;

        IF source_name IS NOT NULL THEN
          UPDATE events
          SET slug = unique_slug_for_event(source_name, target_event_id)
          WHERE id = target_event_id;
        END IF;

        RETURN COALESCE(NEW, OLD);
      END;
      $$ LANGUAGE plpgsql;
    SQL

    execute <<~SQL
      CREATE OR REPLACE TRIGGER sync_event_slug
        AFTER INSERT OR UPDATE OR DELETE ON events_translations
        FOR EACH ROW EXECUTE FUNCTION trg_sync_event_slug();
    SQL
  end

  def down
    execute 'DROP TRIGGER IF EXISTS sync_event_slug ON events_translations;'
    execute 'DROP FUNCTION IF EXISTS trg_sync_event_slug();'
    execute 'DROP FUNCTION IF EXISTS unique_slug_for_event(text, bigint);'

    add_column :events_translations, :slug, :string, limit: 255
    add_index :events_translations, :slug, unique: true, name: :index_events_translations_on_slug

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

    remove_index :events, :slug, if_exists: true
    remove_column :events, :slug
  end
end
