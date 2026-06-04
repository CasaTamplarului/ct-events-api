# frozen_string_literal: true

class HideDirectusBooleanFieldSystemFields < ActiveRecord::Migration[8.1]
  # Hides system-managed fields (id, event_id, created_at, updated_at, FK fields)
  # from the Directus UI so staff only sees the fields they should fill in.

  HIDDEN_FIELDS = [
    # event_boolean_fields — hide everything Directus/Rails manages
    %w[event_boolean_fields id],
    %w[event_boolean_fields event_id],
    %w[event_boolean_fields created_at],
    %w[event_boolean_fields updated_at],
    # event_boolean_field_translations — hide FK + system fields
    %w[event_boolean_field_translations id],
    %w[event_boolean_field_translations event_boolean_field_id],
    %w[event_boolean_field_translations languages_code],
    %w[event_boolean_field_translations created_at],
    %w[event_boolean_field_translations updated_at],
    # attendee_boolean_field_responses — entirely system-managed, hide all
    %w[attendee_boolean_field_responses id],
    %w[attendee_boolean_field_responses attendee_id],
    %w[attendee_boolean_field_responses event_boolean_field_id],
    %w[attendee_boolean_field_responses value],
    %w[attendee_boolean_field_responses created_at],
    %w[attendee_boolean_field_responses updated_at]
  ].freeze

  def up
    conn = ActiveRecord::Base.connection
    HIDDEN_FIELDS.each do |collection, field|
      execute(<<~SQL)
        INSERT INTO directus_fields (collection, field, hidden, width)
        VALUES (#{conn.quote(collection)}, #{conn.quote(field)}, true, 'full')
        ON CONFLICT DO NOTHING
      SQL
      execute(<<~SQL)
        UPDATE directus_fields SET hidden = true
        WHERE collection = #{conn.quote(collection)} AND field = #{conn.quote(field)}
      SQL
    end
  end

  def down
    conn = ActiveRecord::Base.connection
    HIDDEN_FIELDS.each do |collection, field|
      execute("UPDATE directus_fields SET hidden = false WHERE collection = #{conn.quote(collection)} AND field = #{conn.quote(field)}")
    end
  end
end
