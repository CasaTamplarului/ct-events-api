# frozen_string_literal: true

class AddDefaultTimestampsToEventGallery < ActiveRecord::Migration[8.1]
  def change
    change_column_default :event_gallery, :created_at, from: nil, to: -> { "CURRENT_TIMESTAMP" }
    change_column_default :event_gallery, :updated_at, from: nil, to: -> { "CURRENT_TIMESTAMP" }
  end
end
