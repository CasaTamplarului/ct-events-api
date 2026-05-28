class AddChurchNameAndCityToAttendees < ActiveRecord::Migration[8.1]
  def change
    add_column :attendees, :church_name, :string
    add_column :attendees, :city, :string
  end
end
