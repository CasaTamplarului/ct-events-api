# frozen_string_literal: true

class EventsTranslation < ApplicationRecord
  has_one :event
  has_one :language
end
