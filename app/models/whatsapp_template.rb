# frozen_string_literal: true

class WhatsappTemplate < ApplicationRecord
  before_validation { self.variables = [] if variables.nil? }

  validates :name,        presence: true
  validates :content_sid, presence: true
end
