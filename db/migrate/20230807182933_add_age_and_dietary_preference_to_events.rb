class AddAgeAndDietaryPreferenceToEvents < ActiveRecord::Migration[7.0]
  def change
    add_column :attendees, :dietary_preference, :integer, null: false, default: 0

    change_table(:events, bulk: true) do |t|
      t.column :min_age, :integer, null: true
      t.column :max_age, :integer, null: true
      t.column :override_max_people, :boolean, null: false, default: false
    end
  end
end
