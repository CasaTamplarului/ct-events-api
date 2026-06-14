# frozen_string_literal: true

class AddHeroPortraitToEvents < ActiveRecord::Migration[8.1]
  def change
    add_column :events, :hero_portrait, :uuid
    add_foreign_key :events, :directus_files, column: :hero_portrait,
                                              name: :events_hero_portrait_foreign, on_delete: :nullify
  end
end
