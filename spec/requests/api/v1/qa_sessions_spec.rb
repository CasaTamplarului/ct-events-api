# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'GET /api/v1/events/:event_slug/qa/:code' do
  let!(:language) { Language.find_or_create_by!(code: 'ro-RO') { |l| l.name = 'Romanian' } }
  let(:admin)     { create(:user, role: 'admin') }
  let(:event)     { create(:event, slug: 'my-event') }
  let(:session)   { create(:qa_session, event: event, created_by_user: admin, questions_public: true) }
  let!(:translation) { create(:qa_session_translation, qa_session: session, languages_code: 'ro-RO', name: 'Sesiunea 1') }
  let(:qa_token)  { SecureRandom.uuid }
  let(:headers)   { { 'Content-Type' => 'application/json', 'X-QA-Token' => qa_token } }

  def get_session(code: session.code, lang: 'ro-RO')
    get "/api/v1/events/my-event/qa/#{code}?lang=#{lang}", headers: headers
  end

  it 'returns session info with translated name' do
    get_session
    expect(response).to have_http_status(:ok)
    expect(json['code']).to eq(session.code)
    expect(json['name']).to eq('Sesiunea 1')
    expect(json['status']).to eq('open')
    expect(json['voting_enabled']).to be true
    expect(json['questions_public']).to be true
    expect(json['questions']).to eq([])
  end

  it 'returns 404 for unknown session' do
    get_session(code: 'NOTEXIST')
    expect(response).to have_http_status(:not_found)
  end

  it 'returns 404 for unknown event' do
    get '/api/v1/events/no-such-event/qa/ANYCODE', headers: headers
    expect(response).to have_http_status(:not_found)
  end

  context 'with questions' do
    let!(:q1) { create(:qa_question, qa_session: session, body: 'Alpha?', submitter_token: qa_token) }
    let!(:q2) { create(:qa_question, qa_session: session, body: 'Beta?', submitter_token: 'other-token') }

    before do
      create(:qa_vote, qa_question: q1, value: 1, voter_token: qa_token)
      create(:qa_vote, qa_question: q2, value: 1, voter_token: SecureRandom.uuid)
      create(:qa_vote, qa_question: q2, value: 1, voter_token: SecureRandom.uuid)
    end

    it 'returns questions sorted by score descending' do
      get_session
      bodies = json['questions'].map { |q| q['body'] }
      expect(bodies).to eq(['Beta?', 'Alpha?'])
    end

    it 'returns my_vote for the requester' do
      get_session
      q1_json = json['questions'].find { |q| q['body'] == 'Alpha?' }
      q2_json = json['questions'].find { |q| q['body'] == 'Beta?' }
      expect(q1_json['my_vote']).to eq(1)
      expect(q2_json['my_vote']).to be_nil
    end

    it 'returns can_delete true only for own questions' do
      get_session
      q1_json = json['questions'].find { |q| q['body'] == 'Alpha?' }
      q2_json = json['questions'].find { |q| q['body'] == 'Beta?' }
      expect(q1_json['can_delete']).to be true
      expect(q2_json['can_delete']).to be false
    end

    it 'returns correct my_vote and can_delete for authenticated user' do
      user = create(:user)
      token = JwtService.encode(user.id)
      auth_question = create(:qa_question, qa_session: session, body: 'User question?', user_id: user.id, submitter_token: nil)
      create(:qa_vote, qa_question: auth_question, value: -1, user_id: user.id, voter_token: nil)

      get "/api/v1/events/my-event/qa/#{session.code}?lang=ro-RO",
          headers: { 'Content-Type' => 'application/json', 'Authorization' => "Bearer #{token}" }

      q_json = json['questions'].find { |q| q['body'] == 'User question?' }
      expect(q_json['my_vote']).to eq(-1)
      expect(q_json['can_delete']).to be true
    end
  end

  context 'when questions_public is false' do
    let(:session) { create(:qa_session, event: event, created_by_user: admin, questions_public: false) }
    let!(:own_question)   { create(:qa_question, qa_session: session, body: 'Mine?',   submitter_token: qa_token) }
    let!(:other_question) { create(:qa_question, qa_session: session, body: 'Others?', submitter_token: 'other') }

    it 'returns only the requester own questions' do
      get_session
      bodies = json['questions'].map { |q| q['body'] }
      expect(bodies).to eq(['Mine?'])
      expect(bodies).not_to include('Others?')
    end
  end

  context 'name fallback' do
    it 'falls back to first available translation when lang not found' do
      get_session(lang: 'fr-FR')
      expect(json['name']).to eq('Sesiunea 1')
    end
  end
end
