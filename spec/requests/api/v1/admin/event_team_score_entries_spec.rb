# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Admin Event Team Score Entries' do
  let(:admin)   { create(:user, role: 'admin') }
  let(:event)   { create(:event) }
  let(:team)    { create(:event_team, event: event, name: 'Red', score: 10) }
  let(:headers) do
    { 'Content-Type' => 'application/json',
      'Authorization' => "Bearer #{JwtService.encode(admin.id)}" }
  end

  describe 'POST /api/v1/admin/events/:event_slug/teams/:event_team_id/score_entries' do
    it 'adds a positive delta and reflects it in score_after and team score' do
      post "/api/v1/admin/events/#{event.slug}/teams/#{team.id}/score_entries",
           params: { delta: 5 }.to_json,
           headers: headers
      expect(response).to have_http_status(:created)
      body = response.parsed_body
      expect(body['delta']).to eq(5)
      expect(body['score_after']).to eq(15)
      expect(team.reload.score).to eq(15)
    end

    it 'subtracts with a negative delta' do
      post "/api/v1/admin/events/#{event.slug}/teams/#{team.id}/score_entries",
           params: { delta: -3 }.to_json,
           headers: headers
      expect(response).to have_http_status(:created)
      body = response.parsed_body
      expect(body['delta']).to eq(-3)
      expect(body['score_after']).to eq(7)
      expect(team.reload.score).to eq(7)
    end

    it 'returns 422 for a zero delta' do
      post "/api/v1/admin/events/#{event.slug}/teams/#{team.id}/score_entries",
           params: { delta: 0 }.to_json,
           headers: headers
      expect(response).to have_http_status(:unprocessable_content)
      expect(response.parsed_body['error']).to eq('Delta must be a non-zero integer')
    end

    it 'returns 422 when delta is missing' do
      post "/api/v1/admin/events/#{event.slug}/teams/#{team.id}/score_entries",
           params: {}.to_json,
           headers: headers
      expect(response).to have_http_status(:unprocessable_content)
    end

    it 'records the current user as added_by' do
      post "/api/v1/admin/events/#{event.slug}/teams/#{team.id}/score_entries",
           params: { delta: 1 }.to_json,
           headers: headers
      body = response.parsed_body
      expect(body['added_by']['first_name']).to eq(admin.first_name)
      expect(body['added_by']['last_name']).to eq(admin.last_name)
    end

    it 'returns 404 for unknown team' do
      post "/api/v1/admin/events/#{event.slug}/teams/99999/score_entries",
           params: { delta: 1 }.to_json,
           headers: headers
      expect(response).to have_http_status(:not_found)
    end

    it 'creates a score entry and broadcasts score_updated' do
      expect {
        post "/api/v1/admin/events/#{event.slug}/teams/#{team.id}/score_entries",
             params: { delta: 5 }.to_json,
             headers: headers
      }.to have_broadcasted_to("event_teams_#{event.slug}")
        .with(a_hash_including('type' => 'score_updated'))
      expect(response).to have_http_status(:created)
    end

    it 'rejects attendees with 403' do
      attendee = create(:user, role: 'attendee')
      post "/api/v1/admin/events/#{event.slug}/teams/#{team.id}/score_entries",
           params: { delta: 1 }.to_json,
           headers: { 'Content-Type' => 'application/json',
                      'Authorization' => "Bearer #{JwtService.encode(attendee.id)}" }
      expect(response).to have_http_status(:forbidden)
    end
  end

  describe 'GET /api/v1/admin/events/:event_slug/teams/:event_team_id/score_entries' do
    it 'returns score history in chronological order without score_after' do # rubocop:disable RSpec/MultipleExpectations
      create(:event_team_score_entry, event_team: team, delta: 10, added_by_user: admin)
      create(:event_team_score_entry, event_team: team, delta: -4, added_by_user: admin)

      get "/api/v1/admin/events/#{event.slug}/teams/#{team.id}/score_entries",
          headers: headers
      expect(response).to have_http_status(:ok)
      body = response.parsed_body
      expect(body.size).to eq(2)
      expect(body.pluck('delta')).to eq([10, -4])
      expect(body.first.key?('score_after')).to be false
      expect(body.first['added_by']['first_name']).to eq(admin.first_name)
    end

    it 'returns empty array when no entries exist' do
      get "/api/v1/admin/events/#{event.slug}/teams/#{team.id}/score_entries",
          headers: headers
      expect(response).to have_http_status(:ok)
      expect(response.parsed_body).to eq([])
    end
  end
end
