# frozen_string_literal: true

module EventTeamBroadcastable
  extend ActiveSupport::Concern

  private

    def broadcast_team_created(team)
      ActionCable.server.broadcast(
        "event_teams_#{team.event.slug}",
        { type: :team_created, team: broadcast_team_json(team) }
      )
    end

    def broadcast_team_updated(team)
      ActionCable.server.broadcast(
        "event_teams_#{team.event.slug}",
        { type: :team_updated, team: broadcast_team_json(team) }
      )
    end

    def broadcast_team_deleted(team)
      ActionCable.server.broadcast(
        "event_teams_#{team.event.slug}",
        { type: :team_deleted, team_id: team.id }
      )
    end

    def broadcast_score_updated(team, entry)
      ActionCable.server.broadcast(
        "event_teams_#{team.event.slug}",
        {
          type: :score_updated,
          team: broadcast_team_json(team),
          entry: broadcast_entry_json(entry)
        }
      )
    end

    def broadcast_team_json(team)
      { id: team.id, name: team.name, icon: team.icon, colour: team.colour, score: team.score }
    end

    def broadcast_entry_json(entry)
      {
        id: entry.id,
        delta: entry.delta,
        added_by: {
          first_name: entry.added_by_user.first_name,
          last_name: entry.added_by_user.last_name
        },
        created_at: entry.created_at
      }
    end
end
