# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Scan Orders API' do
  let(:admin)          { create(:user, role: 'admin') }
  let(:volunteer)      { create(:user, role: 'volunteer') }
  let(:attendee_user)  { create(:user, role: 'attendee') }
  let(:event)          { create(:event) }
  let(:order)          { create(:order) }
  let!(:first_attendee) do
    create(:attendee, event: event, order: order,
                      first_name: 'Ion', last_name: 'Popescu',
                      email_address: 'ion@example.com', payment_status: :paid)
  end
  let!(:second_attendee) do
    create(:attendee, event: event, order: order,
                      first_name: 'Maria', last_name: 'Ionescu',
                      email_address: 'maria@example.com', payment_status: :paid)
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
                                'ticket_name', 'payment_status', 'checked_in', 'checked_in_at', 'checked_in_by')
    end

    it 'returns payment_status for each attendee' do
      get_order(order.order_reference)
      json['attendees'].each do |a|
        expect(a['payment_status']).to be_present
      end
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
        first_attendee.update!(
          checked_in: true,
          checked_in_at: Time.zone.parse('2026-06-01 10:00:00'),
          checked_in_by_user_id: admin.id
        )
      end

      it 'returns checked_in: true with timestamp and checker name' do
        get_order(order.order_reference)
        a = json['attendees'].find { |x| x['id'] == first_attendee.id }
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
        first_attendee.update!(ticket: ticket)
      end

      it 'includes the ticket name from the ro-RO translation' do
        get_order(order.order_reference)
        a = json['attendees'].find { |x| x['id'] == first_attendee.id }
        expect(a['ticket_name']).to eq('General')
      end
    end

    context 'when an attendee has no ticket' do
      it 'returns ticket_name: nil' do
        get_order(order.order_reference)
        a = json['attendees'].find { |x| x['id'] == first_attendee.id }
        expect(a['ticket_name']).to be_nil
      end
    end

    describe 'self-check-in prevention' do
      context 'when the current user is an attendee in the order' do
        before { create(:attendee, event: event, order: order, user: admin) }

        it 'still returns 200 for GET' do
          get_order(order.order_reference)
          expect(response).to have_http_status(:ok)
        end
      end
    end
  end

  describe 'PATCH /api/v1/scan/orders/:order_reference' do
    def patch_order(ref, body, user: admin)
      patch "/api/v1/scan/orders/#{ref}",
            params: body.to_json,
            headers: auth_header(user)
    end

    it 'returns 401 without a token' do
      patch "/api/v1/scan/orders/#{order.order_reference}",
            params: { attendees: [{ id: first_attendee.id, checked_in: true }] }.to_json,
            headers: { 'Content-Type' => 'application/json' }
      expect(response).to have_http_status(:unauthorized)
    end

    it 'returns 403 for attendee role' do
      patch_order(order.order_reference, { attendees: [{ id: first_attendee.id, checked_in: true }] },
                  user: attendee_user)
      expect(response).to have_http_status(:forbidden)
    end

    it 'returns 404 for unknown order reference' do
      patch_order('CT-2026-99999', { attendees: [{ id: 1, checked_in: true }] })
      expect(response).to have_http_status(:not_found)
    end

    it 'returns 422 when body has no updateable fields' do
      patch_order(order.order_reference, {})
      expect(response).to have_http_status(:unprocessable_content)
      expect(json['error']).to eq('Nothing to update')
    end

    it 'returns the same shape as GET on success' do
      patch_order(order.order_reference, { attendees: [{ id: first_attendee.id, checked_in: true }] })
      expect(json.keys).to include('order_reference', 'payment_status', 'attendees')
    end

    context 'when checking in attendees' do
      it 'checks in a single attendee and records who did it' do
        patch_order(order.order_reference, { attendees: [{ id: first_attendee.id, checked_in: true }] })
        expect(response).to have_http_status(:ok)
        first_attendee.reload
        expect(first_attendee.checked_in).to be true
        expect(first_attendee.checked_in_at).to be_present
        expect(first_attendee.checked_in_by_user_id).to eq(admin.id)
      end

      it 'checks in multiple attendees in one request' do
        patch_order(order.order_reference, {
                      attendees: [
                        { id: first_attendee.id, checked_in: true },
                        { id: second_attendee.id, checked_in: true }
                      ]
                    })
        expect(response).to have_http_status(:ok)
        expect(first_attendee.reload.checked_in).to be true
        expect(second_attendee.reload.checked_in).to be true
      end

      it 'unchecks in an attendee and clears the tracking fields' do
        first_attendee.update!(checked_in: true, checked_in_at: Time.current,
                               checked_in_by_user_id: admin.id)
        patch_order(order.order_reference, { attendees: [{ id: first_attendee.id, checked_in: false }] })
        expect(response).to have_http_status(:ok)
        first_attendee.reload
        expect(first_attendee.checked_in).to be false
        expect(first_attendee.checked_in_at).to be_nil
        expect(first_attendee.checked_in_by_user_id).to be_nil
      end

      it 'reflects check-in state in the response' do
        patch_order(order.order_reference, { attendees: [{ id: first_attendee.id, checked_in: true }] })
        a = json['attendees'].find { |x| x['id'] == first_attendee.id }
        expect(a['checked_in']).to be true
        expect(a['checked_in_by']).to eq("#{admin.first_name} #{admin.last_name}".strip)
      end

      it 'silently ignores attendee IDs not belonging to this order' do
        other_order = create(:order)
        other_attendee = create(:attendee, event: event, order: other_order)
        patch_order(order.order_reference, { attendees: [{ id: other_attendee.id, checked_in: true }] })
        expect(response).to have_http_status(:ok)
        expect(other_attendee.reload.checked_in).to be false
      end
    end

    context 'when updating attendee payment_status' do
      it 'marks an attendee as paid' do
        first_attendee.update!(payment_status: :payment_pending)
        patch_order(order.order_reference, { attendees: [{ id: first_attendee.id, payment_status: 'paid' }] })
        expect(response).to have_http_status(:ok)
        expect(first_attendee.reload.payment_status).to eq('paid')
        a = json['attendees'].find { |x| x['id'] == first_attendee.id }
        expect(a['payment_status']).to eq('paid')
      end

      it 'marks an attendee as payment_pending' do
        patch_order(order.order_reference, { attendees: [{ id: first_attendee.id, payment_status: 'payment_pending' }] })
        expect(response).to have_http_status(:ok)
        expect(first_attendee.reload.payment_status).to eq('payment_pending')
      end

      it 'silently ignores an invalid payment_status value' do
        patch_order(order.order_reference, { attendees: [{ id: first_attendee.id, payment_status: 'bounced' }] })
        expect(response).to have_http_status(:ok)
        expect(first_attendee.reload.payment_status).to eq('paid')
      end

      it 'can update both checked_in and payment_status in one entry' do
        first_attendee.update!(payment_status: :payment_pending)
        patch_order(order.order_reference, {
                      attendees: [{ id: first_attendee.id, checked_in: true, payment_status: 'paid' }]
                    })
        expect(response).to have_http_status(:ok)
        first_attendee.reload
        expect(first_attendee.checked_in).to be true
        expect(first_attendee.payment_status).to eq('paid')
      end
    end

    context 'when computed order payment_status reflects attendees' do
      it 'returns partial when attendees have mixed statuses' do
        first_attendee.update!(payment_status: :paid)
        second_attendee.update!(payment_status: :payment_pending)
        patch_order(order.order_reference, { attendees: [{ id: first_attendee.id, checked_in: true }] })
        expect(json['payment_status']).to eq('partial')
      end
    end

    describe 'self-check-in prevention' do
      context 'when the current user is an attendee in the order' do
        before { create(:attendee, event: event, order: order, user: admin) }

        it 'returns 403 with a descriptive message when trying to check in attendees' do
          patch_order(order.order_reference, { attendees: [{ id: first_attendee.id, checked_in: true }] })
          expect(response).to have_http_status(:forbidden)
          expect(json['error']).to eq(I18n.t('scan.errors.self_checkin_forbidden'))
        end

        it 'returns 403 with a descriptive message when trying to update attendee payment status' do
          patch_order(order.order_reference, { attendees: [{ id: first_attendee.id, payment_status: 'paid' }] })
          expect(response).to have_http_status(:forbidden)
          expect(json['error']).to eq(I18n.t('scan.errors.self_checkin_forbidden'))
        end
      end
    end
  end
end
