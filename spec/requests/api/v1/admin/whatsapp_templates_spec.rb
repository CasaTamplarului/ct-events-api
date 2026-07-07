# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Admin WhatsApp Templates' do
  let(:admin)   { create(:user, role: 'admin') }
  let(:token)   { JwtService.encode(admin.id) }
  let(:headers) { { 'Content-Type' => 'application/json', 'Authorization' => "Bearer #{token}" } }

  describe 'GET /api/v1/admin/whatsapp_templates' do
    before { create_list(:whatsapp_template, 2) }

    it 'returns all templates' do
      get '/api/v1/admin/whatsapp_templates', headers: headers
      expect(response).to have_http_status(:ok)
      expect(response.parsed_body.size).to eq(2)
    end

    it 'returns id, name, content_sid, variables, created_at' do
      get '/api/v1/admin/whatsapp_templates', headers: headers
      parsed = response.parsed_body.first
      expect(parsed.keys).to include('id', 'name', 'content_sid', 'variables', 'created_at')
    end

    context 'with a non-admin JWT' do
      let(:token) { JwtService.encode(create(:user, role: 'attendee').id) }

      it 'returns 403' do
        get '/api/v1/admin/whatsapp_templates', headers: headers
        expect(response).to have_http_status(:forbidden)
      end
    end

    context 'without a JWT' do
      it 'returns 401' do
        get '/api/v1/admin/whatsapp_templates', headers: { 'Content-Type' => 'application/json' }
        expect(response).to have_http_status(:unauthorized)
      end
    end
  end

  describe 'POST /api/v1/admin/whatsapp_templates' do
    let(:valid_params) do
      {
        name: 'Event Reminder',
        content_sid: 'HXabc123',
        variables: [{ position: 1, name: 'first_name' }, { position: 2, name: 'event_name' }]
      }
    end

    it 'creates a template and returns 201' do
      expect do
        post '/api/v1/admin/whatsapp_templates', params: valid_params.to_json, headers: headers
      end.to change(WhatsappTemplate, :count).by(1)

      expect(response).to have_http_status(:created)
      parsed = response.parsed_body
      expect(parsed).to include('name' => 'Event Reminder', 'content_sid' => 'HXabc123')
      expect(parsed['variables'].first['name']).to eq('first_name')
    end

    it 'returns 422 when name is missing' do
      post '/api/v1/admin/whatsapp_templates',
           params: valid_params.merge(name: nil).to_json,
           headers: headers
      expect(response).to have_http_status(:unprocessable_content)
    end

    it 'returns 422 when content_sid is missing' do
      post '/api/v1/admin/whatsapp_templates',
           params: valid_params.merge(content_sid: nil).to_json,
           headers: headers
      expect(response).to have_http_status(:unprocessable_content)
    end

    context 'with a non-admin JWT' do
      let(:token) { JwtService.encode(create(:user, role: 'attendee').id) }

      it 'returns 403' do
        post '/api/v1/admin/whatsapp_templates', params: valid_params.to_json, headers: headers
        expect(response).to have_http_status(:forbidden)
      end
    end
  end
end
