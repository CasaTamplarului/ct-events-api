# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Admin Event Teams' do
  let(:admin)     { create(:user, role: 'admin') }
  let(:volunteer) { create(:user, role: 'volunteer') }
  let(:attendee)  { create(:user, role: 'attendee') }
  let(:event)     { create(:event) }

  def headers(user)
    { 'Content-Type' => 'application/json',
      'Authorization' => "Bearer #{JwtService.encode(user.id)}" }
  end

  describe 'POST /api/v1/admin/events/:event_slug/teams' do
    it 'creates a team with name only' do
      post "/api/v1/admin/events/#{event.slug}/teams",
           params: { name: 'Echipa Roșie' }.to_json,
           headers: headers(admin)
      expect(response).to have_http_status(:created)
      body = JSON.parse(response.body)
      expect(body['name']).to eq('Echipa Roșie')
      expect(body['icon']).to be_nil
      expect(body['colour']).to be_nil
      expect(body['score']).to eq(0)
    end

    it 'creates a team with icon only' do
      post "/api/v1/admin/events/#{event.slug}/teams",
           params: { icon: '🔥' }.to_json,
           headers: headers(admin)
      expect(response).to have_http_status(:created)
      expect(JSON.parse(response.body)['icon']).to eq('🔥')
    end

    it 'creates a team with all fields' do
      post "/api/v1/admin/events/#{event.slug}/teams",
           params: { name: 'Red', icon: '🔥', colour: '#FF5733' }.to_json,
           headers: headers(admin)
      expect(response).to have_http_status(:created)
      body = JSON.parse(response.body)
      expect(body['name']).to eq('Red')
      expect(body['colour']).to eq('#FF5733')
    end

    it 'returns 422 when all fields are blank' do
      post "/api/v1/admin/events/#{event.slug}/teams",
           params: {}.to_json,
           headers: headers(admin)
      expect(response).to have_http_status(:unprocessable_content)
      expect(JSON.parse(response.body)['error']).to include('At least one of name, icon, or colour')
    end

    it 'allows volunteers' do
      post "/api/v1/admin/events/#{event.slug}/teams",
           params: { name: 'Blue' }.to_json,
           headers: headers(volunteer)
      expect(response).to have_http_status(:created)
    end

    it 'rejects attendees with 403' do
      post "/api/v1/admin/events/#{event.slug}/teams",
           params: { name: 'Blue' }.to_json,
           headers: headers(attendee)
      expect(response).to have_http_status(:forbidden)
    end

    it 'returns 404 for unknown event slug' do
      post '/api/v1/admin/events/no-such-event/teams',
           params: { name: 'X' }.to_json,
           headers: headers(admin)
      expect(response).to have_http_status(:not_found)
    end

    it 'creates a team and broadcasts team_created' do
      expect {
        post "/api/v1/admin/events/#{event.slug}/teams",
             params: { name: 'Echipa Roșie', icon: '🔥', colour: '#FF5733' }.to_json,
             headers: headers(admin)
      }.to have_broadcasted_to("event_teams_#{event.slug}")
        .with(a_hash_including('type' => 'team_created'))
      expect(response).to have_http_status(:created)
    end
  end

  describe 'GET /api/v1/admin/events/:event_slug/teams' do
    it 'returns all teams ordered by created_at ascending' do
      create(:event_team, event: event, name: 'Red',  score: 5)
      create(:event_team, event: event, name: 'Blue', score: 12)

      get "/api/v1/admin/events/#{event.slug}/teams",
          headers: headers(admin)
      expect(response).to have_http_status(:ok)
      body = JSON.parse(response.body)
      expect(body.size).to eq(2)
      expect(body.map { |t| t['name'] }).to eq(%w[Red Blue])
      expect(body.first['score']).to eq(5)
    end

    it 'returns empty array when event has no teams' do
      get "/api/v1/admin/events/#{event.slug}/teams",
          headers: headers(admin)
      expect(response).to have_http_status(:ok)
      expect(JSON.parse(response.body)).to eq([])
    end
  end

  describe 'PATCH /api/v1/admin/events/:event_slug/teams/:id' do
    let(:team) { create(:event_team, event: event, name: 'Red') }

    it 'updates name and icon' do
      patch "/api/v1/admin/events/#{event.slug}/teams/#{team.id}",
            params: { name: 'Blue', icon: '💧' }.to_json,
            headers: headers(admin)
      expect(response).to have_http_status(:ok)
      body = JSON.parse(response.body)
      expect(body['name']).to eq('Blue')
      expect(body['icon']).to eq('💧')
    end

    it 'returns 404 for a team belonging to another event' do
      other_team = create(:event_team, name: 'Other')
      patch "/api/v1/admin/events/#{event.slug}/teams/#{other_team.id}",
            params: { name: 'X' }.to_json,
            headers: headers(admin)
      expect(response).to have_http_status(:not_found)
    end

    it 'updates the team and broadcasts team_updated' do
      expect {
        patch "/api/v1/admin/events/#{event.slug}/teams/#{team.id}",
              params: { colour: '#E63946' }.to_json,
              headers: headers(admin)
      }.to have_broadcasted_to("event_teams_#{event.slug}")
        .with(a_hash_including('type' => 'team_updated'))
      expect(response).to have_http_status(:ok)
    end
  end

  describe 'DELETE /api/v1/admin/events/:event_slug/teams/:id' do
    let!(:team) { create(:event_team, event: event, name: 'Red') }

    it 'deletes the team and returns 204' do
      delete "/api/v1/admin/events/#{event.slug}/teams/#{team.id}",
             headers: headers(admin)
      expect(response).to have_http_status(:no_content)
      expect(EventTeam.exists?(team.id)).to be false
    end

    it 'deletes associated score entries' do
      create(:event_team_score_entry, event_team: team, delta: 5, added_by_user: admin)
      delete "/api/v1/admin/events/#{event.slug}/teams/#{team.id}",
             headers: headers(admin)
      expect(EventTeamScoreEntry.where(event_team_id: team.id)).to be_empty
    end

    it 'deletes the team and broadcasts team_deleted' do
      expect {
        delete "/api/v1/admin/events/#{event.slug}/teams/#{team.id}",
               headers: headers(admin)
      }.to have_broadcasted_to("event_teams_#{event.slug}")
        .with(a_hash_including('type' => 'team_deleted', 'team_id' => team.id))
      expect(response).to have_http_status(:no_content)
    end
  end
end
