# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Public Q&A Questions' do
  let(:admin)    { create(:user, role: 'admin') }
  let(:event)    { create(:event, slug: 'my-event') }
  let(:session)  { create(:qa_session, event: event, created_by_user: admin, status: :open) }
  let(:qa_token) { SecureRandom.uuid }
  let(:headers)  { { 'Content-Type' => 'application/json', 'X-QA-Token' => qa_token } }

  describe 'POST /api/v1/events/:event_slug/qa/:code/questions' do
    let(:params) { { body: 'What time?', display_name: 'Timo' } }

    def post_question(p = params)
      post "/api/v1/events/my-event/qa/#{session.code}/questions",
           params: p.to_json, headers: headers
    end

    it 'creates a question and returns 201' do
      post_question
      expect(response).to have_http_status(:created)
      expect(json['body']).to eq('What time?')
      expect(json['display_name']).to eq('Timo')
      expect(json['score']).to eq(0)
      expect(json['my_vote']).to be_nil
      expect(json['can_delete']).to be true
    end

    it 'creates anonymous question when display_name omitted' do
      post_question(body: 'Question?')
      expect(response).to have_http_status(:created)
      expect(json['display_name']).to be_nil
    end

    it 'returns 422 when session is closed' do
      session.closed!
      post_question
      expect(response).to have_http_status(:unprocessable_content)
    end

    it 'returns 422 without body' do
      post_question(display_name: 'Timo')
      expect(response).to have_http_status(:unprocessable_content)
    end

    it 'returns 422 without X-QA-Token and no JWT' do
      post "/api/v1/events/my-event/qa/#{session.code}/questions",
           params: params.to_json,
           headers: { 'Content-Type' => 'application/json' }
      expect(response).to have_http_status(:unprocessable_content)
    end

    it 'associates question with authenticated user when JWT provided' do
      user  = create(:user)
      token = JwtService.encode(user.id)
      post "/api/v1/events/my-event/qa/#{session.code}/questions",
           params: params.to_json,
           headers: { 'Content-Type' => 'application/json', 'Authorization' => "Bearer #{token}" }

      expect(response).to have_http_status(:created)
      question = QaQuestion.last
      expect(question.user_id).to eq(user.id)
      expect(question.submitter_token).to be_nil
    end
  end

  describe 'DELETE /api/v1/events/:event_slug/qa/:code/questions/:id' do
    let!(:question) { create(:qa_question, qa_session: session, submitter_token: qa_token) }
    let!(:other_q)  { create(:qa_question, qa_session: session, submitter_token: 'different-token') }

    it 'deletes own question and returns 204' do
      delete "/api/v1/events/my-event/qa/#{session.code}/questions/#{question.id}", headers: headers
      expect(response).to have_http_status(:no_content)
      expect(QaQuestion.find_by(id: question.id)).to be_nil
    end

    it 'returns 403 when trying to delete another user question' do
      delete "/api/v1/events/my-event/qa/#{session.code}/questions/#{other_q.id}", headers: headers
      expect(response).to have_http_status(:forbidden)
    end
  end
end
