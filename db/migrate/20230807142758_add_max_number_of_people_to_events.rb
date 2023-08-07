class AddMaxNumberOfPeopleToEvents < ActiveRecord::Migration[7.0]
  def change
    add_column :events, :max_number_of_people, :integer, null: true
  end
end
