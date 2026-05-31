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
      ticket = create(:ticket, event: event, price: 150, food_included: true)
      create(:tickets_translation, tickets_id: ticket.id, languages_code: 'ro-RO', name: 'Adult',
                                   description: 'Includes all meals')
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

      it 'returns upcoming bookings ordered by created_at DESC (newest first)' do
        first_booking  = create_booking(user: user, start_date: 30.days.from_now, end_date: 33.days.from_now)
        second_booking = create_booking(user: user, start_date: 10.days.from_now, end_date: 13.days.from_now)

        get '/api/v1/auth/me/bookings/upcoming', headers: auth_headers

        refs = json.map { |b| b['order_reference'] }
        expect(refs).to eq([second_booking[:order].order_reference, first_booking[:order].order_reference])
      end

      it 'includes the order_reference' do
        booking = create_booking(user: user, start_date: 10.days.from_now, end_date: 13.days.from_now)

        get '/api/v1/auth/me/bookings/upcoming', headers: auth_headers

        expect(json.first['order_reference']).to eq(booking[:order].order_reference)
      end

      it 'includes total_price as the sum of ticket prices' do
        create_booking(user: user, start_date: 10.days.from_now, end_date: 13.days.from_now,
                       with_ticket: true)

        get '/api/v1/auth/me/bookings/upcoming', headers: auth_headers

        expect(json.first['total_price']).to eq('150.0')
      end

      it 'includes all three payment statuses' do
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

      it 'returns event name in the user language' do
        user.update!(language: 'en-US')
        event = create(:event, start_date: 10.days.from_now, end_date: 13.days.from_now)
        create(:events_translation, event: event, languages_code: 'en-US', name: 'Test Conference')
        create(:events_translation, event: event, languages_code: 'ro-RO', name: 'Conferința Test')
        order = create(:order)
        create(:attendee, event: event, order: order, user: user)

        get '/api/v1/auth/me/bookings/upcoming', headers: auth_headers

        expect(json.first['event']['name']).to eq('Test Conference')
      end

      it 'falls back to ro-RO event name when user language has no translation' do
        user.update!(language: 'en-US')
        event = create(:event, start_date: 10.days.from_now, end_date: 13.days.from_now)
        create(:events_translation, event: event, languages_code: 'ro-RO', name: 'Conferința Test')
        order = create(:order)
        create(:attendee, event: event, order: order, user: user)

        get '/api/v1/auth/me/bookings/upcoming', headers: auth_headers

        expect(json.first['event']['name']).to eq('Conferința Test')
      end

      it 'includes attendee fields with ticket details' do # rubocop:disable RSpec/MultipleExpectations
        booking = create_booking(user: user, start_date: 10.days.from_now,
                                 end_date: 13.days.from_now, with_ticket: true)

        get '/api/v1/auth/me/bookings/upcoming', headers: auth_headers

        a = json.first['attendees'].first
        expect(a['first_name']).to eq(booking[:attendee].first_name)
        expect(a['last_name']).to eq(booking[:attendee].last_name)
        expect(a['payment_status']).to eq('paid')
        expect(a['ticket_name']).to eq('Adult')
        expect(a['ticket_description']).to eq('Includes all meals')
        expect(a['ticket_price']).to eq('150.0')
        expect(a['food_included']).to be(true)
        expect(a['dietary_preference']).to eq('no_preference')
      end

      it 'only returns the current user attendees when user did not create the order' do
        other_user = create(:user, email: 'other@example.com')
        event = create(:event, start_date: 10.days.from_now, end_date: 13.days.from_now)
        order = create(:order)
        create(:attendee, event: event, order: order, user: user,       first_name: 'Ion')
        create(:attendee, event: event, order: order, user: other_user, first_name: 'Maria')

        get '/api/v1/auth/me/bookings/upcoming', headers: auth_headers

        expect(json.first['attendees'].length).to eq(1)
        expect(json.first['attendees'].first['first_name']).to eq('Ion')
      end

      it 'returns all attendees when user created the order' do
        other_user = create(:user, email: 'other@example.com')
        event = create(:event, start_date: 10.days.from_now, end_date: 13.days.from_now)
        create(:events_translation, event: event, languages_code: 'ro-RO', name: 'Conferința Test')
        order = create(:order, user: user)
        create(:attendee, event: event, order: order, user: user,       first_name: 'Ion')
        create(:attendee, event: event, order: order, user: other_user, first_name: 'Maria')

        get '/api/v1/auth/me/bookings/upcoming', headers: auth_headers

        names = json.first['attendees'].pluck('first_name')
        expect(names).to contain_exactly('Ion', 'Maria')
      end

      it 'includes orders the user created even if no attendee is linked to them' do
        event = create(:event, start_date: 10.days.from_now, end_date: 13.days.from_now)
        create(:events_translation, event: event, languages_code: 'ro-RO', name: 'Conferința Test')
        order = create(:order, user: user)
        create(:attendee, event: event, order: order, user: nil, first_name: 'Guest')

        get '/api/v1/auth/me/bookings/upcoming', headers: auth_headers

        expect(json.first['order_reference']).to eq(order.order_reference)
        expect(json.first['attendees'].first['first_name']).to eq('Guest')
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

      it 'returns past bookings ordered by created_at DESC (newest first)' do
        first_booking  = create_booking(user: user, start_date: 30.days.ago, end_date: 27.days.ago)
        second_booking = create_booking(user: user, start_date: 10.days.ago, end_date: 7.days.ago)

        get '/api/v1/auth/me/bookings/past', headers: auth_headers

        refs = json.map { |b| b['order_reference'] }
        expect(refs).to eq([second_booking[:order].order_reference, first_booking[:order].order_reference])
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

  # ── POST /api/v1/auth/me/bookings/check ──────────────────────────────────────

  describe 'POST /api/v1/auth/me/bookings/check' do
    let(:event_a) do
      create(:event, slug: 'conf-2026', start_date: 10.days.from_now, end_date: 13.days.from_now)
    end
    let(:event_b) do
      create(:event, slug: 'tabara-2026', start_date: 20.days.from_now, end_date: 23.days.from_now)
    end

    def post_check(slugs)
      post '/api/v1/auth/me/bookings/check',
           params: { slugs: slugs }.to_json,
           headers: auth_headers
    end

    context 'with a paid booking' do
      before do
        order = create(:order)
        create(:attendee, event: event_a, order: order, user: user, payment_status: :paid)
      end

      it 'returns has_booking true with the order_reference' do
        post_check(['conf-2026'])
        expect(response).to have_http_status(:ok)
        expect(json['conf-2026']['has_booking']).to be true
        expect(json['conf-2026']['order_reference']).to match(/\ACT-\d{4}-\d{5}\z/)
      end
    end

    context 'with a payment_pending booking' do
      before do
        order = create(:order)
        create(:attendee, event: event_a, order: order, user: user, payment_status: :payment_pending)
      end

      it 'returns has_booking true' do
        post_check(['conf-2026'])
        expect(json['conf-2026']['has_booking']).to be true
      end
    end

    context 'with a refunded booking' do
      before do
        order = create(:order)
        create(:attendee, event: event_a, order: order, user: user, payment_status: :refunded)
      end

      it 'returns has_booking false' do
        post_check(['conf-2026'])
        expect(json['conf-2026']['has_booking']).to be false
        expect(json['conf-2026']['order_reference']).to be_nil
      end
    end

    context 'with no booking for the event' do
      it 'returns has_booking false' do
        post_check(['conf-2026'])
        expect(json['conf-2026']['has_booking']).to be false
        expect(json['conf-2026']['order_reference']).to be_nil
      end
    end

    context 'with an unknown slug' do
      it 'returns has_booking false for unknown slugs' do
        post_check(['does-not-exist'])
        expect(json['does-not-exist']['has_booking']).to be false
        expect(json['does-not-exist']['order_reference']).to be_nil
      end
    end

    context 'with multiple slugs' do
      before do
        order = create(:order)
        create(:attendee, event: event_a, order: order, user: user, payment_status: :paid)
      end

      it 'returns correct result for each slug in one call' do
        post_check(%w[conf-2026 tabara-2026])
        expect(json['conf-2026']['has_booking']).to be true
        expect(json['tabara-2026']['has_booking']).to be false
      end
    end

    context 'with missing slugs param' do
      it 'returns 422' do
        post '/api/v1/auth/me/bookings/check',
             params: {}.to_json,
             headers: auth_headers
        expect(response).to have_http_status(:unprocessable_entity)
        expect(json['error']).to eq(I18n.t('auth.errors.slugs_required'))
      end
    end

    context 'with no JWT' do
      it 'returns 401' do
        post '/api/v1/auth/me/bookings/check',
             params: { slugs: ['conf-2026'] }.to_json,
             headers: { 'Content-Type' => 'application/json' }
        expect(response).to have_http_status(:unauthorized)
      end
    end
  end

  describe 'DELETE /api/v1/auth/me/bookings/:order_reference' do
    let(:event) { create(:event, start_date: 10.days.from_now, end_date: 13.days.from_now) }
    let!(:order) { create(:order) }
    let!(:attendee) do
      create(:attendee, event: event, order: order, user: user, payment_status: :payment_pending)
    end

    it 'returns 401 without a token' do
      delete "/api/v1/auth/me/bookings/#{order.order_reference}"
      expect(response).to have_http_status(:unauthorized)
    end

    it 'returns 404 for unknown order reference' do
      delete '/api/v1/auth/me/bookings/CT-2026-99999', headers: auth_headers
      expect(response).to have_http_status(:not_found)
    end

    it 'returns 404 when the user has no attendees in the order' do
      other_order = create(:order)
      other_user = create(:user, first_name: 'Other', email: 'other@example.com')
      create(:attendee, event: event, order: other_order, user: other_user)
      delete "/api/v1/auth/me/bookings/#{other_order.order_reference}", headers: auth_headers
      expect(response).to have_http_status(:not_found)
    end

    it 'returns 422 when all user attendees are already paid' do
      attendee.update!(payment_status: :paid)
      delete "/api/v1/auth/me/bookings/#{order.order_reference}", headers: auth_headers
      expect(response).to have_http_status(:unprocessable_content)
      expect(json['error']).to eq(I18n.t('bookings.errors.nothing_to_cancel'))
    end

    it 'returns 422 when all user attendees are already cancelled' do
      attendee.update!(payment_status: :attendee_cancelled)
      delete "/api/v1/auth/me/bookings/#{order.order_reference}", headers: auth_headers
      expect(response).to have_http_status(:unprocessable_content)
    end

    it 'cancels all payment_pending attendees and returns the updated booking' do
      delete "/api/v1/auth/me/bookings/#{order.order_reference}", headers: auth_headers
      expect(response).to have_http_status(:ok)
      expect(attendee.reload.payment_status).to eq('attendee_cancelled')
      expect(json['order_reference']).to eq(order.order_reference)
      expect(json['payment_status']).to eq('attendee_cancelled')
    end

    it 'does not cancel attendees belonging to other users in the same order' do
      other_user = create(:user, first_name: 'Other', email: 'other2@example.com')
      other_attendee = create(:attendee, event: event, order: order, user: other_user,
                                         payment_status: :payment_pending)
      delete "/api/v1/auth/me/bookings/#{order.order_reference}", headers: auth_headers
      expect(other_attendee.reload.payment_status).to eq('payment_pending')
    end

    it 'does not cancel paid attendees belonging to the current user' do
      paid_attendee = create(:attendee, event: event, order: order, user: user,
                                        payment_status: :paid)
      delete "/api/v1/auth/me/bookings/#{order.order_reference}", headers: auth_headers
      expect(paid_attendee.reload.payment_status).to eq('paid')
    end
  end

  describe 'DELETE /api/v1/auth/me/bookings/:order_reference/attendees/:id' do
    let(:event) { create(:event, start_date: 10.days.from_now, end_date: 13.days.from_now) }
    let!(:order) { create(:order) }
    let!(:attendee) do
      create(:attendee, event: event, order: order, user: user, payment_status: :payment_pending)
    end
    let!(:other_attendee) do
      create(:attendee, event: event, order: order, user: user, payment_status: :payment_pending)
    end

    it 'returns 401 without a token' do
      delete "/api/v1/auth/me/bookings/#{order.order_reference}/attendees/#{attendee.id}"
      expect(response).to have_http_status(:unauthorized)
    end

    it 'returns 404 for unknown order reference' do
      delete "/api/v1/auth/me/bookings/CT-2026-99999/attendees/#{attendee.id}", headers: auth_headers
      expect(response).to have_http_status(:not_found)
    end

    it 'returns 404 when attendee belongs to another user' do
      other_user = create(:user, first_name: 'Other', email: 'other3@example.com')
      other_attendee_record = create(:attendee, event: event, order: order, user: other_user)
      delete "/api/v1/auth/me/bookings/#{order.order_reference}/attendees/#{other_attendee_record.id}",
             headers: auth_headers
      expect(response).to have_http_status(:not_found)
    end

    it 'returns 422 when attendee is already paid' do
      attendee.update!(payment_status: :paid)
      delete "/api/v1/auth/me/bookings/#{order.order_reference}/attendees/#{attendee.id}",
             headers: auth_headers
      expect(response).to have_http_status(:unprocessable_content)
      expect(json['error']).to eq(I18n.t('bookings.errors.cannot_cancel'))
    end

    it 'returns 422 when attendee is already cancelled' do
      attendee.update!(payment_status: :attendee_cancelled)
      delete "/api/v1/auth/me/bookings/#{order.order_reference}/attendees/#{attendee.id}",
             headers: auth_headers
      expect(response).to have_http_status(:unprocessable_content)
    end

    it 'cancels the specific attendee and returns the updated booking' do
      delete "/api/v1/auth/me/bookings/#{order.order_reference}/attendees/#{attendee.id}",
             headers: auth_headers
      expect(response).to have_http_status(:ok)
      expect(attendee.reload.payment_status).to eq('attendee_cancelled')
      expect(json['order_reference']).to eq(order.order_reference)
    end

    it 'does not affect other attendees in the same order' do
      delete "/api/v1/auth/me/bookings/#{order.order_reference}/attendees/#{attendee.id}",
             headers: auth_headers
      expect(other_attendee.reload.payment_status).to eq('payment_pending')
    end
  end
end
