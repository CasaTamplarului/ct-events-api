# frozen_string_literal: true

module Api
  module V1
    class QaVotesController < ActionController::API
      include Authenticatable
      include QaIdentifiable

      before_action :try_authenticate_user
      before_action :load_session_and_question

      def create
        if @qa_session.closed?
          return render json: { error: 'Session is closed' }, status: :unprocessable_content
        end

        unless @qa_session.voting_enabled
          return render json: { error: 'Voting is disabled' }, status: :unprocessable_content
        end

        identity = current_qa_identity
        if identity[:user_id].nil? && identity[:voter_token].blank?
          return render json: { error: 'X-QA-Token header required' }, status: :unprocessable_content
        end

        value = params[:value].to_i
        unless [1, -1].include?(value)
          return render json: { error: 'value must be 1 or -1' }, status: :unprocessable_content
        end

        existing = QaVote.find_for(question: @question, identity: identity)

        if existing
          if existing.value == value
            existing.destroy!
            render json: { my_vote: nil }, status: :ok
          else
            existing.update!(value: value)
            render json: { my_vote: value }, status: :ok
          end
        else
          vote = @question.qa_votes.create!(
            value: value,
            user_id: identity[:user_id],
            voter_token: identity[:voter_token]
          )
          render json: { my_vote: vote.value }, status: :created
        end
      end

      private

        def load_session_and_question
          event = Event.find_by(slug: params[:event_slug])
          return render json: { error: 'Not found' }, status: :not_found unless event

          @qa_session = event.qa_sessions.find_by(code: params[:code])
          return render json: { error: 'Not found' }, status: :not_found unless @qa_session

          @question = @qa_session.qa_questions.find_by(id: params[:question_id])
          return render json: { error: 'Not found' }, status: :not_found unless @question
        end
    end
  end
end
