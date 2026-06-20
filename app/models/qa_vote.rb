# frozen_string_literal: true

class QaVote < ApplicationRecord
  belongs_to :qa_question

  validates :value, inclusion: { in: [1, -1] }
  validate :identity_present

  def self.find_for(question:, identity:)
    if identity[:user_id]
      find_by(qa_question: question, user_id: identity[:user_id])
    else
      find_by(qa_question: question, voter_token: identity[:voter_token])
    end
  end

  private

    def identity_present
      errors.add(:base, 'must have user_id or voter_token') if user_id.nil? && voter_token.blank?
    end
end
