class CreateQaVotes < ActiveRecord::Migration[8.1]
  def change
    create_table :qa_votes do |t|
      t.references :qa_question, null: false, foreign_key: { on_delete: :cascade }
      t.integer :value, null: false
      t.bigint :user_id
      t.string :voter_token
      t.timestamps
    end
    add_index :qa_votes, %i[qa_question_id user_id],
              unique: true, where: 'user_id IS NOT NULL', name: 'idx_qa_votes_user_unique'
    add_index :qa_votes, %i[qa_question_id voter_token],
              unique: true, where: 'voter_token IS NOT NULL', name: 'idx_qa_votes_token_unique'
  end
end
