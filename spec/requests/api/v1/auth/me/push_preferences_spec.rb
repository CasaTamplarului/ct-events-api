# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'PATCH /api/v1/auth/me/push_preferences' do
  let(:user) { create(:user) }
  let(:token) { JwtService.encode(user.id) }

  def patch_preferences(params, jwt: token)
    patch '/api/v1/auth/me/push_preferences',
          params: params.to_json,
          headers: { 'Content-Type' => 'application/json', 'Authorization' => "Bearer #{jwt}" }
  end

  context 'with a valid JWT' do
    it 'returns 200 with the updated push_preferences object' do
      patch_preferences({ marketing_push: false, event_reminder_push: false })

      expect(response).to have_http_status(:ok)
      expect(json['push_preferences']['marketing_push']).to be false
      expect(json['push_preferences']['event_reminder_push']).to be false
    end

    it 'persists the updated values to the database' do
      patch_preferences({ payment_reminder_push: false })

      expect(user.reload.payment_reminder_push).to be false
    end

    it 'only changes provided fields and leaves others unchanged' do
      user.update!(event_reminder_push: false)
      patch_preferences({ marketing_push: false })

      expect(user.reload.event_reminder_push).to be false
      expect(user.reload.marketing_push).to be false
    end

    it 'returns all four push preference fields in the response' do
      patch_preferences({ marketing_push: false })

      expect(json['push_preferences'].keys).to match_array(%w[
                                                             marketing_push payment_reminder_push
                                                             event_reminder_push event_update_push
                                                           ])
    end

    it 'ignores unknown fields and still returns 200' do
      patch_preferences({ unknown_field: true, marketing_push: false })

      expect(response).to have_http_status(:ok)
      expect(json['push_preferences'].keys).to match_array(%w[
                                                             marketing_push payment_reminder_push
                                                             event_reminder_push event_update_push
                                                           ])
    end

    it 'persists a value being set back to true' do
      user.update!(marketing_push: false)
      patch_preferences({ marketing_push: true })

      expect(user.reload.marketing_push).to be true
    end
  end

  context 'without a JWT' do
    it 'returns 401' do
      patch '/api/v1/auth/me/push_preferences',
            params: { marketing_push: false }.to_json,
            headers: { 'Content-Type' => 'application/json' }

      expect(response).to have_http_status(:unauthorized)
    end
  end

  context 'with an invalid JWT' do
    it 'returns 401' do
      patch_preferences({ marketing_push: false }, jwt: 'invalid-token')
      expect(response).to have_http_status(:unauthorized)
    end
  end
end
