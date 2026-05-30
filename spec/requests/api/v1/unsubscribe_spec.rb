# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'GET /api/v1/unsubscribe' do
  before { ENV['FRONTEND_URL'] = 'http://localhost:3001' }
  after  { ENV.delete('FRONTEND_URL') }

  def get_unsubscribe(token)
    get "/api/v1/unsubscribe?token=#{CGI.escape(token)}"
  end

  context 'with a valid token for marketing_emails' do
    let(:user) { create(:user, marketing_emails: true) }
    let(:token) { EmailUnsubscribeTokenService.generate(user: user, type: 'marketing_emails') }

    it 'sets marketing_emails to false' do
      get_unsubscribe(token)
      expect(user.reload.marketing_emails).to be false
    end

    it 'redirects to the frontend unsubscribed page with the type param' do
      get_unsubscribe(token)
      expect(response).to redirect_to('http://localhost:3001/unsubscribed?type=marketing_emails')
    end
  end

  context 'with a valid token for event_reminder_emails' do
    let(:user) { create(:user, event_reminder_emails: true) }
    let(:token) { EmailUnsubscribeTokenService.generate(user: user, type: 'event_reminder_emails') }

    it 'sets event_reminder_emails to false' do
      get_unsubscribe(token)
      expect(user.reload.event_reminder_emails).to be false
    end

    it 'redirects with the correct type param' do
      get_unsubscribe(token)
      expect(response).to redirect_to('http://localhost:3001/unsubscribed?type=event_reminder_emails')
    end
  end

  context 'when the user is already unsubscribed (idempotent)' do
    let(:user) { create(:user, marketing_emails: false) }
    let(:token) { EmailUnsubscribeTokenService.generate(user: user, type: 'marketing_emails') }

    it 'still redirects with the type param' do
      get_unsubscribe(token)
      expect(response).to redirect_to('http://localhost:3001/unsubscribed?type=marketing_emails')
    end
  end

  context 'with an invalid token' do
    it 'redirects with error=invalid_token' do
      get_unsubscribe('not-a-real-token')
      expect(response).to redirect_to('http://localhost:3001/unsubscribed?error=invalid_token')
    end
  end

  context 'with a token for a soft-deleted user' do
    let(:user) { create(:user) }
    let(:token) { EmailUnsubscribeTokenService.generate(user: user, type: 'marketing_emails') }

    it 'redirects with error=invalid_token' do
      user.update!(deleted_at: Time.current)
      get_unsubscribe(token)
      expect(response).to redirect_to('http://localhost:3001/unsubscribed?error=invalid_token')
    end
  end
end
