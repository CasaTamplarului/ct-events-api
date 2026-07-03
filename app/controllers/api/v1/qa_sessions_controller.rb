# frozen_string_literal: true

module Api
  module V1
    class QaSessionsController < ActionController::API
      include Authenticatable
      include QaIdentifiable
      include QaQuestionRenderable

      # Codes are globally unique — lets clients join by code alone.
      def resolve
        qa_session = QaSession.includes(:event).find_by(code: params[:code].to_s.strip)
        return render json: { error: 'Not found' }, status: :not_found unless qa_session

        render json: { event_slug: qa_session.event.slug, code: qa_session.code }
      end

      def show
        try_authenticate_user

        event = Event.find_by(slug: params[:event_slug])
        return render json: { error: 'Not found' }, status: :not_found unless event

        qa_session = event.qa_sessions
                          .includes(:qa_session_translations, qa_questions: :qa_votes)
                          .find_by(code: params[:code])
        return render json: { error: 'Not found' }, status: :not_found unless qa_session

        identity = current_qa_identity
        lang = params[:lang].presence || 'ro-RO'
        questions = visible_questions(qa_session, identity)
        sorted = questions.sort_by { |q| [-q.qa_votes.sum(&:value), -q.created_at.to_i] }

        render json: {
          code: qa_session.code,
          name: qa_session.name_for(lang),
          status: qa_session.status,
          voting_enabled: qa_session.voting_enabled,
          questions_public: qa_session.questions_public,
          questions: sorted.map { |q| question_json(q, identity: identity) }
        }
      end

      private

        def visible_questions(qa_session, identity)
          all = qa_session.qa_questions.to_a
          return all if qa_session.questions_public

          all.select { |q| q.submitted_by?(identity) }
        end
    end
  end
end
