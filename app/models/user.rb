# frozen_string_literal: true

class User < ApplicationRecord
  has_secure_password(validations: false, reset_token: false)

  has_many :attendees, dependent: :nullify
  has_many :user_identities, dependent: :destroy

  normalizes :email, with: ->(e) { e.strip.downcase }

  validates :first_name, presence: true
  validates :email, uniqueness: { allow_nil: true },
                    format: { with: URI::MailTo::EMAIL_REGEXP }, allow_nil: true
  validates :password, length: { minimum: 8 }, allow_nil: true
end
