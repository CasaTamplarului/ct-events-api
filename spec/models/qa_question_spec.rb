# frozen_string_literal: true

require 'rails_helper'

RSpec.describe QaQuestion do
  let(:session) { create(:qa_session) }

  describe 'validations' do
    it 'is invalid without body' do
      q = QaQuestion.new(qa_session: session, submitter_token: SecureRandom.uuid)
      expect(q).not_to be_valid
      expect(q.errors[:body]).to be_present
    end

    it 'is invalid without user_id or submitter_token' do
      q = QaQuestion.new(qa_session: session, body: 'Question?')
      expect(q).not_to be_valid
      expect(q.errors[:base]).to include('must have user or submitter token')
    end

    it 'is valid with user_id' do
      user = create(:user)
      q = QaQuestion.new(qa_session: session, body: 'Question?', user_id: user.id)
      expect(q).to be_valid
    end

    it 'is valid with submitter_token' do
      q = QaQuestion.new(qa_session: session, body: 'Question?', submitter_token: SecureRandom.uuid)
      expect(q).to be_valid
    end
  end

  describe '#submitted_by?' do
    let(:user)  { create(:user) }
    let(:token) { SecureRandom.uuid }

    it 'matches by user_id' do
      q = create(:qa_question, qa_session: session, user_id: user.id, submitter_token: nil)
      expect(q.submitted_by?({ user_id: user.id, voter_token: nil })).to be true
      expect(q.submitted_by?({ user_id: user.id + 1, voter_token: nil })).to be false
    end

    it 'matches by voter_token' do
      q = create(:qa_question, qa_session: session, submitter_token: token)
      expect(q.submitted_by?({ user_id: nil, voter_token: token })).to be true
      expect(q.submitted_by?({ user_id: nil, voter_token: 'other' })).to be false
    end

    it 'returns false for nil identity' do
      q = create(:qa_question, qa_session: session, submitter_token: token)
      expect(q.submitted_by?(nil)).to be false
    end
  end

  describe '#score' do
    let(:question) { create(:qa_question, qa_session: session) }

    it 'sums vote values' do
      create(:qa_vote, qa_question: question, value: 1, voter_token: SecureRandom.uuid)
      create(:qa_vote, qa_question: question, value: 1, voter_token: SecureRandom.uuid)
      create(:qa_vote, qa_question: question, value: -1, voter_token: SecureRandom.uuid)
      expect(question.qa_votes.reload.sum(&:value)).to eq(1)
    end
  end
end
