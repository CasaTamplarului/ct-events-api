# frozen_string_literal: true

class EventsTranslation < ApplicationRecord
  has_one :event, dependent: :destroy
  has_one :language, dependent: :destroy
end
