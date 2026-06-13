# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Bracelets scan API' do
  let(:admin)         { create(:user, role: 'admin') }
  let(:attendee_user) { create(:user, role: 'attendee') }
  let(:event)         { create(:event, status: :live) }
  let(:order)         { create(:order) }
  let!(:attendee)     { create(:attendee, event: event, order: order) }

  def auth_header(user)
    { 'Authorization' => "Bearer #{JwtService.encode(user.id)}", 'Content-Type' => 'application/json' }
  end

  # ── generate ─────────────────────────────────────────────────────────────────

  describe 'POST /api/v1/scan/bracelets/generate' do
    def post_generate(event_id: event.id, quantity: 3, code_length: 5, user: admin)
      post '/api/v1/scan/bracelets/generate',
           params: { event_id: event_id, quantity: quantity, code_length: code_length }.to_json,
           headers: auth_header(user)
    end

    it 'returns 401 without token' do
      post '/api/v1/scan/bracelets/generate',
           params: { event_id: event.id, quantity: 3, code_length: 5 }.to_json,
           headers: { 'Content-Type' => 'application/json' }
      expect(response).to have_http_status(:unauthorized)
    end

    it 'returns 403 for attendee role' do
      post_generate(user: attendee_user)
      expect(response).to have_http_status(:forbidden)
    end

    it 'returns 404 for unknown event' do
      post_generate(event_id: 999_999)
      expect(response).to have_http_status(:not_found)
    end

    it 'returns 422 for invalid quantity' do
      post_generate(quantity: 0)
      expect(response).to have_http_status(:unprocessable_content)
    end

    it 'returns 422 for invalid code_length' do
      post_generate(code_length: 7)
      expect(response).to have_http_status(:unprocessable_content)
    end

    it 'generates the requested number of codes' do
      post_generate(quantity: 5, code_length: 4)
      expect(response).to have_http_status(:created)
      expect(json['codes'].size).to eq(5)
    end

    it 'codes have the correct prefix and length' do
      post_generate(quantity: 2, code_length: 6)
      json['codes'].each do |code|
        prefix, random = code.split('-', 2)
        expect(prefix).to eq(event.id.to_s)
        expect(random.length).to eq(6)
        expect(random).to match(/\A[A-Z0-9]+\z/)
      end
    end

    it 'persists codes to the database' do
      expect { post_generate(quantity: 3) }.to change(Bracelet, :count).by(3)
    end

    it 'codes are unique' do
      post_generate(quantity: 10, code_length: 4)
      expect(json['codes'].uniq.size).to eq(10)
    end
  end

  # ── assign ────────────────────────────────────────────────────────────────────

  describe 'POST /api/v1/scan/bracelets/assign' do
    let(:bracelet_code) { "#{event.id}-ABCDE" }

    def post_assign(bracelet_code: "#{event.id}-ABCDE", attendee_id: attendee.id, user: admin)
      post '/api/v1/scan/bracelets/assign',
           params: { bracelet_code: bracelet_code, attendee_id: attendee_id }.to_json,
           headers: auth_header(user)
    end

    it 'returns 401 without token' do
      post '/api/v1/scan/bracelets/assign',
           params: { bracelet_code: bracelet_code, attendee_id: attendee.id }.to_json,
           headers: { 'Content-Type' => 'application/json' }
      expect(response).to have_http_status(:unauthorized)
    end

    it 'returns 403 for attendee role' do
      post_assign(user: attendee_user)
      expect(response).to have_http_status(:forbidden)
    end

    it 'returns 404 for unknown attendee' do
      post_assign(attendee_id: 999_999)
      expect(response).to have_http_status(:not_found)
    end

    it 'assigns a new bracelet code to the attendee' do
      post_assign
      expect(response).to have_http_status(:ok)
      expect(json['code']).to eq(bracelet_code)
      expect(json['attendee_id']).to eq(attendee.id)
      expect(json['order_reference']).to eq(order.order_reference)
    end

    it 'creates a bracelet record' do
      expect { post_assign }.to change(Bracelet, :count).by(1)
    end

    it 'reassigns an existing bracelet to a different attendee' do
      other_attendee = create(:attendee, event: event, order: order)
      create(:bracelet, code: bracelet_code, event: event, attendee: other_attendee)

      post_assign
      expect(response).to have_http_status(:ok)
      expect(Bracelet.find_by(code: bracelet_code).attendee_id).to eq(attendee.id)
    end

    it 'does not create a duplicate bracelet record on reassign' do
      create(:bracelet, code: bracelet_code, event: event, attendee: attendee)
      expect { post_assign }.not_to change(Bracelet, :count)
    end
  end

  # ── show ──────────────────────────────────────────────────────────────────────

  describe 'GET /api/v1/scan/bracelets/:code' do
    let!(:bracelet) { create(:bracelet, code: "#{event.id}-XYZ99", event: event, attendee: attendee) }

    def get_bracelet(code: bracelet.code, user: admin)
      get "/api/v1/scan/bracelets/#{code}", headers: auth_header(user)
    end

    it 'returns 401 without token' do
      get "/api/v1/scan/bracelets/#{bracelet.code}"
      expect(response).to have_http_status(:unauthorized)
    end

    it 'returns 403 for attendee role' do
      get_bracelet(user: attendee_user)
      expect(response).to have_http_status(:forbidden)
    end

    it 'returns 404 for unknown code' do
      get_bracelet(code: 'UNKNOWN-CODE')
      expect(response).to have_http_status(:not_found)
    end

    it 'returns 404 for unassigned bracelet' do
      unassigned = create(:bracelet, event: event, attendee: nil)
      get_bracelet(code: unassigned.code)
      expect(response).to have_http_status(:not_found)
    end

    it 'returns order_reference and attendee_id' do
      get_bracelet
      expect(response).to have_http_status(:ok)
      expect(json['order_reference']).to eq(order.order_reference)
      expect(json['attendee_id']).to eq(attendee.id)
    end
  end
end
