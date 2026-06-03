# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'GET /api/v1/scan/meal_slots' do
  let(:admin)         { create(:user, role: 'admin') }
  let(:attendee_user) { create(:user, role: 'attendee') }
  let(:event)         { create(:event, slug: 'tabara-2026', start_date: 7.days.from_now, end_date: 10.days.from_now) }
  let(:ticket)        { create(:ticket, event: event) }
  let(:date)          { 8.days.from_now.to_date }

  def auth_header(user)
    { 'Authorization' => "Bearer #{JwtService.encode(user.id)}", 'Content-Type' => 'application/json' }
  end

  def get_slots(event_slug: event.slug, date: self.date, user: admin)
    get '/api/v1/scan/meal_slots', params: { event_slug: event_slug, date: date.to_s },
                                   headers: auth_header(user)
  end

  it 'returns 401 without a token' do
    get '/api/v1/scan/meal_slots', params: { event_slug: event.slug, date: date.to_s }
    expect(response).to have_http_status(:unauthorized)
  end

  it 'returns 403 for attendee role' do
    get_slots(user: attendee_user)
    expect(response).to have_http_status(:forbidden)
  end

  it 'returns 404 for unknown event_slug' do
    get_slots(event_slug: 'unknown-event')
    expect(response).to have_http_status(:not_found)
  end

  it 'returns 422 when date param is missing' do
    get '/api/v1/scan/meal_slots', params: { event_slug: event.slug }, headers: auth_header(admin)
    expect(response).to have_http_status(:unprocessable_content)
  end

  context 'with meal slots on the requested date' do
    let!(:lunch_slot)  { create(:ticket_meal_slot, ticket: ticket, occurs_on: date, meal_type: 'lunch',  sort: 1) }
    let!(:dinner_slot) { create(:ticket_meal_slot, ticket: ticket, occurs_on: date, meal_type: 'dinner', sort: 2) }
    let!(:other_date)  { create(:ticket_meal_slot, ticket: ticket, occurs_on: date + 1, meal_type: 'lunch', sort: 1) }

    it 'returns 200 with slots for that date only' do
      get_slots
      expect(response).to have_http_status(:ok)
      expect(json.length).to eq(2)
      expect(json.pluck('meal_type')).to contain_exactly('lunch', 'dinner')
    end

    it 'returns id, meal_type, occurs_on, and sort for each slot' do
      get_slots
      slot = json.find { |s| s['meal_type'] == 'lunch' }
      expect(slot.keys).to contain_exactly('id', 'meal_type', 'occurs_on', 'sort')
      expect(slot['id']).to eq(lunch_slot.id)
    end
  end

  it 'returns empty array when no slots on that date' do
    get_slots
    expect(response).to have_http_status(:ok)
    expect(json).to eq([])
  end

  context 'deduplication across tickets' do
    let(:ticket2)  { create(:ticket, event: event) }
    let!(:slot_t1) { create(:ticket_meal_slot, ticket: ticket,  occurs_on: date, meal_type: 'lunch', sort: 1) }
    let!(:slot_t2) { create(:ticket_meal_slot, ticket: ticket2, occurs_on: date, meal_type: 'lunch', sort: 1) }

    it 'returns only one entry per meal_type when multiple tickets share it' do
      get_slots
      expect(json.select { |s| s['meal_type'] == 'lunch' }.length).to eq(1)
    end
  end

  context 'slots from a different event' do
    let(:other_event)  { create(:event, slug: 'other-event', start_date: 7.days.from_now, end_date: 10.days.from_now) }
    let(:other_ticket) { create(:ticket, event: other_event) }
    let!(:other_slot)  { create(:ticket_meal_slot, ticket: other_ticket, occurs_on: date, meal_type: 'lunch', sort: 1) }

    it 'does not include slots from other events' do
      get_slots
      expect(json).to eq([])
    end
  end
end
