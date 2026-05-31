# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'POST /api/v1/:lang/orders' do
  let(:language_code) { 'ro-RO' }
  let(:language) { Language.find_or_create_by!(code: language_code) { |l| l.name = 'Romanian' } }

  let(:event) { create(:event, status: :live, slug: 'tabara-impact-2026', max_number_of_people: 10) }
  let(:ticket) { create(:ticket, event: event, price: 350) }
  let(:ticket_translation) { create(:tickets_translation, tickets_id: ticket.id, languages_code: language_code, name: 'Standard') }
  let(:event_translation) { create(:events_translation, event: event, languages_code: language_code, name: 'Tabara Impact') }

  let(:valid_item) do
    {
      event_slug: 'tabara-impact-2026',
      ticket_name: 'Standard',
      attendee: {
        first_name: 'Ion',
        last_name: 'Popescu',
        email_address: 'ion@example.com',
        phone_number: '0722000000'
      }
    }
  end

  before do
    language
    ticket_translation
    event_translation
    stub_request(:post, 'https://api.sendgrid.com/v3/mail/send')
      .to_return(status: 202, body: '', headers: {})
  end

  def post_order(items)
    post "/api/v1/#{language_code}/orders",
         params: { items: items }.to_json,
         headers: { 'Content-Type' => 'application/json' }
  end

  describe 'success' do
    it 'returns 201 with a formatted order reference' do
      post_order([valid_item])

      expect(response).to have_http_status(:created)
      expect(json['order_reference']).to match(/\ACT-\d{4}-\d{5}\z/)
    end

    it 'creates one attendee per item' do
      post_order([valid_item])

      expect(Attendee.count).to eq(1)
    end

    it 'creates a single order for multiple items on the same event' do
      second_item = valid_item.deep_merge(attendee: { email_address: 'maria@example.com' })
      post_order([valid_item, second_item])

      expect(Order.count).to eq(1)
      expect(Attendee.count).to eq(2)
    end

    it 'links attendees to the order' do
      post_order([valid_item])

      expect(Attendee.last.order).to eq(Order.last)
    end

    it 'links attendees to the correct ticket' do
      post_order([valid_item])

      expect(Attendee.last.ticket).to eq(ticket)
    end
  end

  describe 'missing items' do
    it 'returns 400 when items param is absent' do
      post "/api/v1/#{language_code}/orders",
           params: {}.to_json,
           headers: { 'Content-Type' => 'application/json' }

      expect(response).to have_http_status(:bad_request)
      expect(json['error']).to be_present
    end

    it 'returns 400 when items is empty' do
      post_order([])

      expect(response).to have_http_status(:bad_request)
      expect(json['error']).to be_present
    end
  end

  describe 'unknown event slug' do
    it 'returns 400' do
      post_order([valid_item.merge(event_slug: 'unknown-event')])

      expect(response).to have_http_status(:bad_request)
      expect(json['error']).to be_present
    end
  end

  describe 'unknown ticket name' do
    it 'returns 400' do
      post_order([valid_item.merge(ticket_name: 'VIP')])

      expect(response).to have_http_status(:bad_request)
      expect(json['error']).to be_present
    end
  end

  describe 'sold out event' do
    let(:event) { create(:event, status: :live, slug: 'tabara-impact-2026', max_number_of_people: 1) }

    before { create(:attendee, event: event) }

    it 'returns 409' do
      post_order([valid_item])

      expect(response).to have_http_status(:conflict)
      expect(json['error']).to be_present
    end
  end

  describe 'duplicate registration' do
    before { create(:attendee, event: event, email_address: 'ion@example.com') }

    it 'returns 422 when same email is already registered for the event' do
      post_order([valid_item])

      expect(response).to have_http_status(:unprocessable_entity)
      expect(json['error']).to be_present
    end

    it 'allows re-registration when the existing attendee has cancelled' do
      Attendee.find_by(event: event, email_address: 'ion@example.com')
              .update!(payment_status: :attendee_cancelled)

      post_order([valid_item])

      expect(response).to have_http_status(:created)
    end
  end

  context 'when order is created successfully — email' do
    it 'sends a booking confirmation email' do
      post_order([valid_item])

      expect(WebMock).to have_requested(:post, 'https://api.sendgrid.com/v3/mail/send').once
    end

    it 'still creates the order if email fails' do
      stub_request(:post, 'https://api.sendgrid.com/v3/mail/send').to_raise(SocketError)
      expect { post_order([valid_item]) }.to change(Order, :count).by(1)
      expect(response).to have_http_status(:created)
    end
  end
end
