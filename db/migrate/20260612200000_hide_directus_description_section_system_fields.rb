# frozen_string_literal: true

class HideDirectusDescriptionSectionSystemFields < ActiveRecord::Migration[8.1]
  HIDDEN_FIELDS = [
    %w[event_description_sections id],
    %w[event_description_sections event_id],
    %w[event_description_sections created_at],
    %w[event_description_sections updated_at],
    %w[event_description_section_translations id],
    %w[event_description_section_translations event_description_section_id],
    %w[event_description_section_translations languages_code],
    %w[event_description_section_translations created_at],
    %w[event_description_section_translations updated_at]
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
