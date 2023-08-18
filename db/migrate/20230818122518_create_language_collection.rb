class CreateLanguageCollection < ActiveRecord::Migration[7.0]
  def change
    create_table :languages, id: false do |t|
      t.string :code, null: false, primary_key: true
      t.string :name, null: false

      t.timestamps
    end
  end
end
