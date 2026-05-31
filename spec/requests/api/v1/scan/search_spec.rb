# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'GET /api/v1/scan/search' do
  let(:admin)         { create(:user, role: 'admin') }
  let(:volunteer)     { create(:user, role: 'volunteer') }
  let(:attendee_user) { create(:user, role: 'attendee') }
  let(:event)         { create(:event, slug: 'conferinta-2026') }
  let(:other_event)   { create(:event, slug: 'tabara-2026') }
  let(:first_order)   { create(:order) }
  let(:second_order)  { create(:order) }

  let!(:first_attendee) do
    create(:attendee, event: event, order: first_order,
                      first_name: 'Ion', last_name: 'Popescu',
                      email_address: 'ion@example.com', phone_number: '0722111222',
                      payment_status: :paid)
  end
  let!(:second_attendee) do
    create(:attendee, event: event, order: second_order,
                      first_name: 'Maria', last_name: 'Ionescu',
                      email_address: 'maria@example.com', phone_number: '0733444555',
                      payment_status: :payment_pending)
  end
  let!(:other_event_attendee) do
    create(:attendee, event: other_event, order: first_order,
                      first_name: 'Vasile', last_name: 'Popa',
                      email_address: 'vasile@example.com', phone_number: '0744666777')
  end

  def auth_header(user)
    { 'Authorization' => "Bearer #{JwtService.encode(user.id)}", 'Content-Type' => 'application/json' }
  end

  def search(params, user: admin)
    get '/api/v1/scan/search', params: params, headers: auth_header(user)
  end

  describe 'authentication and authorisation' do
    it 'returns 401 without a token' do
      get '/api/v1/scan/search', params: { type: 'order_ref', query: 'CT' }
      expect(response).to have_http_status(:unauthorized)
    end

    it 'returns 403 for attendee role' do
      search({ type: 'order_ref', query: 'CT' }, user: attendee_user)
      expect(response).to have_http_status(:forbidden)
    end

    it 'returns 200 for volunteer role' do
      search({ type: 'order_ref', query: 'CT' }, user: volunteer)
      expect(response).to have_http_status(:ok)
    end
  end

  describe 'param validation' do
    it 'returns 422 when type is missing' do
      search({ query: 'Ion', event_slug: 'conferinta-2026' })
      expect(response).to have_http_status(:unprocessable_content)
      expect(json['error']).to eq('type and query are required')
    end

    it 'returns 422 when query is missing' do
      search({ type: 'name', event_slug: 'conferinta-2026' })
      expect(response).to have_http_status(:unprocessable_content)
      expect(json['error']).to eq('type and query are required')
    end

    it 'returns 422 for an invalid type' do
      search({ type: 'fax', query: 'Ion' })
      expect(response).to have_http_status(:unprocessable_content)
      expect(json['error']).to eq('Invalid type')
    end

    it 'returns 422 when query is shorter than 2 characters' do
      search({ type: 'order_ref', query: 'C' })
      expect(response).to have_http_status(:unprocessable_content)
      expect(json['error']).to eq('query must be at least 2 characters')
    end

    it 'returns 422 when event_slug is missing for name type' do
      search({ type: 'name', query: 'Ion' })
      expect(response).to have_http_status(:unprocessable_content)
      expect(json['error']).to eq('event_slug is required for this search type')
    end

    it 'returns 422 when event_slug is missing for email type' do
      search({ type: 'email', query: 'ion@' })
      expect(response).to have_http_status(:unprocessable_content)
      expect(json['error']).to eq('event_slug is required for this search type')
    end

    it 'returns 422 when event_slug is missing for phone type' do
      search({ type: 'phone', query: '072' })
      expect(response).to have_http_status(:unprocessable_content)
      expect(json['error']).to eq('event_slug is required for this search type')
    end

    it 'returns 404 when event_slug does not match any event' do
      search({ type: 'name', query: 'Ion', event_slug: 'no-such-event' })
      expect(response).to have_http_status(:not_found)
    end
  end

  describe 'order_ref search' do
    it 'returns matching orders for a partial ref' do
      search({ type: 'order_ref', query: first_order.order_reference[0..9] })
      expect(response).to have_http_status(:ok)
      expect(json.pluck('order_reference')).to include(first_order.order_reference)
    end

    it 'returns an empty array when no orders match' do
      search({ type: 'order_ref', query: 'CT-9999' })
      expect(response).to have_http_status(:ok)
      expect(json).to eq([])
    end

    it 'returns orders with attendees in the expected shape' do
      search({ type: 'order_ref', query: first_order.order_reference })
      order_json = json.find { |o| o['order_reference'] == first_order.order_reference }
      expect(order_json.keys).to include('order_reference', 'payment_status', 'attendees')
      expect(order_json['attendees'].first.keys).to include(
        'id', 'first_name', 'last_name', 'email_address',
        'ticket_name', 'payment_status', 'checked_in', 'checked_in_at', 'checked_in_by'
      )
    end
  end

  describe 'name search' do
    it 'finds by partial first name' do
      search({ type: 'name', query: 'Io', event_slug: 'conferinta-2026' })
      expect(response).to have_http_status(:ok)
      expect(json.pluck('order_reference')).to include(first_order.order_reference)
    end

    it 'finds by partial last name' do
      search({ type: 'name', query: 'Popes', event_slug: 'conferinta-2026' })
      expect(json.pluck('order_reference')).to include(first_order.order_reference)
    end

    it 'finds by full name' do
      search({ type: 'name', query: 'Ion Popescu', event_slug: 'conferinta-2026' })
      expect(json.pluck('order_reference')).to include(first_order.order_reference)
    end

    it 'does not return orders from other events' do
      search({ type: 'name', query: 'Vasile', event_slug: 'conferinta-2026' })
      expect(json).to eq([])
    end

    it 'returns empty array when no name matches' do
      search({ type: 'name', query: 'Gheorghe', event_slug: 'conferinta-2026' })
      expect(json).to eq([])
    end
  end

  describe 'email search' do
    it 'finds by partial email' do
      search({ type: 'email', query: 'ion@', event_slug: 'conferinta-2026' })
      expect(response).to have_http_status(:ok)
      expect(json.pluck('order_reference')).to include(first_order.order_reference)
    end

    it 'does not return orders where the matching attendee is in another event' do
      search({ type: 'email', query: 'vasile@', event_slug: 'conferinta-2026' })
      expect(json).to eq([])
    end
  end

  describe 'phone search' do
    it 'finds by partial phone number' do
      search({ type: 'phone', query: '07221', event_slug: 'conferinta-2026' })
      expect(response).to have_http_status(:ok)
      expect(json.pluck('order_reference')).to include(first_order.order_reference)
    end

    it 'does not return orders where the matching attendee is in another event' do
      search({ type: 'phone', query: '07446', event_slug: 'conferinta-2026' })
      expect(json).to eq([])
    end
  end

  describe 'result cap' do
    it 'returns at most 20 results' do
      21.times do |i|
        o = create(:order)
        create(:attendee, event: event, order: o,
                          first_name: 'TestUser', last_name: "Num#{i}",
                          email_address: "testuser#{i}@example.com",
                          phone_number: "0700#{i.to_s.rjust(6, '0')}")
      end
      search({ type: 'name', query: 'TestUser', event_slug: 'conferinta-2026' })
      expect(response).to have_http_status(:ok)
      expect(json.length).to eq(20)
    end
  end
end
