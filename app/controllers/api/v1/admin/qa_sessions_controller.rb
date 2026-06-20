# frozen_string_literal: true

module Api
  module V1
    module Admin
      class QaSessionsController < ActionController::API
        include Authenticatable

        before_action :authenticate_user!
        before_action :require_admin!
        before_action :load_event, only: %i[index create]

        def index
          sessions = @event.qa_sessions
                           .includes(:qa_session_translations, :qa_questions)
                           .order(created_at: :desc)
          render json: sessions.map { |s| session_json(s) }
        end

        def create
          session = @event.qa_sessions.new(
            created_by_user: current_user,
            voting_enabled: params.fetch(:voting_enabled, true),
            questions_public: params.fetch(:questions_public, true)
          )

          (params[:translations] || {}).each do |lang, attrs|
            session.qa_session_translations.build(languages_code: lang, name: attrs[:name])
          end

          if session.save
            render json: session_json(session), status: :created
          else
            render json: { error: session.errors.full_messages.first }, status: :unprocessable_content
          end
        end

        def update
          session = QaSession.find_by(code: params[:code])
          return render json: { error: 'QA session not found' }, status: :not_found unless session

          attrs = params.permit(:voting_enabled, :questions_public, :status)

          ActiveRecord::Base.transaction do
            if params[:translations].present?
              params[:translations].each do |lang, translation_attrs|
                t = session.qa_session_translations.find_or_initialize_by(languages_code: lang)
                t.name = translation_attrs[:name]
                t.save!
              end
            end
            session.update!(attrs)
          end
          render json: session_json(session.reload)
        rescue ActiveRecord::RecordInvalid => e
          render json: { error: e.message }, status: :unprocessable_content
        end

        def destroy
          session = QaSession.find_by(code: params[:code])
          return render json: { error: 'QA session not found' }, status: :not_found unless session

          session.destroy!
          head :no_content
        end

        private

          def load_event
            @event = Event.find_by(slug: params[:event_slug])
            render json: { error: 'Event not found' }, status: :not_found unless @event
          end

          def session_json(session)
            {
              code: session.code,
              status: session.status,
              voting_enabled: session.voting_enabled,
              questions_public: session.questions_public,
              question_count: session.qa_questions.size,
              translations: session.qa_session_translations.map do |t|
                { languages_code: t.languages_code, name: t.name }
              end,
              created_at: session.created_at
            }
          end
      end
    end
  end
end
