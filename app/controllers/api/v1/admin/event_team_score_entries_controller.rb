# frozen_string_literal: true

module Api
  module V1
    module Admin
      class EventTeamScoreEntriesController < ActionController::API
        include Authenticatable
        include EventTeamBroadcastable

        before_action :authenticate_user!
        before_action { require_permission!(:can_manage_teams) }
        before_action :load_team

        def index
          entries = @team.score_entries
                         .includes(:added_by_user)
                         .order(created_at: :asc)
          render json: entries.map { |e| entry_json(e) }
        end

        def create
          delta = params[:delta].to_i

          if delta.zero?
            return render json: { error: 'Delta must be a non-zero integer' },
                          status: :unprocessable_content
          end

          entry = nil
          ActiveRecord::Base.transaction do
            entry = @team.score_entries.create!(delta: delta, added_by_user: current_user)
            @team.increment!(:score, delta) # rubocop:disable Rails/SkipsModelValidations
          end

          render json: entry_json(entry, score_after: @team.reload.score), status: :created
          broadcast_score_updated(@team, entry)
        rescue ActiveRecord::RecordInvalid => e
          render json: { error: e.message }, status: :unprocessable_content
        end

        private

          def load_team
            event = Event.find_by(slug: params[:event_slug])
            return render json: { error: 'Event not found' }, status: :not_found unless event

            @team = event.event_teams.find_by(id: params[:event_team_id])
            render json: { error: 'Team not found' }, status: :not_found unless @team
          end

          def entry_json(entry, score_after: nil)
            hash = {
              id: entry.id,
              delta: entry.delta,
              added_by: {
                first_name: entry.added_by_user.first_name,
                last_name: entry.added_by_user.last_name
              },
              created_at: entry.created_at
            }
            hash[:score_after] = score_after unless score_after.nil?
            hash
          end
      end
    end
  end
end
