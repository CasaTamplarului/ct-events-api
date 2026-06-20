# frozen_string_literal: true

module Api
  module V1
    class QaQuestionsController < ActionController::API
      include Authenticatable
      include QaIdentifiable
      include QaQuestionRenderable

      before_action :try_authenticate_user
      before_action :load_session

      def create
        return render json: { error: 'Session is closed' }, status: :unprocessable_content if @qa_session.closed?

        identity = current_qa_identity
        if identity[:user_id].nil? && identity[:voter_token].blank?
          return render json: { error: 'X-QA-Token header required' }, status: :unprocessable_content
        end

        question = @qa_session.qa_questions.new(
          body: params[:body],
          display_name: params[:display_name].presence,
          user_id: identity[:user_id],
          submitter_token: identity[:voter_token]
        )

        if question.save
          render json: question_json(question, identity: identity), status: :created
        else
          render json: { error: question.errors.full_messages.first }, status: :unprocessable_content
        end
      end

      def destroy
        identity = current_qa_identity
        question = @qa_session.qa_questions.find_by(id: params[:id])
        return render json: { error: 'Question not found' }, status: :not_found unless question

        return render json: { error: 'Forbidden' }, status: :forbidden unless question.submitted_by?(identity)

        question.destroy!
        head :no_content
      end

      private

        def load_session
          event = Event.find_by(slug: params[:event_slug])
          return render json: { error: 'Not found' }, status: :not_found unless event

          @qa_session = event.qa_sessions.find_by(code: params[:code])
          render json: { error: 'Not found' }, status: :not_found unless @qa_session
        end
    end
  end
end
