# frozen_string_literal: true

module Api
  module V1
    module Admin
      class EventTeamsController < ActionController::API
        include Authenticatable

        before_action :authenticate_user!
        before_action { require_permission!(:can_manage_teams) }
        before_action :load_event
        before_action :load_team, only: %i[update destroy]

        def index
          teams = @event.event_teams.order(created_at: :asc)
          render json: teams.map { |t| team_json(t) }
        end

        def create
          team = @event.event_teams.new(team_params)
          if team.save
            render json: team_json(team), status: :created
          else
            render json: { error: team.errors.full_messages.first }, status: :unprocessable_content
          end
        end

        def update
          if @team.update(team_params)
            render json: team_json(@team)
          else
            render json: { error: @team.errors.full_messages.first }, status: :unprocessable_content
          end
        end

        def destroy
          @team.destroy!
          head :no_content
        end

        private

          def load_event
            @event = Event.find_by(slug: params[:event_slug])
            render json: { error: 'Event not found' }, status: :not_found unless @event
          end

          def load_team
            @team = @event.event_teams.find_by(id: params[:id])
            render json: { error: 'Team not found' }, status: :not_found unless @team
          end

          def team_params
            params.permit(:name, :icon, :colour)
          end

          def team_json(team)
            {
              id: team.id,
              name: team.name,
              icon: team.icon,
              colour: team.colour,
              score: team.score
            }
          end
      end
    end
  end
end
