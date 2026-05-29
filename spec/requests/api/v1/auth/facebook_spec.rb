# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'POST /api/v1/auth/facebook' do
  let(:app_id)       { 'test_app_id' }
  let(:app_secret)   { 'test_app_secret' }
  let(:access_token) { 'test_fb_access_token' }

  let(:debug_token_url) do
    "https://graph.facebook.com/debug_token?input_token=#{access_token}&access_token=#{app_id}%7C#{app_secret}"
  end

  let(:me_url) do
    "https://graph.facebook.com/me?fields=id%2Cemail%2Cfirst_name%2Clast_name%2Cpicture.type%28large%29&access_token=#{access_token}"
  end

  let(:fb_user_payload) do
    {
      id: 'fb-uid-123',
      email: 'ion@example.com',
      first_name: 'Ion',
      last_name: 'Popescu',
      picture: { data: { url: 'https://fb.com/photo.jpg' } }
    }.to_json
  end

  before do
    allow(Rails.application.credentials).to receive(:dig).and_call_original
    allow(Rails.application.credentials).to receive(:dig)
      .with(:auth, :facebook_app_id).and_return(app_id)
    allow(Rails.application.credentials).to receive(:dig)
      .with(:auth, :facebook_app_secret).and_return(app_secret)

    stub_request(:get, debug_token_url)
      .to_return(status: 200,
                 body: { data: { is_valid: true, app_id: app_id } }.to_json,
                 headers: { 'Content-Type' => 'application/json' })
  end

  def post_facebook(params = { access_token: access_token })
    post '/api/v1/auth/facebook',
         params: params.to_json,
         headers: { 'Content-Type' => 'application/json' }
  end

  context 'with a valid token — new user' do
    before do
      stub_request(:get, me_url)
        .to_return(status: 200, body: fb_user_payload,
                   headers: { 'Content-Type' => 'application/json' })
    end

    it 'returns 200 with a JWT and user data' do
      post_facebook
      expect(response).to have_http_status(:ok)
      expect(json['jwt']).to be_present
      expect(json['user']['email']).to eq('ion@example.com')
      expect(json['user']['first_name']).to eq('Ion')
    end

    it 'creates a new User record' do
      expect { post_facebook }.to change(User, :count).by(1)
    end

    it 'creates a UserIdentity with provider facebook' do
      post_facebook
      expect(UserIdentity.where(provider: 'facebook', uid: 'fb-uid-123')).to exist
    end

    it 'returns a JWT that decodes to the correct user_id' do
      post_facebook
      user_id = JwtService.decode(json['jwt'])
      expect(user_id).to eq(User.find_by(email: 'ion@example.com').id)
    end

    it 'sets avatar_url from the picture field' do
      post_facebook
      expect(User.find_by(email: 'ion@example.com').avatar_url).to eq('https://fb.com/photo.jpg')
    end

    it 'returns can_change_email: false' do
      post_facebook
      expect(json['user']['can_change_email']).to be false
    end

    it 'includes language in the user response' do
      post_facebook
      expect(json['user'].key?('language')).to be true
    end
  end

  context 'with a valid token — existing UserIdentity (idempotent)' do
    before do
      stub_request(:get, me_url)
        .to_return(status: 200, body: fb_user_payload,
                   headers: { 'Content-Type' => 'application/json' })
      post_facebook
    end

    it 'does not create a second user on repeated sign-in' do
      expect { post_facebook }.not_to change(User, :count)
      expect(response).to have_http_status(:ok)
    end
  end

  context 'with a valid token — existing User matched by email' do
    let!(:existing_user) { create(:user, email: 'ion@example.com') }

    before do
      stub_request(:get, me_url)
        .to_return(status: 200, body: fb_user_payload,
                   headers: { 'Content-Type' => 'application/json' })
    end

    it 'does not create a new user' do
      expect { post_facebook }.not_to change(User, :count)
    end

    it 'links a new Facebook identity to the existing user' do
      post_facebook
      expect(UserIdentity.find_by(provider: 'facebook', uid: 'fb-uid-123').user).to eq(existing_user)
    end

    it 'updates avatar_url on the existing user' do
      post_facebook
      expect(existing_user.reload.avatar_url).to eq('https://fb.com/photo.jpg')
    end
  end

  context 'attendee backfill on new user' do
    before do
      stub_request(:get, me_url)
        .to_return(status: 200, body: fb_user_payload,
                   headers: { 'Content-Type' => 'application/json' })
    end

    it 'links existing attendees with matching email to the new user' do
      event    = create(:event)
      attendee = create(:attendee, event: event, email_address: 'ion@example.com')
      post_facebook
      user = User.find_by(email: 'ion@example.com')
      expect(attendee.reload.user).to eq(user)
    end
  end

  context 'attendee backfill on email-matched existing user' do
    let!(:existing_user) { create(:user, email: 'ion@example.com') }

    before do
      stub_request(:get, me_url)
        .to_return(status: 200, body: fb_user_payload,
                   headers: { 'Content-Type' => 'application/json' })
    end

    it 'links existing attendees to the matched user' do
      event    = create(:event)
      attendee = create(:attendee, event: event, email_address: 'ion@example.com')
      post_facebook
      expect(attendee.reload.user).to eq(existing_user)
    end
  end

  context 'with a nil email (phone-only Facebook account)' do
    let(:fb_no_email_payload) do
      {
        id: 'fb-uid-789',
        first_name: 'Ion',
        last_name: 'Popescu',
        picture: { data: { url: nil } }
      }.to_json
    end

    before do
      stub_request(:get, me_url)
        .to_return(status: 200, body: fb_no_email_payload,
                   headers: { 'Content-Type' => 'application/json' })
    end

    it 'creates a user with nil email' do
      post_facebook
      expect(response).to have_http_status(:ok)
      user = User.find_by(first_name: 'Ion')
      expect(user.email).to be_nil
    end
  end

  context 'with a missing access_token param' do
    it 'returns 422' do
      post_facebook({})
      expect(response).to have_http_status(:unprocessable_entity)
      expect(json['error']).to eq('access_token is required')
    end
  end

  context 'with an invalid token (is_valid: false)' do
    before do
      stub_request(:get, debug_token_url)
        .to_return(status: 200,
                   body: { data: { is_valid: false, app_id: app_id } }.to_json,
                   headers: { 'Content-Type' => 'application/json' })
    end

    it 'returns 401' do
      post_facebook
      expect(response).to have_http_status(:unauthorized)
      expect(json['error']).to eq('Invalid Facebook token')
    end
  end

  context 'with a token from a different app' do
    before do
      stub_request(:get, debug_token_url)
        .to_return(status: 200,
                   body: { data: { is_valid: true, app_id: 'other_app' } }.to_json,
                   headers: { 'Content-Type' => 'application/json' })
    end

    it 'returns 401' do
      post_facebook
      expect(response).to have_http_status(:unauthorized)
      expect(json['error']).to eq('Invalid Facebook token')
    end
  end

  context 'when Graph API returns non-2xx' do
    before do
      stub_request(:get, debug_token_url)
        .to_return(status: 400, body: '{}',
                   headers: { 'Content-Type' => 'application/json' })
    end

    it 'returns 401' do
      post_facebook
      expect(response).to have_http_status(:unauthorized)
      expect(json['error']).to eq('Invalid Facebook token')
    end
  end
end
