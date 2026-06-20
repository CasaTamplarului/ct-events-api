# frozen_string_literal: true

require 'rails_helper'

RSpec.describe QaVote do
  let(:question) { create(:qa_question) }

  describe 'validations' do
    it 'is invalid with value 0' do
      vote = QaVote.new(qa_question: question, value: 0, voter_token: SecureRandom.uuid)
      expect(vote).not_to be_valid
    end

    it 'is valid with value 1' do
      vote = QaVote.new(qa_question: question, value: 1, voter_token: SecureRandom.uuid)
      expect(vote).to be_valid
    end

    it 'is valid with value -1' do
      vote = QaVote.new(qa_question: question, value: -1, voter_token: SecureRandom.uuid)
      expect(vote).to be_valid
    end

    it 'requires user_id or voter_token' do
      vote = QaVote.new(qa_question: question, value: 1)
      expect(vote).not_to be_valid
      expect(vote.errors[:base]).to include('must have user_id or voter_token')
    end
  end

  describe '.find_for' do
    let(:user)  { create(:user) }
    let(:token) { SecureRandom.uuid }

    it 'finds by user_id' do
      vote = create(:qa_vote, qa_question: question, value: 1, user_id: user.id, voter_token: nil)
      expect(QaVote.find_for(question: question, identity: { user_id: user.id, voter_token: nil })).to eq(vote)
    end

    it 'finds by voter_token' do
      vote = create(:qa_vote, qa_question: question, value: 1, voter_token: token)
      expect(QaVote.find_for(question: question, identity: { user_id: nil, voter_token: token })).to eq(vote)
    end

    it 'returns nil when not found' do
      expect(QaVote.find_for(question: question, identity: { user_id: nil, voter_token: 'missing' })).to be_nil
    end
  end
end
