# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'PATCH /api/v1/auth/me/email_preferences' do
  let(:user) { create(:user) }
  let(:token) { JwtService.encode(user.id) }

  def patch_preferences(params, jwt: token)
    patch '/api/v1/auth/me/email_preferences',
          params: params.to_json,
          headers: { 'Content-Type' => 'application/json', 'Authorization' => "Bearer #{jwt}" }
  end

  context 'with a valid JWT' do
    it 'returns 200 with the updated email_preferences object' do
      patch_preferences({ marketing_emails: true, event_reminder_emails: true })

      expect(response).to have_http_status(:ok)
      expect(json['email_preferences']['marketing_emails']).to be true
      expect(json['email_preferences']['event_reminder_emails']).to be true
    end

    it 'persists the updated values to the database' do
      patch_preferences({ payment_reminder_emails: true })

      expect(user.reload.payment_reminder_emails).to be true
    end

    it 'only changes provided fields and leaves others unchanged' do
      user.update!(event_reminder_emails: true)
      patch_preferences({ marketing_emails: true })

      expect(user.reload.event_reminder_emails).to be true
      expect(user.reload.marketing_emails).to be true
    end

    it 'returns all five preference fields in the response' do
      patch_preferences({ marketing_emails: false })

      expect(json['email_preferences'].keys).to match_array(%w[
        marketing_emails payment_reminder_emails payment_receipt_emails
        event_reminder_emails event_update_emails
      ])
    end

    it 'ignores unknown fields and still returns 200' do
      patch_preferences({ unknown_field: true, marketing_emails: true })

      expect(response).to have_http_status(:ok)
      expect(json['email_preferences'].keys).to match_array(%w[
        marketing_emails payment_reminder_emails payment_receipt_emails
        event_reminder_emails event_update_emails
      ])
    end
  end

  context 'without a JWT' do
    it 'returns 401' do
      patch '/api/v1/auth/me/email_preferences',
            params: { marketing_emails: true }.to_json,
            headers: { 'Content-Type' => 'application/json' }

      expect(response).to have_http_status(:unauthorized)
    end
  end

  context 'with an invalid JWT' do
    it 'returns 401' do
      patch_preferences({ marketing_emails: true }, jwt: 'invalid-token')
      expect(response).to have_http_status(:unauthorized)
    end
  end
end
