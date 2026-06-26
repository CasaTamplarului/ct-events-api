# frozen_string_literal: true

module Api
  module V1
    module Admin
      class QaQuestionsController < ActionController::API
        include Authenticatable
        include QaQuestionRenderable
        include QaBroadcastable

        before_action :authenticate_user!
        before_action :require_admin!
        before_action :load_session

        def index
          questions = @qa_session.qa_questions.includes(:qa_votes).to_a
          sorted = questions.sort_by { |q| [-q.qa_votes.sum(&:value), -q.created_at.to_i] }
          render json: sorted.map { |q| question_json(q, identity: nil, admin: true) }
        end

        def destroy
          question = @qa_session.qa_questions.find_by(id: params[:id])
          return render json: { error: 'Question not found' }, status: :not_found unless question

          question.destroy!
          broadcast_question_deleted(@qa_session.code, question.id)
          head :no_content
        end

        private

          def load_session
            @qa_session = QaSession.find_by(code: params[:code])
            render json: { error: 'Session not found' }, status: :not_found unless @qa_session
          end
      end
    end
  end
end
