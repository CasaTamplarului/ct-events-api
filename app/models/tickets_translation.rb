# frozen_string_literal: true

class TicketsTranslation < ApplicationRecord
  has_one :ticket, dependent: :destroy
  has_one :language, dependent: :destroy
end
