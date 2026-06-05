# frozen_string_literal: true

require 'rails_helper'

RSpec.describe FcmService do
  let(:user) { create(:user) }

  before do
    user.push_subscriptions.create!(token: 'token-ios',     platform: 'ios')
    user.push_subscriptions.create!(token: 'token-android', platform: 'android')
    user.push_subscriptions.create!(token: 'token-web',     platform: 'web')
  end

  describe '.push_enabled?' do
    it 'returns false when FCM project_id is absent' do
      allow(Rails.application.credentials).to receive(:dig).with(:fcm, :project_id).and_return(nil)
      expect(described_class.push_enabled?).to be false
    end

    it 'returns true when FCM project_id is present' do
      allow(Rails.application.credentials).to receive(:dig).with(:fcm, :project_id).and_return('my-project')
      expect(described_class.push_enabled?).to be true
    end
  end

  describe '.send_to_user' do
    it 'returns early without sending when push is disabled' do
      allow(described_class).to receive(:push_enabled?).and_return(false)
      expect(described_class).not_to receive(:deliver)
      described_class.send_to_user(user: user, title: 'Hello', body: 'World')
    end

    it 'skips tokens for users who have opted out of the given preference' do
      user.update!(event_reminder_push: false)
      allow(described_class).to receive(:push_enabled?).and_return(true)
      allow(described_class).to receive(:deliver)

      described_class.send_to_user(user: user, title: 'Reminder', body: 'Event soon',
                                   preference: :event_reminder_push)

      expect(described_class).not_to have_received(:deliver)
    end

    it 'sends to all subscriptions when preference is opted in' do
      allow(described_class).to receive(:push_enabled?).and_return(true)
      allow(described_class).to receive(:access_token).and_return('fake-token')
      allow(described_class).to receive(:deliver)

      described_class.send_to_user(user: user, title: 'Update', body: 'New info',
                                   preference: :event_reminder_push)

      expect(described_class).to have_received(:deliver).exactly(3).times
    end
  end

  describe '.deliver (via HTTP stub)' do
    let(:project_id)   { 'test-project' }
    let(:access_token) { 'ya29.fake-token' }
    let(:fcm_url)      { "https://fcm.googleapis.com/v1/projects/#{project_id}/messages:send" }

    before do
      allow(Rails.application.credentials).to receive(:dig).with(:fcm, :project_id).and_return(project_id)
      allow(Rails.application.credentials).to receive(:dig).with(:fcm, :client_email).and_return('svc@project.iam.gserviceaccount.com')
      allow(Rails.application.credentials).to receive(:dig).with(:fcm, :private_key).and_return(nil)

      mock_creds = instance_double(Google::Auth::ServiceAccountCredentials,
                                   fetch_access_token!: nil, access_token: access_token)
      allow(Google::Auth::ServiceAccountCredentials).to receive(:make_creds).and_return(mock_creds)
    end

    it 'POSTs to the v1 endpoint with a Bearer token' do
      allow(described_class).to receive(:push_enabled?).and_return(true)

      described_class.send_to_user(user: user, title: 'Hi', body: 'There',
                                   preference: :marketing_push)

      expect(WebMock).to have_requested(:post, fcm_url)
        .with(headers: { 'Authorization' => "Bearer #{access_token}" })
        .at_least_once
    end

    it 'sends a data-only webpush payload with no top-level notification key' do
      allow(described_class).to receive(:push_enabled?).and_return(true)
      user.push_subscriptions.destroy_all
      user.push_subscriptions.create!(token: 'single-token', platform: 'web')

      described_class.send_to_user(user: user, title: 'Hi', body: 'There')

      expect(WebMock).to have_requested(:post, fcm_url).with { |req|
        body = JSON.parse(req.body)
        body['message'].key?('notification') == false &&
          body['message'].dig('webpush', 'data', 'title') == 'Hi' &&
          body['message'].dig('webpush', 'data', 'body') == 'There'
      }
    end

    it 'always includes the default icon in the webpush data' do
      allow(described_class).to receive(:push_enabled?).and_return(true)
      user.push_subscriptions.destroy_all
      user.push_subscriptions.create!(token: 'single-token', platform: 'web')

      described_class.send_to_user(user: user, title: 'Hi', body: 'There')

      expect(WebMock).to have_requested(:post, fcm_url).with { |req|
        body = JSON.parse(req.body)
        body['message'].dig('webpush', 'data', 'icon') == FcmService::DEFAULT_ICON
      }
    end

    it 'includes image in webpush data when provided' do
      allow(described_class).to receive(:push_enabled?).and_return(true)
      user.push_subscriptions.destroy_all
      user.push_subscriptions.create!(token: 'single-token', platform: 'web')

      described_class.send_to_user(user: user, title: 'Hi', body: 'There',
                                   image: 'https://example.com/hero.jpg')

      expect(WebMock).to have_requested(:post, fcm_url).with { |req|
        body = JSON.parse(req.body)
        body['message'].dig('webpush', 'data', 'image') == 'https://example.com/hero.jpg'
      }
    end

    it 'omits image from webpush data when not provided' do
      allow(described_class).to receive(:push_enabled?).and_return(true)
      user.push_subscriptions.destroy_all
      user.push_subscriptions.create!(token: 'single-token', platform: 'web')

      described_class.send_to_user(user: user, title: 'Hi', body: 'There')

      expect(WebMock).to have_requested(:post, fcm_url).with { |req|
        body = JSON.parse(req.body)
        body['message'].dig('webpush', 'data').key?('image') == false
      }
    end

    it 'JSON-encodes actions into webpush data when provided' do
      allow(described_class).to receive(:push_enabled?).and_return(true)
      user.push_subscriptions.destroy_all
      user.push_subscriptions.create!(token: 'single-token', platform: 'web')

      actions = [{ action: 'view_event', title: 'View Event' }, { action: 'my_bookings', title: 'My Bookings' }]
      described_class.send_to_user(user: user, title: 'Hi', body: 'There', actions: actions)

      expect(WebMock).to have_requested(:post, fcm_url).with { |req|
        body   = JSON.parse(req.body)
        parsed = JSON.parse(body['message'].dig('webpush', 'data', 'actions'))
        parsed.first['action'] == 'view_event' && parsed.last['action'] == 'my_bookings'
      }
    end

    it 'includes link in webpush fcm_options and data when provided' do
      allow(described_class).to receive(:push_enabled?).and_return(true)
      user.push_subscriptions.destroy_all
      user.push_subscriptions.create!(token: 'single-token', platform: 'web')

      described_class.send_to_user(user: user, title: 'Hi', body: 'There',
                                   link: 'https://ctevents.chiciudean.family/events/my-event')

      expect(WebMock).to have_requested(:post, fcm_url).with { |req|
        body = JSON.parse(req.body)
        body['message'].dig('webpush', 'data', 'link') == 'https://ctevents.chiciudean.family/events/my-event' &&
          body['message'].dig('webpush', 'fcm_options', 'link') == 'https://ctevents.chiciudean.family/events/my-event'
      }
    end

    it 'includes a top-level data field for Android/iOS with the same fields' do
      allow(described_class).to receive(:push_enabled?).and_return(true)
      user.push_subscriptions.destroy_all
      user.push_subscriptions.create!(token: 'single-token', platform: 'android')

      described_class.send_to_user(user: user, title: 'Hi', body: 'There',
                                   image: 'https://example.com/img.jpg',
                                   link: '/event/slug',
                                   actions: [{ action: 'view', title: 'View' }])

      expect(WebMock).to have_requested(:post, fcm_url).with { |req|
        data = JSON.parse(req.body).dig('message', 'data')
        data['title'] == 'Hi' &&
          data['body'] == 'There' &&
          data['image'] == 'https://example.com/img.jpg' &&
          data['link'] == '/event/slug' &&
          JSON.parse(data['actions']).first['action'] == 'view'
      }
    end

    it 'deletes a push subscription when FCM returns UNREGISTERED' do
      user.push_subscriptions.destroy_all
      sub = user.push_subscriptions.create!(token: 'stale-token', platform: 'android')

      stub_request(:post, fcm_url).to_return(
        status: 404,
        body: { error: { status: 'NOT_FOUND', details: [{ errorCode: 'UNREGISTERED' }] } }.to_json
      )
      allow(described_class).to receive(:push_enabled?).and_return(true)

      described_class.send_to_user(user: user, title: 'Hi', body: 'There')

      expect(PushSubscription.find_by(id: sub.id)).to be_nil
    end

    it 'does not delete a subscription when FCM returns a non-UNREGISTERED error' do
      user.push_subscriptions.destroy_all
      sub = user.push_subscriptions.create!(token: 'good-token', platform: 'ios')

      stub_request(:post, fcm_url).to_return(
        status: 500,
        body: { error: { status: 'INTERNAL' } }.to_json
      )
      allow(described_class).to receive(:push_enabled?).and_return(true)

      described_class.send_to_user(user: user, title: 'Hi', body: 'There')

      expect(PushSubscription.find_by(id: sub.id)).to be_present
    end
  end
end
