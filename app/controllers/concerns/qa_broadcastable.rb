# frozen_string_literal: true

module QaBroadcastable
  extend ActiveSupport::Concern

  private

    def broadcast_question_added(question)
      ActionCable.server.broadcast(
        "qa_questions_#{question.qa_session.code}",
        {
          type: 'question_added',
          question: {
            id: question.id,
            body: question.body,
            display_name: question.display_name,
            score: 0,
            created_at: question.created_at
          }
        }
      )
    end

    def broadcast_question_deleted(session_code, question_id)
      ActionCable.server.broadcast(
        "qa_questions_#{session_code}",
        { type: 'question_deleted', question_id: question_id }
      )
    end

    def broadcast_score_updated(question)
      score = question.qa_votes.sum(:value)
      ActionCable.server.broadcast(
        "qa_questions_#{question.qa_session.code}",
        { type: 'score_updated', question_id: question.id, score: score }
      )
    end
end
