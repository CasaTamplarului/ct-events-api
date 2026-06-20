# frozen_string_literal: true

module QaQuestionRenderable
  extend ActiveSupport::Concern

  private

    def question_json(question, identity:, admin: false)
      votes = question.qa_votes.to_a
      my_vote = nil

      if identity
        found = votes.find do |v|
          (identity[:user_id] && v.user_id == identity[:user_id]) ||
            (identity[:voter_token].present? && v.voter_token == identity[:voter_token])
        end
        my_vote = found&.value
      end

      score = votes.sum(&:value)
      can_delete = admin || question.submitted_by?(identity)

      {
        id: question.id,
        body: question.body,
        display_name: question.display_name,
        score: score,
        my_vote: my_vote,
        can_delete: can_delete,
        created_at: question.created_at
      }
    end
end
