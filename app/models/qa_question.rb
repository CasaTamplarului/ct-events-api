# frozen_string_literal: true

class QaQuestion < ApplicationRecord
  belongs_to :qa_session
  belongs_to :user, optional: true
  has_many :qa_votes, dependent: :destroy

  validates :body, presence: true
  validate :identity_present

  def submitted_by?(identity)
    return false if identity.nil?
    return user_id == identity[:user_id] if identity[:user_id] && user_id
    return submitter_token == identity[:voter_token] if identity[:voter_token].present? && submitter_token.present?

    false
  end

  private

    def identity_present
      errors.add(:base, 'must have user or submitter token') if user_id.nil? && submitter_token.blank?
    end
end
