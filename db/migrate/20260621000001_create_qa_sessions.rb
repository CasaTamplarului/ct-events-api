class CreateQaSessions < ActiveRecord::Migration[8.1]
  def change
    create_table :qa_sessions do |t|
      t.references :event, null: false, foreign_key: { on_delete: :cascade }
      t.string :code, limit: 8, null: false
      t.integer :status, null: false, default: 0
      t.boolean :voting_enabled, null: false, default: true
      t.boolean :questions_public, null: false, default: true
      t.bigint :created_by_user_id, null: false
      t.timestamps
    end
    add_index :qa_sessions, :code, unique: true
    add_foreign_key :qa_sessions, :users, column: :created_by_user_id
  end
end
