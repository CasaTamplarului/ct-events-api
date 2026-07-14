# frozen_string_literal: true

class CreateEventTeamScoreEntries < ActiveRecord::Migration[7.1]
  def change
    create_table :event_team_score_entries do |t|
      t.references :event_team, null: false, foreign_key: true
      t.integer :delta, null: false
      t.references :added_by_user, null: false, foreign_key: { to_table: :users }
      t.datetime :created_at, null: false
    end
  end
end
