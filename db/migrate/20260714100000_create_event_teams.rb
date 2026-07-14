# frozen_string_literal: true

class CreateEventTeams < ActiveRecord::Migration[7.1]
  def change
    create_table :event_teams do |t|
      t.references :event, null: false, foreign_key: true
      t.string :name
      t.string :icon
      t.string :colour
      t.integer :score, null: false, default: 0
      t.timestamps
    end
  end
end
