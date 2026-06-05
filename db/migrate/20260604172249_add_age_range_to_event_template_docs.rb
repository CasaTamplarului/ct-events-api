# frozen_string_literal: true

class AddAgeRangeToEventTemplateDocs < ActiveRecord::Migration[8.1]
  def change
    add_column :event_template_docs, :age_from, :integer, null: true
    add_column :event_template_docs, :age_to,   :integer, null: true
  end
end
