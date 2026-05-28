class AddLocationToEvents < ActiveRecord::Migration[8.1]
  def change
    add_column :events, :location_name, :string
    add_column :events, :latitude, :decimal
    add_column :events, :longitude, :decimal
    add_column :events, :google_place_id, :string
  end
end
