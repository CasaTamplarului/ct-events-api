class CreateAttendees < ActiveRecord::Migration[7.0]
  def change
    create_table :attendees do |t|
      t.string :first_name
      t.string :last_name
      t.string :email_address
      t.string :phone_number
      t.references :event, null: false, foreign_key: true

      t.timestamps
    end
  end
end
