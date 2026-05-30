# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'GET /api/v1/auth/me/bookings' do
  before do
    Language.find_or_create_by!(code: 'ro-RO') { |l| l.name = 'Romanian' }
    Language.find_or_create_by!(code: 'en-US') { |l| l.name = 'English' }
  end

  let(:user)         { create(:user, email: 'ion@example.com', language: 'ro-RO') }
  let(:token)        { JwtService.encode(user.id) }
  let(:auth_headers) { { 'Content-Type' => 'application/json', 'Authorization' => "Bearer #{token}" } }

  # Creates a complete booking: event + order + attendee linked to the given user.
  def create_booking(user:, start_date:, end_date:, payment_status: :paid, with_ticket: false)
    event = create(:event, start_date: start_date, end_date: end_date)
    create(:events_translation, event: event, languages_code: 'ro-RO', name: 'Conferința Test')
    order = create(:order)
    ticket = nil
    if with_ticket
      ticket = create(:ticket, event: event)
      create(:tickets_translation, tickets_id: ticket.id, languages_code: 'ro-RO', name: 'Adult')
    end
    attendee = create(:attendee, event: event, order: order, user: user,
                                 payment_status: payment_status, ticket: ticket)
    { event: event, order: order, attendee: attendee }
  end

  # ── GET /api/v1/auth/me/bookings/upcoming ────────────────────────────────────

  describe 'GET /api/v1/auth/me/bookings/upcoming' do
    context 'with a valid JWT' do
      it 'returns 200' do
        get '/api/v1/auth/me/bookings/upcoming', headers: auth_headers
        expect(response).to have_http_status(:ok)
      end

      it 'returns empty array when user has no upcoming bookings' do
        get '/api/v1/auth/me/bookings/upcoming', headers: auth_headers
        expect(json).to eq([])
      end

      it 'returns upcoming bookings ordered by start_date ASC' do
        create_booking(user: user, start_date: 30.days.from_now, end_date: 33.days.from_now)
        create_booking(user: user, start_date: 10.days.from_now, end_date: 13.days.from_now)

        get '/api/v1/auth/me/bookings/upcoming', headers: auth_headers

        start_dates = json.map { |b| b['event']['start_date'] }
        expect(start_dates).to eq(start_dates.sort)
      end

      it 'includes the order_reference' do
        booking = create_booking(user: user, start_date: 10.days.from_now, end_date: 13.days.from_now)

        get '/api/v1/auth/me/bookings/upcoming', headers: auth_headers

        expect(json.first['order_reference']).to eq(booking[:order].order_reference)
      end

      it 'includes all three payment statuses' do # rubocop:disable RSpec/ExampleLength
        create_booking(user: user, start_date: 10.days.from_now, end_date: 13.days.from_now,
                       payment_status: :paid)
        create_booking(user: user, start_date: 20.days.from_now, end_date: 23.days.from_now,
                       payment_status: :payment_pending)
        create_booking(user: user, start_date: 30.days.from_now, end_date: 33.days.from_now,
                       payment_status: :refunded)

        get '/api/v1/auth/me/bookings/upcoming', headers: auth_headers

        statuses = json.pluck('payment_status')
        expect(statuses).to contain_exactly('paid', 'payment_pending', 'refunded')
      end

      it 'includes all expected event fields' do # rubocop:disable RSpec/ExampleLength,RSpec/MultipleExpectations
        event = create(:event,
                       start_date: 10.days.from_now,
                       end_date: 13.days.from_now,
                       slug: 'test-event',
                       location_name: 'Casa Tâmplarului',
                       address: 'Str. Test 1')
        create(:events_translation, event: event, languages_code: 'ro-RO', name: 'Conferința Test')
        order = create(:order)
        create(:attendee, event: event, order: order, user: user)

        get '/api/v1/auth/me/bookings/upcoming', headers: auth_headers

        e = json.first['event']
        expect(e['name']).to eq('Conferința Test')
        expect(e['slug']).to eq('test-event')
        expect(e['location_name']).to eq('Casa Tâmplarului')
        expect(e['address']).to eq('Str. Test 1')
        expect(e['start_date']).to be_present
        expect(e['end_date']).to be_present
      end

      it 'returns event name in the user language' do # rubocop:disable RSpec/ExampleLength
        user.update!(language: 'en-US')
        event = create(:event, start_date: 10.days.from_now, end_date: 13.days.from_now)
        create(:events_translation, event: event, languages_code: 'en-US', name: 'Test Conference')
        create(:events_translation, event: event, languages_code: 'ro-RO', name: 'Conferința Test')
        order = create(:order)
        create(:attendee, event: event, order: order, user: user)

        get '/api/v1/auth/me/bookings/upcoming', headers: auth_headers

        expect(json.first['event']['name']).to eq('Test Conference')
      end

      it 'falls back to ro-RO event name when user language has no translation' do # rubocop:disable RSpec/ExampleLength
        user.update!(language: 'en-US')
        event = create(:event, start_date: 10.days.from_now, end_date: 13.days.from_now)
        create(:events_translation, event: event, languages_code: 'ro-RO', name: 'Conferința Test')
        order = create(:order)
        create(:attendee, event: event, order: order, user: user)

        get '/api/v1/auth/me/bookings/upcoming', headers: auth_headers

        expect(json.first['event']['name']).to eq('Conferința Test')
      end

      it 'includes attendee fields with ticket_name' do # rubocop:disable RSpec/ExampleLength
        booking = create_booking(user: user, start_date: 10.days.from_now,
                                 end_date: 13.days.from_now, with_ticket: true)

        get '/api/v1/auth/me/bookings/upcoming', headers: auth_headers

        a = json.first['attendees'].first
        expect(a['first_name']).to eq(booking[:attendee].first_name)
        expect(a['last_name']).to eq(booking[:attendee].last_name)
        expect(a['ticket_name']).to eq('Adult')
        expect(a['dietary_preference']).to eq('no_preference')
      end

      it 'only returns the current user attendees, not other users on the same order' do # rubocop:disable RSpec/ExampleLength
        other_user = create(:user, email: 'other@example.com')
        event = create(:event, start_date: 10.days.from_now, end_date: 13.days.from_now)
        order = create(:order)
        create(:attendee, event: event, order: order, user: user,       first_name: 'Ion')
        create(:attendee, event: event, order: order, user: other_user, first_name: 'Maria')

        get '/api/v1/auth/me/bookings/upcoming', headers: auth_headers

        expect(json.first['attendees'].length).to eq(1)
        expect(json.first['attendees'].first['first_name']).to eq('Ion')
      end

      it 'does not return past bookings' do
        create_booking(user: user, start_date: 10.days.ago, end_date: 7.days.ago)

        get '/api/v1/auth/me/bookings/upcoming', headers: auth_headers

        expect(json).to eq([])
      end
    end

    context 'with no JWT' do
      it 'returns 401' do
        get '/api/v1/auth/me/bookings/upcoming',
            headers: { 'Content-Type' => 'application/json' }
        expect(response).to have_http_status(:unauthorized)
      end
    end
  end

  # ── GET /api/v1/auth/me/bookings/past ────────────────────────────────────────

  describe 'GET /api/v1/auth/me/bookings/past' do
    context 'with a valid JWT' do
      it 'returns empty array when user has no past bookings' do
        get '/api/v1/auth/me/bookings/past', headers: auth_headers
        expect(json).to eq([])
      end

      it 'returns past bookings ordered by start_date DESC' do
        create_booking(user: user, start_date: 30.days.ago, end_date: 27.days.ago)
        create_booking(user: user, start_date: 10.days.ago, end_date: 7.days.ago)

        get '/api/v1/auth/me/bookings/past', headers: auth_headers

        start_dates = json.map { |b| b['event']['start_date'] }
        expect(start_dates).to eq(start_dates.sort.reverse)
      end

      it 'does not return upcoming bookings' do
        create_booking(user: user, start_date: 10.days.from_now, end_date: 13.days.from_now)

        get '/api/v1/auth/me/bookings/past', headers: auth_headers

        expect(json).to eq([])
      end

      it 'returns 200 with booking data' do
        booking = create_booking(user: user, start_date: 10.days.ago, end_date: 7.days.ago)

        get '/api/v1/auth/me/bookings/past', headers: auth_headers

        expect(response).to have_http_status(:ok)
        expect(json.first['order_reference']).to eq(booking[:order].order_reference)
      end
    end

    context 'with no JWT' do
      it 'returns 401' do
        get '/api/v1/auth/me/bookings/past',
            headers: { 'Content-Type' => 'application/json' }
        expect(response).to have_http_status(:unauthorized)
      end
    end
  end
end
