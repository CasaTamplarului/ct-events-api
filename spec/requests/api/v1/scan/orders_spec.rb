# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Scan Orders API' do
  let(:admin)          { create(:user, role: 'admin') }
  let(:volunteer)      { create(:user, role: 'volunteer') }
  let(:attendee_user)  { create(:user, role: 'attendee') }
  let(:event)          { create(:event) }
  let(:order)          { create(:order, payment_status: :paid) }
  let!(:attendee1) do
    create(:attendee, event: event, order: order,
                      first_name: 'Ion', last_name: 'Popescu', email_address: 'ion@example.com')
  end
  let!(:attendee2) do
    create(:attendee, event: event, order: order,
                      first_name: 'Maria', last_name: 'Ionescu', email_address: 'maria@example.com')
  end

  def auth_header(user)
    { 'Authorization' => "Bearer #{JwtService.encode(user.id)}", 'Content-Type' => 'application/json' }
  end

  describe 'GET /api/v1/scan/orders/:order_reference' do
    def get_order(ref, user: admin)
      get "/api/v1/scan/orders/#{ref}", headers: auth_header(user)
    end

    it 'returns 401 without a token' do
      get "/api/v1/scan/orders/#{order.order_reference}"
      expect(response).to have_http_status(:unauthorized)
    end

    it 'returns 403 for attendee role' do
      get_order(order.order_reference, user: attendee_user)
      expect(response).to have_http_status(:forbidden)
    end

    it 'returns 200 and order data for admin' do
      get_order(order.order_reference)
      expect(response).to have_http_status(:ok)
      expect(json['order_reference']).to eq(order.order_reference)
      expect(json['payment_status']).to eq('paid')
    end

    it 'returns 200 for volunteer role' do
      get_order(order.order_reference, user: volunteer)
      expect(response).to have_http_status(:ok)
    end

    it 'returns 404 for unknown order reference' do
      get_order('CT-2026-99999')
      expect(response).to have_http_status(:not_found)
    end

    it 'returns all attendees in the order' do
      get_order(order.order_reference)
      emails = json['attendees'].pluck('email_address')
      expect(emails).to contain_exactly('ion@example.com', 'maria@example.com')
    end

    it 'includes required fields on each attendee' do
      get_order(order.order_reference)
      a = json['attendees'].first
      expect(a.keys).to include('id', 'first_name', 'last_name', 'email_address',
                                'ticket_name', 'checked_in', 'checked_in_at', 'checked_in_by')
    end

    it 'returns checked_in: false and nil timestamps for unchecked attendees' do
      get_order(order.order_reference)
      a = json['attendees'].first
      expect(a['checked_in']).to be false
      expect(a['checked_in_at']).to be_nil
      expect(a['checked_in_by']).to be_nil
    end

    context 'when an attendee is checked in' do
      before do
        attendee1.update!(
          checked_in: true,
          checked_in_at: Time.zone.parse('2026-06-01 10:00:00'),
          checked_in_by_user_id: admin.id
        )
      end

      it 'returns checked_in: true with timestamp and checker name' do
        get_order(order.order_reference)
        a = json['attendees'].find { |x| x['id'] == attendee1.id }
        expect(a['checked_in']).to be true
        expect(a['checked_in_at']).to be_present
        expect(a['checked_in_by']).to eq("#{admin.first_name} #{admin.last_name}".strip)
      end
    end

    context 'when an attendee has a ticket with a ro-RO translation' do
      before do
        Language.find_or_create_by!(code: 'ro-RO') { |l| l.name = 'Romanian' }
        ticket = create(:ticket, event: event, price: 100)
        create(:tickets_translation, tickets_id: ticket.id, languages_code: 'ro-RO', name: 'General')
        attendee1.update!(ticket: ticket)
      end

      it 'includes the ticket name from the ro-RO translation' do
        get_order(order.order_reference)
        a = json['attendees'].find { |x| x['id'] == attendee1.id }
        expect(a['ticket_name']).to eq('General')
      end
    end

    context 'when an attendee has no ticket' do
      it 'returns ticket_name: nil' do
        get_order(order.order_reference)
        a = json['attendees'].find { |x| x['id'] == attendee1.id }
        expect(a['ticket_name']).to be_nil
      end
    end
  end
end
