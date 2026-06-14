# frozen_string_literal: true

class UpdateLanguageCodesToBcp47 < ActiveRecord::Migration[8.1]
  RENAME = { 'ro' => 'ro-RO', 'en' => 'en-US' }.freeze
  TRANSLATION_TABLES = %i[events_translations tickets_translations].freeze

  def up
    # Drop all FKs pointing at languages.code, re-add with ON UPDATE CASCADE
    TRANSLATION_TABLES.each do |table|
      remove_foreign_key table, column: :languages_code
      add_foreign_key table, :languages, column: :languages_code,
                                         primary_key: :code, on_update: :cascade, on_delete: :restrict
    end

    # Now a single UPDATE on languages cascades to all translation tables automatically
    RENAME.each do |old_code, new_code|
      execute "UPDATE languages SET code = '#{new_code}' WHERE code = '#{old_code}';"
    end
  end

  def down
    RENAME.each do |old_code, new_code|
      execute "UPDATE languages SET code = '#{old_code}' WHERE code = '#{new_code}';"
    end

    TRANSLATION_TABLES.each do |table|
      remove_foreign_key table, column: :languages_code
      add_foreign_key table, :languages, column: :languages_code,
                                         primary_key: :code, on_delete: :restrict
    end
  end
end
