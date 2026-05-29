class AddDescriptionToTicketsTranslations < ActiveRecord::Migration[8.1]
  def change
    add_column :tickets_translations, :description, :text
  end
end
