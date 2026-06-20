# frozen_string_literal: true

module QaQuestionRenderable
  extend ActiveSupport::Concern

  private

    def question_json(question, identity:, admin: false)
      votes = question.qa_votes.to_a
      score = votes.sum(&:value)
      my_vote = find_my_vote(votes, identity)
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

    def find_my_vote(votes, identity)
      return nil unless identity

      found = votes.find { |v| vote_matches_identity?(v, identity) }
      found&.value
    end

    def vote_matches_identity?(vote, identity)
      (identity[:user_id] && vote.user_id == identity[:user_id]) ||
        (identity[:voter_token].present? && vote.voter_token == identity[:voter_token])
    end
end
