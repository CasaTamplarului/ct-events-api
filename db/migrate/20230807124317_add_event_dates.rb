class AddEventDates < ActiveRecord::Migration[7.0]
  def change
    change_table(:events, bulk: true) do |t|
      t.column :start_date, :timestamp, null: false, default: -> { 'CURRENT_TIMESTAMP' }
      t.column :end_date, :timestamp, null: false, default: -> { 'CURRENT_TIMESTAMP' }
    end
  end
end
