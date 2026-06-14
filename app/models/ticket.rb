# frozen_string_literal: true

class Ticket < ApplicationRecord
  has_many :tickets_translations, foreign_key: 'tickets_id', dependent: :destroy, inverse_of: :ticket
  has_many :ticket_meal_slots, dependent: :destroy
  has_many :ticket_allowed_users, dependent: :destroy
  has_many :allowed_users, through: :ticket_allowed_users, source: :user

  belongs_to :event

  before_validation :fill_valid_date_range
  validate :valid_to_not_before_valid_from

  def translations(language_code)
    tickets_translations.find_by(languages_code: language_code)
  end

  private

    def fill_valid_date_range
      self.valid_to   = valid_from if valid_from && valid_to.nil?
      self.valid_from = valid_to   if valid_to   && valid_from.nil?
    end

    def valid_to_not_before_valid_from
      return unless valid_from && valid_to

      errors.add(:valid_to, 'must be on or after valid_from') if valid_to < valid_from
    end
end
