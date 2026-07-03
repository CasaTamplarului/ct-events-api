# frozen_string_literal: true

class PushSubscription < ApplicationRecord
  PLATFORMS = %w[web ios android].freeze

  belongs_to :user, optional: true

  validates :token,    presence: true, uniqueness: true
  validates :platform, presence: true, inclusion: { in: PLATFORMS }
end
