# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Admin WhatsApp Broadcasts' do
  let(:admin)    { create(:user, role: 'admin', phone_number: '+40700111000') }
  let(:token)    { JwtService.encode(admin.id) }
  let(:headers)  { { 'Content-Type' => 'application/json', 'Authorization' => "Bearer #{token}" } }
  let(:template) { create(:whatsapp_template) }

  before { allow(TwilioService).to receive(:send_whatsapp) }

  describe 'GET /api/v1/admin/whatsapp_broadcasts' do
    before { create(:whatsapp_broadcast, whatsapp_template: template, sent_by_user: admin, recipient_count: 5) }

    it 'returns last 50 broadcasts' do
      get '/api/v1/admin/whatsapp_broadcasts', headers: headers
      expect(response).to have_http_status(:ok)
      parsed = response.parsed_body
      expect(parsed.size).to eq(1)
      expect(parsed.first.keys).to include('id', 'template_id', 'template_name', 'event_id', 'recipient_count', 'sent_at')
    end

    context 'without JWT' do
      it 'returns 401' do
        get '/api/v1/admin/whatsapp_broadcasts', headers: { 'Content-Type' => 'application/json' }
        expect(response).to have_http_status(:unauthorized)
      end
    end
  end

  describe 'POST /api/v1/admin/whatsapp_broadcasts' do
    context 'when to: is present (test send)' do
      it 'calls TwilioService and returns sent_to: 1 without creating a broadcast' do
        expect do
          post '/api/v1/admin/whatsapp_broadcasts',
               params: {
                 template_id: template.id,
                 to: '+40700999888',
                 variables: { 'first_name' => 'Ion', 'event_name' => 'Fara Regrete' }
               }.to_json,
               headers: headers
        end.not_to change(WhatsappBroadcast, :count)

        expect(response).to have_http_status(:ok)
        expect(response.parsed_body).to eq('sent_to' => 1)
        expect(TwilioService).to have_received(:send_whatsapp).with(
          hash_including(to: '+40700999888', content_sid: template.content_sid)
        )
      end
    end

    context 'without to: (bulk send)' do
      let(:user_with_phone) { create(:user, phone_number: '+40700111222') }
      let(:event)           { create(:event) }

      before do
        ActiveJob::Base.queue_adapter = :test
        create(:attendee, event: event, user: user_with_phone, payment_status: :paid)
      end

      after { ActiveJob::Base.queue_adapter = :inline }

      it 'creates a broadcast and enqueues the job' do
        expect do
          post '/api/v1/admin/whatsapp_broadcasts',
               params: { template_id: template.id, event_id: event.id }.to_json,
               headers: headers
        end.to have_enqueued_job(SendWhatsappJob)
           .and change(WhatsappBroadcast, :count).by(1)

        expect(response).to have_http_status(:ok)
        parsed = response.parsed_body
        expect(parsed['broadcast_id']).to be_present
        expect(parsed['queued_for']).to be >= 1
      end

      it 'returns 404 when template not found' do
        post '/api/v1/admin/whatsapp_broadcasts',
             params: { template_id: 999_999 }.to_json,
             headers: headers
        expect(response).to have_http_status(:not_found)
      end
    end

    context 'with a non-admin JWT' do
      let(:token) { JwtService.encode(create(:user, role: 'attendee').id) }

      it 'returns 403' do
        post '/api/v1/admin/whatsapp_broadcasts',
             params: { template_id: template.id, to: '+40700000000' }.to_json,
             headers: headers
        expect(response).to have_http_status(:forbidden)
      end
    end
  end
end
