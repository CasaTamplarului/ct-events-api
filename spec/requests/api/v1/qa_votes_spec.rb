# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Public Q&A Votes' do
  let(:admin)    { create(:user, role: 'admin') }
  let(:event)    { create(:event, slug: 'my-event') }
  let(:session)  { create(:qa_session, event: event, created_by_user: admin, voting_enabled: true) }
  let(:question) { create(:qa_question, qa_session: session) }
  let(:qa_token) { SecureRandom.uuid }
  let(:headers)  { { 'Content-Type' => 'application/json', 'X-QA-Token' => qa_token } }

  def post_vote(value)
    post "/api/v1/events/my-event/qa/#{session.code}/questions/#{question.id}/vote",
         params: { value: value }.to_json, headers: headers
  end

  describe 'POST …/vote (no existing vote)' do
    it 'creates a vote and returns 201 with my_vote' do
      post_vote(1)
      expect(response).to have_http_status(:created)
      expect(json['my_vote']).to eq(1)
      expect(QaVote.count).to eq(1)
    end

    it 'creates a downvote' do
      post_vote(-1)
      expect(response).to have_http_status(:created)
      expect(json['my_vote']).to eq(-1)
    end

    it 'returns 422 for invalid value' do
      post_vote(0)
      expect(response).to have_http_status(:unprocessable_content)
    end
  end

  describe 'POST …/vote (toggle: same value again)' do
    before { create(:qa_vote, qa_question: question, value: 1, voter_token: qa_token) }

    it 'deletes the vote and returns my_vote: null' do
      post_vote(1)
      expect(response).to have_http_status(:ok)
      expect(json['my_vote']).to be_nil
      expect(QaVote.count).to eq(0)
    end
  end

  describe 'POST …/vote (switch: opposite value)' do
    before { create(:qa_vote, qa_question: question, value: 1, voter_token: qa_token) }

    it 'updates the vote direction and returns 200' do
      post_vote(-1)
      expect(response).to have_http_status(:ok)
      expect(json['my_vote']).to eq(-1)
      expect(QaVote.count).to eq(1)
      expect(QaVote.first.value).to eq(-1)
    end
  end

  describe 'session constraints' do
    it 'returns 422 when session is closed' do
      session.closed!
      post_vote(1)
      expect(response).to have_http_status(:unprocessable_content)
    end

    it 'returns 422 when voting is disabled' do
      session.update!(voting_enabled: false)
      post_vote(1)
      expect(response).to have_http_status(:unprocessable_content)
    end
  end

  describe 'identity' do
    it 'returns 422 without X-QA-Token and no JWT' do
      post "/api/v1/events/my-event/qa/#{session.code}/questions/#{question.id}/vote",
           params: { value: 1 }.to_json,
           headers: { 'Content-Type' => 'application/json' }
      expect(response).to have_http_status(:unprocessable_content)
    end

    it 'uses user_id from JWT when authenticated' do
      user  = create(:user)
      token = JwtService.encode(user.id)
      post "/api/v1/events/my-event/qa/#{session.code}/questions/#{question.id}/vote",
           params: { value: 1 }.to_json,
           headers: { 'Content-Type' => 'application/json', 'Authorization' => "Bearer #{token}" }

      expect(response).to have_http_status(:created)
      expect(QaVote.last.user_id).to eq(user.id)
    end
  end

  describe '404 cases' do
    it 'returns 404 for unknown event slug' do
      post "/api/v1/events/no-such-event/qa/#{session.code}/questions/#{question.id}/vote",
           params: { value: 1 }.to_json, headers: headers
      expect(response).to have_http_status(:not_found)
    end

    it 'returns 404 for unknown session code' do
      post "/api/v1/events/my-event/qa/BADCODE/questions/#{question.id}/vote",
           params: { value: 1 }.to_json, headers: headers
      expect(response).to have_http_status(:not_found)
    end

    it 'returns 404 for unknown question id' do
      post "/api/v1/events/my-event/qa/#{session.code}/questions/0/vote",
           params: { value: 1 }.to_json, headers: headers
      expect(response).to have_http_status(:not_found)
    end
  end
end
