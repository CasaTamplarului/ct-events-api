# frozen_string_literal: true

class Passkey < ApplicationRecord
  belongs_to :user

  validates :external_id, presence: true, uniqueness: true
  validates :public_key,  presence: true
  validates :nickname, length: { maximum: 100 }, allow_nil: true
end
