# frozen_string_literal: true

module Api
  module V1
    class QaVotesController < ActionController::API
      include Authenticatable
      include QaIdentifiable
      include QaBroadcastable

      before_action :try_authenticate_user
      before_action :load_session_and_question

      def create
        return render json: { error: 'Session is closed' }, status: :unprocessable_content if @qa_session.closed?

        unless @qa_session.voting_enabled
          return render json: { error: 'Voting is disabled' }, status: :unprocessable_content
        end

        identity = current_qa_identity
        return render_auth_required unless identity_present?(identity)

        value = params[:value].to_i
        unless [1, -1].include?(value)
          return render json: { error: 'value must be 1 or -1' }, status: :unprocessable_content
        end

        cast_vote(identity, value)
      end

      private

        def identity_present?(identity)
          identity[:user_id].present? || identity[:voter_token].present?
        end

        def render_auth_required
          render json: { error: 'Authentication required: provide a JWT or X-QA-Token header' },
                 status: :unprocessable_content
        end

        def cast_vote(identity, value)
          existing = QaVote.find_for(question: @question, identity: identity)
          if existing
            handle_existing_vote(existing, value)
          else
            vote = @question.qa_votes.create!(value: value, user_id: identity[:user_id],
                                              voter_token: identity[:voter_token])
            broadcast_score_updated(@question.reload)
            render json: { my_vote: vote.value }, status: :created
          end
        end

        def handle_existing_vote(existing, value)
          if existing.value == value
            existing.destroy!
            broadcast_score_updated(@question.reload)
            render json: { my_vote: nil }, status: :ok
          else
            existing.update!(value: value)
            broadcast_score_updated(@question.reload)
            render json: { my_vote: value }, status: :ok
          end
        end

        def load_session_and_question
          event = Event.find_by(slug: params[:event_slug])
          return render json: { error: 'Not found' }, status: :not_found unless event

          @qa_session = event.qa_sessions.find_by(code: params[:code])
          return render json: { error: 'Not found' }, status: :not_found unless @qa_session

          @question = @qa_session.qa_questions.find_by(id: params[:question_id])
          render json: { error: 'Not found' }, status: :not_found unless @question
        end
    end
  end
end
