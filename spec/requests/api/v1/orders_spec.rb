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
      ticket_id: ticket.id,
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
      expect(json['order_reference']).to match(/\ACT-\d{4}-[A-Z0-9]{6}\z/)
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

    it 'persists age when provided' do
      item_with_age = valid_item.deep_merge(attendee: { age: 25 })
      post_order([item_with_age])

      expect(Attendee.last.age).to eq(25)
    end

    it 'ignores age when not provided' do
      post_order([valid_item])

      expect(Attendee.last.age).to be_nil
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

  describe 'unknown ticket id' do
    it 'returns 400' do
      post_order([valid_item.merge(ticket_id: 999_999)])

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

  describe 'registration cutoff' do
    def post_order_as(user, items)
      post "/api/v1/#{language_code}/orders",
           params: { items: items }.to_json,
           headers: {
             'Content-Type' => 'application/json',
             'Authorization' => "Bearer #{JwtService.encode(user.id)}"
           }
    end

    context 'when registration_closes_at is in the past' do
      let(:event) { create(:event, status: :live, slug: 'tabara-impact-2026', registration_closes_at: 1.hour.ago) }

      it 'returns 422 for an unauthenticated user' do
        post_order([valid_item])

        expect(response).to have_http_status(:unprocessable_entity)
        expect(json['error']).to be_present
      end

      it 'returns 422 for an attendee' do
        post_order_as(create(:user, role: 'attendee'), [valid_item])

        expect(response).to have_http_status(:unprocessable_entity)
      end

      it 'allows an admin to register past the cutoff' do
        post_order_as(create(:user, role: 'admin'), [valid_item])

        expect(response).to have_http_status(:created)
      end

      it 'allows a volunteer to register past the cutoff' do
        post_order_as(create(:user, role: 'volunteer'), [valid_item])

        expect(response).to have_http_status(:created)
      end
    end

    context 'when registration_closes_at is in the future' do
      let(:event) { create(:event, status: :live, slug: 'tabara-impact-2026', registration_closes_at: 1.hour.from_now) }

      it 'allows anyone to register' do
        post_order([valid_item])

        expect(response).to have_http_status(:created)
      end
    end

    context 'when registration_closes_at is nil' do
      it 'allows anyone to register' do
        post_order([valid_item])

        expect(response).to have_http_status(:created)
      end
    end
  end

  describe 'duplicate registration' do
    before { create(:attendee, event: event, email_address: 'ion@example.com') }

    it 'allows re-registration regardless of existing attendee status' do
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

  describe 'template doc uploads' do
    let!(:directus_file) { create(:directus_file) }
    let!(:template_doc) { create(:event_template_doc, event: event) }

    let(:item_with_upload) do
      valid_item.deep_merge(attendee: {
                              template_doc_uploads: [
                                { event_template_doc_id: template_doc.id, directus_files_id: directus_file.id }
                              ]
                            })
    end

    it 'creates AttendeeTemplateDocUpload records' do
      post_order([item_with_upload])

      expect(response).to have_http_status(:created)
      expect(AttendeeTemplateDocUpload.count).to eq(1)
      expect(AttendeeTemplateDocUpload.last.event_template_doc).to eq(template_doc)
      expect(AttendeeTemplateDocUpload.last.directus_files_id).to eq(directus_file.id)
    end

    it 'ignores template_doc_uploads when none provided' do
      post_order([valid_item])

      expect(response).to have_http_status(:created)
      expect(AttendeeTemplateDocUpload.count).to eq(0)
    end

    context 'when event_template_doc_id belongs to a different event' do
      let!(:other_event) { create(:event, status: :live) }
      let!(:other_doc) { create(:event_template_doc, event: other_event) }

      it 'returns 400' do
        item = valid_item.deep_merge(attendee: {
                                       template_doc_uploads: [
                                         { event_template_doc_id: other_doc.id, directus_files_id: directus_file.id }
                                       ]
                                     })
        post_order([item])

        expect(response).to have_http_status(:bad_request)
        expect(json['error']).to be_present
      end
    end

    context 'when a required template doc has no upload' do
      let!(:template_doc) { create(:event_template_doc, event: event, required: true, age_from: nil, age_to: nil) }
      let!(:doc_translation) do
        EventTemplateDocTranslation.create!(
          event_template_doc: template_doc,
          languages_code: language_code,
          label: 'Formular de consimțământ'
        )
      end

      it 'returns 400 and mentions the missing doc label' do
        post_order([valid_item])

        expect(response).to have_http_status(:bad_request)
        expect(json['error']).to include('Formular de consimțământ')
      end
    end

    context 'when a required template doc has an age range' do
      let!(:template_doc) { create(:event_template_doc, event: event, required: true, age_from: 13, age_to: 17) }

      it 'does not require upload for attendee outside the age range' do
        post_order([valid_item.deep_merge(attendee: { age: 25 })])

        expect(response).to have_http_status(:created)
      end

      it 'requires upload for attendee within the age range' do
        post_order([valid_item.deep_merge(attendee: { age: 15 })])

        expect(response).to have_http_status(:bad_request)
      end

      it 'does not require upload when attendee has no age set' do
        post_order([valid_item])

        expect(response).to have_http_status(:created)
      end
    end
  end

  context 'for_leaders ticket with allowed_users list' do
    let(:leader_user) { create(:user, role: 'leader') }
    let(:other_leader) { create(:user, role: 'leader') }
    let(:leader_ticket) { create(:ticket, event: event, for_leaders: true) }
    let!(:leader_ticket_translation) do
      create(:tickets_translation, tickets_id: leader_ticket.id, languages_code: language_code, name: 'Leader')
    end

    def leader_item(user_id: leader_user.id)
      {
        event_slug: event.slug,
        ticket_id: leader_ticket.id,
        attendee: {
          first_name: 'Ion',
          last_name: 'Popescu',
          email_address: "leader#{user_id}@example.com",
          phone_number: '0722000000'
        }
      }
    end

    def post_order_as(user, item)
      post "/api/v1/#{language_code}/orders",
           params: { items: [item] }.to_json,
           headers: {
             'Content-Type' => 'application/json',
             'Authorization' => "Bearer #{JwtService.encode(user.id)}"
           }
    end

    context 'when no allowed_users are assigned' do
      it 'allows any non-attendee role to create an order' do
        post_order_as(leader_user, leader_item)

        expect(response).to have_http_status(:created)
      end
    end

    context 'when allowed_users list is non-empty' do
      before { create(:ticket_allowed_user, ticket: leader_ticket, user: leader_user) }

      it 'allows the user who is in the list to create an order' do
        post_order_as(leader_user, leader_item)

        expect(response).to have_http_status(:created)
      end

      it 'returns 403 for a user who is not in the list' do
        post_order_as(other_leader, leader_item(user_id: other_leader.id))

        expect(response).to have_http_status(:forbidden)
        expect(json['error']).to eq(I18n.t('orders.errors.not_allowed_for_ticket', locale: :ro))
      end
    end
  end

  describe 'boolean field responses' do
    let!(:boolean_field) { create(:event_boolean_field, event: event, required: false) }
    let!(:boolean_field_translation) do
      EventBooleanFieldTranslation.create!(
        event_boolean_field: boolean_field,
        languages_code: language_code,
        label: 'Ești de acord?',
        true_label: 'Da',
        false_label: 'Nu'
      )
    end

    let(:item_with_response) do
      valid_item.deep_merge(attendee: {
                              boolean_field_responses: [
                                { event_boolean_field_id: boolean_field.id, value: true }
                              ]
                            })
    end

    it 'creates AttendeeBooleanFieldResponse records' do
      post_order([item_with_response])

      expect(response).to have_http_status(:created)
      expect(AttendeeBooleanFieldResponse.count).to eq(1)
      expect(AttendeeBooleanFieldResponse.last.event_boolean_field).to eq(boolean_field)
      expect(AttendeeBooleanFieldResponse.last.value).to be true
    end

    it 'accepts false as a valid response value' do
      item = valid_item.deep_merge(attendee: {
                                     boolean_field_responses: [{ event_boolean_field_id: boolean_field.id, value: false }]
                                   })
      post_order([item])

      expect(response).to have_http_status(:created)
      expect(AttendeeBooleanFieldResponse.last.value).to be false
    end

    it 'ignores boolean_field_responses when none are provided' do
      post_order([valid_item])

      expect(response).to have_http_status(:created)
      expect(AttendeeBooleanFieldResponse.count).to eq(0)
    end

    context 'when event_boolean_field_id belongs to a different event' do
      let!(:other_event) { create(:event, status: :live) }
      let!(:other_field) { create(:event_boolean_field, event: other_event) }

      it 'returns 400' do
        item = valid_item.deep_merge(attendee: {
                                       boolean_field_responses: [{ event_boolean_field_id: other_field.id, value: true }]
                                     })
        post_order([item])

        expect(response).to have_http_status(:bad_request)
        expect(json['error']).to be_present
      end
    end

    context 'when a required boolean field has no response' do
      let!(:boolean_field) { create(:event_boolean_field, event: event, required: true) }
      # Override outer translation so only one translation exists for boolean_field + language_code
      let!(:boolean_field_translation) do
        EventBooleanFieldTranslation.create!(
          event_boolean_field: boolean_field,
          languages_code: language_code,
          label: 'Ești de acord?',
          true_label: 'Da',
          false_label: 'Nu'
        )
      end

      it 'returns 400 and includes the missing field label in the error' do
        post_order([valid_item])

        expect(response).to have_http_status(:bad_request)
        expect(json['error']).to include('Ești de acord?')
      end
    end
  end
end
