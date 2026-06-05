# frozen_string_literal: true

class AddRequiredToEventTemplateDocs < ActiveRecord::Migration[8.1]
  def change
    add_column :event_template_docs, :required, :boolean, null: false, default: false
  end
end
