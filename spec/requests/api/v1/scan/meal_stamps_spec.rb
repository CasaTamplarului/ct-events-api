# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'POST /api/v1/scan/meal_stamps' do
  let(:admin)         { create(:user, role: 'admin', first_name: 'Ana', last_name: 'Ionescu') }
  let(:attendee_user) { create(:user, role: 'attendee') }
  let(:event)         { create(:event, start_date: 2.days.from_now, end_date: 5.days.from_now) }
  let(:ticket)        { create(:ticket, event: event) }
  let(:order)         { create(:order) }
  let!(:attendee)     { create(:attendee, event: event, order: order, ticket: ticket, first_name: 'Ion', last_name: 'Popescu') }
  let(:slot_date)     { 3.days.from_now.to_date }
  let!(:slot)         { create(:ticket_meal_slot, ticket: ticket, occurs_on: slot_date, meal_type: 'lunch', sort: 1) }

  def auth_header(user)
    { 'Authorization' => "Bearer #{JwtService.encode(user.id)}", 'Content-Type' => 'application/json' }
  end

  def post_stamp(qr_code: attendee.qr_code, meal_type: 'lunch', occurs_on: slot_date.to_s, user: admin)
    post '/api/v1/scan/meal_stamps',
         params: { qr_code: qr_code, meal_type: meal_type, occurs_on: occurs_on }.to_json,
         headers: auth_header(user)
  end

  it 'returns 401 without a token' do
    post '/api/v1/scan/meal_stamps',
         params: { qr_code: attendee.qr_code, meal_type: 'lunch', occurs_on: slot_date.to_s }.to_json,
         headers: { 'Content-Type' => 'application/json' }
    expect(response).to have_http_status(:unauthorized)
  end

  it 'returns 403 for attendee role' do
    post_stamp(user: attendee_user)
    expect(response).to have_http_status(:forbidden)
  end

  it 'returns 422 when qr_code is missing' do
    post '/api/v1/scan/meal_stamps',
         params: { meal_type: 'lunch', occurs_on: slot_date.to_s }.to_json,
         headers: auth_header(admin)
    expect(response).to have_http_status(:unprocessable_content)
  end

  it 'returns 404 for an unknown QR code' do
    post_stamp(qr_code: 'CT-2026-XXXXXX-99999')
    expect(response).to have_http_status(:not_found)
  end

  it 'returns 422 when the attendee is not entitled to that meal' do
    post_stamp(meal_type: 'breakfast')
    expect(response).to have_http_status(:unprocessable_content)
    expect(json['error']).to eq('Not entitled')
  end

  context 'first stamp' do
    it 'returns 200 with already_stamped: false and total_stamps: 1' do
      post_stamp
      expect(response).to have_http_status(:ok)
      expect(json['already_stamped']).to be(false)
      expect(json['total_stamps']).to eq(1)
    end

    it 'creates a MealStamp record' do
      expect { post_stamp }.to change(MealStamp, :count).by(1)
    end

    it 'returns stamp with stamped_at and stamped_by' do
      post_stamp
      expect(json['stamp']['stamped_at']).to be_present
      expect(json['stamp']['stamped_by']).to eq('Ana Ionescu')
    end

    it 'returns attendee first_name and last_name' do
      post_stamp
      expect(json['attendee']).to include('first_name' => 'Ion', 'last_name' => 'Popescu')
    end
  end

  context 'second stamp (seconds)' do
    before { create(:meal_stamp, attendee: attendee, ticket_meal_slot: slot, stamped_by_user_id: admin.id) }

    it 'returns 200 with already_stamped: true and total_stamps: 2' do
      post_stamp
      expect(response).to have_http_status(:ok)
      expect(json['already_stamped']).to be(true)
      expect(json['total_stamps']).to eq(2)
    end

    it 'creates another MealStamp record' do
      expect { post_stamp }.to change(MealStamp, :count).by(1)
    end
  end
end
