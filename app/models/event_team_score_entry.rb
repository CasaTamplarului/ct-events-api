# frozen_string_literal: true

class EventTeamScoreEntry < ApplicationRecord
  belongs_to :event_team
  belongs_to :added_by_user, class_name: 'User'

  validates :delta, presence: true, numericality: { only_integer: true, other_than: 0 }
end
