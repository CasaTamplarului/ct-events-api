class CreateQaQuestions < ActiveRecord::Migration[8.1]
  def change
    create_table :qa_questions do |t|
      t.references :qa_session, null: false, foreign_key: { on_delete: :cascade }
      t.text :body, null: false
      t.string :display_name
      t.bigint :user_id
      t.string :submitter_token
      t.timestamps
    end
    add_foreign_key :qa_questions, :users, column: :user_id, on_delete: :nullify
  end
end
