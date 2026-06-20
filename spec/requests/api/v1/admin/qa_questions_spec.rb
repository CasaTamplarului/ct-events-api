# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Admin Q&A Questions' do
  let(:admin)   { create(:user, role: 'admin') }
  let(:event)   { create(:event) }
  let(:session) { create(:qa_session, event: event, created_by_user: admin) }
  let(:headers) { { 'Content-Type' => 'application/json', 'Authorization' => "Bearer #{JwtService.encode(admin.id)}" } }

  describe 'GET /api/v1/admin/qa_sessions/:code/questions' do
    let!(:q1) { create(:qa_question, qa_session: session, body: 'Question A') }
    let!(:q2) { create(:qa_question, qa_session: session, body: 'Question B') }

    before do
      create(:qa_vote, qa_question: q1, value: 1, voter_token: SecureRandom.uuid)
      create(:qa_vote, qa_question: q1, value: 1, voter_token: SecureRandom.uuid)
      create(:qa_vote, qa_question: q2, value: -1, voter_token: SecureRandom.uuid)
    end

    it 'returns questions sorted by score descending' do
      get "/api/v1/admin/qa_sessions/#{session.code}/questions", headers: headers

      expect(response).to have_http_status(:ok)
      bodies = json.map { |q| q['body'] }
      expect(bodies).to eq(['Question A', 'Question B'])
    end

    it 'returns correct scores' do
      get "/api/v1/admin/qa_sessions/#{session.code}/questions", headers: headers

      q1_json = json.find { |q| q['body'] == 'Question A' }
      q2_json = json.find { |q| q['body'] == 'Question B' }
      expect(q1_json['score']).to eq(2)
      expect(q2_json['score']).to eq(-1)
    end

    it 'returns 401 without auth' do
      get "/api/v1/admin/qa_sessions/#{session.code}/questions"
      expect(response).to have_http_status(:unauthorized)
    end
  end

  describe 'DELETE /api/v1/admin/qa_sessions/:code/questions/:id' do
    let!(:question) { create(:qa_question, qa_session: session) }

    it 'removes the question and returns 204' do
      delete "/api/v1/admin/qa_sessions/#{session.code}/questions/#{question.id}", headers: headers

      expect(response).to have_http_status(:no_content)
      expect(QaQuestion.find_by(id: question.id)).to be_nil
    end

    it 'cascades to votes' do
      create(:qa_vote, qa_question: question, value: 1, voter_token: SecureRandom.uuid)
      delete "/api/v1/admin/qa_sessions/#{session.code}/questions/#{question.id}", headers: headers

      expect(QaVote.where(qa_question_id: question.id)).to be_empty
    end
  end
end
