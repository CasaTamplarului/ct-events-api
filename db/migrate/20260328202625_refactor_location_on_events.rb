# frozen_string_literal: true

class RefactorLocationOnEvents < ActiveRecord::Migration[8.1]
  def change
    remove_column :events, :latitude, :decimal
    remove_column :events, :longitude, :decimal
    rename_column :events, :google_place_id, :embed_url
  end
end
