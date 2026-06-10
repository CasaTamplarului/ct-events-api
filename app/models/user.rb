# frozen_string_literal: true

class User < ApplicationRecord
  has_secure_password(validations: false, reset_token: false)

  has_many :attendees, dependent: :nullify
  has_many :user_identities, dependent: :destroy
  has_many :passkeys, dependent: :destroy
  has_many :push_subscriptions, dependent: :destroy

  ROLES = %w[admin volunteer attendee leader].freeze

  ROLE_PERMISSIONS = {
    'admin'     => { can_check_in_attendees: true,  can_scan_food_stamp: true,  can_send_push_notifications: true,  can_manage_bracelets: true  }.freeze,
    'volunteer' => { can_check_in_attendees: true,  can_scan_food_stamp: true,  can_send_push_notifications: false, can_manage_bracelets: false }.freeze,
    'attendee'  => { can_check_in_attendees: false, can_scan_food_stamp: false, can_send_push_notifications: false, can_manage_bracelets: false }.freeze,
    'leader'    => { can_check_in_attendees: false, can_scan_food_stamp: false, can_send_push_notifications: false, can_manage_bracelets: false }.freeze
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
