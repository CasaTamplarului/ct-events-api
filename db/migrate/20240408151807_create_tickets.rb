class CreateTickets < ActiveRecord::Migration[7.1]
  def change
    create_table :tickets do |t|
      t.string :name
      t.decimal :price
      t.references :event, null: false, foreign_key: true

      t.timestamps
    end
  end
end
