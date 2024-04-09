# frozen_string_literal: true

class EventsTranslation < ApplicationRecord
  belongs_to :event
  has_one :language, dependent: :destroy
end
