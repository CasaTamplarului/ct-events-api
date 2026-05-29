# frozen_string_literal: true

class EventGallery < ApplicationRecord
  self.table_name = "event_gallery"

  belongs_to :event
end
