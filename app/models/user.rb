# frozen_string_literal: true

class User < ApplicationRecord
  has_secure_password(validations: false, reset_token: false)

  has_many :attendees, dependent: :nullify
  has_many :user_identities, dependent: :destroy
  has_many :passkeys, dependent: :destroy

  ROLES = %w[admin volunteer attendee].freeze

  ROLE_PERMISSIONS = {
    'admin' => { can_check_in_attendees: true, can_scan_food_stamp: true }.freeze,
    'volunteer' => { can_check_in_attendees: true, can_scan_food_stamp: true }.freeze,
    'attendee' => { can_check_in_attendees: false, can_scan_food_stamp: false }.freeze
  }.freeze

  attribute :role, :string, default: 'attendee'

  normalizes :email, with: ->(e) { e&.strip&.downcase }

  scope :active, -> { where(deleted_at: nil) }

  validates :first_name, presence: true
  validates :email, uniqueness: { allow_nil: true },
                    format: { with: URI::MailTo::EMAIL_REGEXP }, allow_nil: true
  validates :password, length: { minimum: 8 }, allow_nil: true
  validates :role, inclusion: { in: ROLES }

  def can?(permission)
    ROLE_PERMISSIONS.dig(role, permission) == true
  end
end
