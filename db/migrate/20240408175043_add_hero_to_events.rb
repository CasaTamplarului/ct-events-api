class AddHeroToEvents < ActiveRecord::Migration[7.1]
  def change
    add_column :events, :hero, :boolean, null: false, default: false
  end
end
