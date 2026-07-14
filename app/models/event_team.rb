# frozen_string_literal: true

class EventTeam < ApplicationRecord
  belongs_to :event
  has_many :score_entries, class_name: 'EventTeamScoreEntry', dependent: :destroy

  validate :at_least_one_field_present

  private

    def at_least_one_field_present
      return if name.present? || icon.present? || colour.present?

      errors.add(:base, 'At least one of name, icon, or colour must be present')
    end
end
