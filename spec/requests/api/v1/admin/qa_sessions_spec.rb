# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Admin Q&A Sessions' do
  let!(:language) { Language.find_or_create_by!(code: 'ro-RO') { |l| l.name = 'Romanian' } }
  let(:admin)     { create(:user, role: 'admin') }
  let(:non_admin) { create(:user, role: 'attendee') }
  let(:event)     { create(:event, slug: 'my-event') }
  let(:headers)   { { 'Content-Type' => 'application/json', 'Authorization' => "Bearer #{JwtService.encode(admin.id)}" } }
  let(:non_admin_headers) { { 'Content-Type' => 'application/json', 'Authorization' => "Bearer #{JwtService.encode(non_admin.id)}" } }

  describe 'GET /api/v1/admin/events/:event_slug/qa_sessions' do
    let!(:session) { create(:qa_session, event: event, created_by_user: admin) }
    let!(:translation) { create(:qa_session_translation, qa_session: session, languages_code: 'ro-RO', name: 'Sesiunea 1') }

    it 'returns 401 without auth' do
      get "/api/v1/admin/events/#{event.slug}/qa_sessions"
      expect(response).to have_http_status(:unauthorized)
    end

    it 'returns 403 for non-admin' do
      get "/api/v1/admin/events/#{event.slug}/qa_sessions", headers: non_admin_headers
      expect(response).to have_http_status(:forbidden)
    end

    it 'returns sessions with translations and question_count' do
      create(:qa_question, qa_session: session)
      get "/api/v1/admin/events/#{event.slug}/qa_sessions", headers: headers

      expect(response).to have_http_status(:ok)
      body = json
      expect(body).to be_an(Array)
      expect(body.length).to eq(1)

      s = body.first
      expect(s['code']).to eq(session.code)
      expect(s['status']).to eq('open')
      expect(s['voting_enabled']).to be true
      expect(s['questions_public']).to be true
      expect(s['question_count']).to eq(1)
      expect(s['translations'].first['languages_code']).to eq('ro-RO')
      expect(s['translations'].first['name']).to eq('Sesiunea 1')
    end

    it 'returns 404 for unknown event' do
      get '/api/v1/admin/events/nonexistent/qa_sessions', headers: headers
      expect(response).to have_http_status(:not_found)
    end
  end

  describe 'POST /api/v1/admin/events/:event_slug/qa_sessions' do
    let(:params) do
      {
        voting_enabled: true,
        questions_public: false,
        translations: { 'ro-RO' => { name: 'Sesiunea 1' } }
      }
    end

    it 'creates a session with an auto-generated code' do
      post "/api/v1/admin/events/#{event.slug}/qa_sessions",
           params: params.to_json, headers: headers

      expect(response).to have_http_status(:created)
      expect(json['code']).to match(/\A[A-Z0-9]{8}\z/)
      expect(json['status']).to eq('open')
      expect(json['voting_enabled']).to be true
      expect(json['questions_public']).to be false
      expect(json['translations'].first['name']).to eq('Sesiunea 1')
    end

    it 'returns 403 for non-admin' do
      post "/api/v1/admin/events/#{event.slug}/qa_sessions",
           params: params.to_json, headers: non_admin_headers
      expect(response).to have_http_status(:forbidden)
    end
  end

  describe 'PATCH /api/v1/admin/qa_sessions/:code' do
    let!(:session) { create(:qa_session, event: event, created_by_user: admin, status: :open) }
    let!(:translation) { create(:qa_session_translation, qa_session: session, languages_code: 'ro-RO', name: 'Old') }

    it 'closes the session' do
      patch "/api/v1/admin/qa_sessions/#{session.code}",
            params: { status: 'closed' }.to_json, headers: headers

      expect(response).to have_http_status(:ok)
      expect(json['status']).to eq('closed')
      expect(session.reload).to be_closed
    end

    it 'updates a translation name' do
      patch "/api/v1/admin/qa_sessions/#{session.code}",
            params: { translations: { 'ro-RO' => { name: 'Updated' } } }.to_json, headers: headers

      expect(response).to have_http_status(:ok)
      expect(session.qa_session_translations.find_by(languages_code: 'ro-RO').name).to eq('Updated')
    end

    it 'toggles voting_enabled' do
      patch "/api/v1/admin/qa_sessions/#{session.code}",
            params: { voting_enabled: false }.to_json, headers: headers

      expect(response).to have_http_status(:ok)
      expect(json['voting_enabled']).to be false
    end
  end

  describe 'DELETE /api/v1/admin/qa_sessions/:code' do
    let!(:session) { create(:qa_session, event: event, created_by_user: admin) }

    it 'deletes the session and returns 204' do
      delete "/api/v1/admin/qa_sessions/#{session.code}", headers: headers

      expect(response).to have_http_status(:no_content)
      expect(QaSession.find_by(code: session.code)).to be_nil
    end

    it 'returns 403 for non-admin' do
      delete "/api/v1/admin/qa_sessions/#{session.code}", headers: non_admin_headers
      expect(response).to have_http_status(:forbidden)
    end
  end
end
