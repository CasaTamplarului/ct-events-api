# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'POST /api/v1/admin/push_notifications' do
  let(:admin)   { create(:user, role: 'admin') }
  let(:user_ro) { create(:user, language: 'ro-RO') }
  let(:user_en) { create(:user, language: 'en-US') }
  let(:user_no_lang) { create(:user, language: nil) }
  let(:token)   { JwtService.encode(admin.id) }
  let(:headers) { { 'Content-Type' => 'application/json', 'Authorization' => "Bearer #{token}" } }
  let(:event)   { create(:event) }

  let(:translations) do
    {
      ro: { title: 'Salut!', body: 'Buna ziua' },
      en: { title: 'Hello!', body: 'Good day' }
    }
  end

  before do
    user_ro.push_subscriptions.create!(token: 'token-ro', platform: 'web')
    user_en.push_subscriptions.create!(token: 'token-en', platform: 'web')
    user_no_lang.push_subscriptions.create!(token: 'token-nl', platform: 'web')
    create(:attendee, event: event, user: user_ro, email_address: user_ro.email)
    create(:attendee, event: event, user: user_en, email_address: user_en.email)
  end

  def post_notification(params)
    post '/api/v1/admin/push_notifications',
         params: params.to_json,
         headers: headers
  end

  context 'with an admin JWT' do
    context 'with event_id' do
      it 'sends the right translation to each user' do
        allow(FcmService).to receive(:send_to_user)

        post_notification(event_id: event.id, translations: translations)

        expect(FcmService).to have_received(:send_to_user).with(
          hash_including(user: user_ro, title: 'Salut!', body: 'Buna ziua')
        )
        expect(FcmService).to have_received(:send_to_user).with(
          hash_including(user: user_en, title: 'Hello!', body: 'Good day')
        )
      end

      it 'uses event_update_push preference' do
        allow(FcmService).to receive(:send_to_user)

        post_notification(event_id: event.id, translations: translations)

        expect(FcmService).to have_received(:send_to_user).with(
          hash_including(preference: :event_update_push)
        ).at_least(:once)
      end

      it 'defaults link to /event/:slug' do
        allow(FcmService).to receive(:send_to_user)

        post_notification(event_id: event.id, translations: translations)

        expect(FcmService).to have_received(:send_to_user).with(
          hash_including(link: "/event/#{event.slug}")
        ).at_least(:once)
      end

      it 'returns 404 when event not found' do
        post_notification(event_id: 999_999, translations: translations)
        expect(response).to have_http_status(:not_found)
      end
    end

    context 'without event_id' do
      it 'sends to all users with push subscriptions' do
        allow(FcmService).to receive(:send_to_user)

        post_notification(translations: translations)

        expect(FcmService).to have_received(:send_to_user).exactly(3).times
      end

      it 'uses marketing_push preference' do
        allow(FcmService).to receive(:send_to_user)

        post_notification(translations: translations)

        expect(FcmService).to have_received(:send_to_user).with(
          hash_including(preference: :marketing_push)
        ).at_least(:once)
      end

      it 'defaults link to /' do
        allow(FcmService).to receive(:send_to_user)

        post_notification(translations: translations)

        expect(FcmService).to have_received(:send_to_user).with(
          hash_including(link: '/')
        ).at_least(:once)
      end
    end

    it 'falls back to ro translation for users with no language set' do
      allow(FcmService).to receive(:send_to_user)

      post_notification(translations: translations)

      expect(FcmService).to have_received(:send_to_user).with(
        hash_including(user: user_no_lang, title: 'Salut!', body: 'Buna ziua')
      )
    end

    it 'uses provided link over default' do
      allow(FcmService).to receive(:send_to_user)

      post_notification(event_id: event.id, translations: translations, link: '/bookings')

      expect(FcmService).to have_received(:send_to_user).with(
        hash_including(link: '/bookings')
      ).at_least(:once)
    end

    it 'passes image_url from directus_file_id when provided' do
      allow(FcmService).to receive(:send_to_user)

      post_notification(event_id: event.id, translations: translations,
                        directus_file_id: '187aa1d8-0000-0000-0000-000000000000')

      expect(FcmService).to have_received(:send_to_user).with(
        hash_including(image: "#{PushNotification::DIRECTUS_URL}/assets/187aa1d8-0000-0000-0000-000000000000")
      ).at_least(:once)
    end

    it 'passes translated actions to FcmService for each user language' do
      allow(FcmService).to receive(:send_to_user)
      translations_with_actions = {
        ro: { title: 'Salut!', body: 'Buna ziua',
              actions: [{ action: 'view_event', title: 'Deschide evenimentul', url: '/event/slug' }] },
        en: { title: 'Hello!', body: 'Good day',
              actions: [{ action: 'view_event', title: 'View Event', url: '/event/slug' }] }
      }

      post_notification(event_id: event.id, translations: translations_with_actions)

      expect(FcmService).to have_received(:send_to_user).with(
        hash_including(user: user_ro, actions: [{ 'action' => 'view_event', 'title' => 'Deschide evenimentul', 'url' => '/event/slug' }])
      )
      expect(FcmService).to have_received(:send_to_user).with(
        hash_including(user: user_en, actions: [{ 'action' => 'view_event', 'title' => 'View Event', 'url' => '/event/slug' }])
      )
    end

    it 'passes empty actions when not provided in translations' do
      allow(FcmService).to receive(:send_to_user)

      post_notification(event_id: event.id, translations: translations)

      expect(FcmService).to have_received(:send_to_user).with(
        hash_including(actions: [])
      ).at_least(:once)
    end

    it 'creates a PushNotification record' do
      allow(FcmService).to receive(:send_to_user)

      expect do
        post_notification(event_id: event.id, translations: translations)
      end.to change(PushNotification, :count).by(1)

      pn = PushNotification.last
      expect(pn.event).to eq(event)
      expect(pn.created_by).to eq(admin)
      expect(pn.sent_to).to eq(2)
      expect(pn.translations['ro']['title']).to eq('Salut!')
    end

    it 'returns 422 when translations are missing' do
      post_notification(event_id: event.id)
      expect(response).to have_http_status(:unprocessable_content)
    end

    it 'returns 422 when ro translation is missing' do
      post_notification(event_id: event.id,
                        translations: { en: { title: 'Hi', body: 'There' } })
      expect(response).to have_http_status(:unprocessable_content)
    end
  end

  context 'with a non-admin JWT' do
    let(:token) { JwtService.encode(user_ro.id) }

    it 'returns 403' do
      post_notification(event_id: event.id, translations: translations)
      expect(response).to have_http_status(:forbidden)
    end
  end

  context 'without a JWT' do
    it 'returns 401' do
      post '/api/v1/admin/push_notifications',
           params: { translations: translations }.to_json,
           headers: { 'Content-Type' => 'application/json' }
      expect(response).to have_http_status(:unauthorized)
    end
  end
end
