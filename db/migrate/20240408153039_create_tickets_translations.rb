class CreateTicketsTranslations < ActiveRecord::Migration[7.1]
  def change
    create_table :tickets_translations do |t|
      t.integer :tickets_id
      t.string :languages_code
      t.string :name, null: false

      t.timestamps
    end

    add_foreign_key :tickets_translations, :languages, column: :languages_code, primary_key: :code, on_delete: :nullify
    add_foreign_key :tickets_translations, :tickets, column: :tickets_id, primary_key: :id, on_delete: :nullify
  end
end
