# frozen_string_literal: true

class User < ApplicationRecord
  has_secure_password(validations: false)

  has_many :attendees, dependent: :nullify
  has_many :user_identities, dependent: :destroy

  normalizes :email, with: ->(e) { e.strip.downcase }

  validates :first_name, presence: true
  validates :last_name, presence: true
  validates :email, presence: true, uniqueness: true,
                    format: { with: URI::MailTo::EMAIL_REGEXP }
  validates :password, length: { minimum: 8 }, allow_nil: true
end
