# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Passkeys API' do
  let!(:user) { create(:user) }
  let(:jwt)   { JwtService.encode(user.id) }
  let(:auth_headers) { { 'Content-Type' => 'application/json', 'Authorization' => "Bearer #{jwt}" } }
  let(:json_headers) { { 'Content-Type' => 'application/json' } }

  # ─── Fake WebAuthn options objects ───────────────────────────────────────────

  let(:fake_reg_options) do
    double('CreationOptions', # rubocop:disable RSpec/VerifiedDoubles
           challenge: 'reg-challenge-b64url',
           as_json: {
             'challenge' => 'reg-challenge-b64url',
             'rp' => { 'name' => 'Casa Tâmplarului', 'id' => 'casatamplarului.ro' },
             'user' => { 'id' => 'abc', 'name' => user.email, 'displayName' => user.first_name },
             'pubKeyCredParams' => [{ 'type' => 'public-key', 'alg' => -7 }],
             'timeout' => 60_000,
             'attestation' => 'none',
             'authenticatorSelection' => { 'residentKey' => 'required', 'userVerification' => 'preferred' },
             'excludeCredentials' => []
           })
  end

  let(:fake_auth_options) do
    double('RequestOptions', # rubocop:disable RSpec/VerifiedDoubles
           challenge: 'auth-challenge-b64url',
           as_json: {
             'challenge' => 'auth-challenge-b64url',
             'timeout' => 60_000,
             'rpId' => 'casatamplarului.ro',
             'allowCredentials' => [],
             'userVerification' => 'preferred'
           })
  end

  let(:fake_reg_credential) do
    double('CreatedCredential', # rubocop:disable RSpec/VerifiedDoubles
           id: 'new-cred-external-id',
           public_key: 'fake-public-key-cbor',
           sign_count: 0)
  end

  let(:fake_auth_credential) do
    double('GetCredential', # rubocop:disable RSpec/VerifiedDoubles
           id: 'existing-cred-id',
           sign_count: 1)
  end

  # ─── Helper: build a real challenge_token ────────────────────────────────────

  def reg_challenge_token
    PasskeyChallengeService.encode(
      challenge: 'reg-challenge-b64url',
      purpose: PasskeyChallengeService::PURPOSE_REGISTER,
      user_id: user.id
    )
  end

  def auth_challenge_token
    PasskeyChallengeService.encode(
      challenge: 'auth-challenge-b64url',
      purpose: PasskeyChallengeService::PURPOSE_AUTHENTICATE
    )
  end

  # ─── POST /auth/passkeys/register/options ────────────────────────────────────

  describe 'POST /api/v1/auth/passkeys/register/options' do
    before { allow(WebAuthn::Credential).to receive(:options_for_create).and_return(fake_reg_options) }

    it 'returns 200 with WebAuthn options and a challenge_token' do # rubocop:disable RSpec/ExampleLength
      post '/api/v1/auth/passkeys/register/options',
           params: {}.to_json, headers: auth_headers
      expect(response).to have_http_status(:ok)
      expect(json['challenge']).to eq('reg-challenge-b64url')
      expect(json['challenge_token']).to be_present
      expect(json['rp']['name']).to eq('Casa Tâmplarului')
    end

    it 'returns 401 without authentication' do
      post '/api/v1/auth/passkeys/register/options',
           params: {}.to_json, headers: json_headers
      expect(response).to have_http_status(:unauthorized)
    end
  end

  # ─── POST /auth/passkeys/register ────────────────────────────────────────────

  describe 'POST /api/v1/auth/passkeys/register' do
    before do
      allow(WebAuthn::Credential).to receive(:from_create).and_return(fake_reg_credential)
      allow(fake_reg_credential).to receive(:verify)
    end

    def post_register(extra = {})
      body = {
        challenge_token: reg_challenge_token,
        nickname: 'MacBook Pro',
        id: 'new-cred-external-id',
        rawId: 'new-cred-external-id',
        type: 'public-key',
        response: { clientDataJSON: 'x', attestationObject: 'y' }
      }.merge(extra)
      post '/api/v1/auth/passkeys/register',
           params: body.to_json, headers: auth_headers
    end

    it 'returns 200 verified:true and creates a Passkey record' do
      expect { post_register }.to change(Passkey, :count).by(1)
      expect(response).to have_http_status(:ok)
      expect(json['verified']).to be true
    end

    it 'stores the correct external_id and nickname' do
      post_register
      pk = user.passkeys.last
      expect(pk.external_id).to eq('new-cred-external-id')
      expect(pk.nickname).to eq('MacBook Pro')
    end

    it 'returns 401 for an invalid challenge_token' do
      post_register(challenge_token: 'not.a.valid.token')
      expect(response).to have_http_status(:unauthorized)
      expect(json['error']).to eq('Invalid or expired challenge')
    end

    it 'returns 401 for a challenge_token with the wrong purpose' do # rubocop:disable RSpec/ExampleLength
      wrong_token = PasskeyChallengeService.encode(
        challenge: 'reg-challenge-b64url',
        purpose: PasskeyChallengeService::PURPOSE_AUTHENTICATE
      )
      post_register(challenge_token: wrong_token)
      expect(response).to have_http_status(:unauthorized)
    end

    it 'returns 401 for a challenge_token belonging to a different user' do # rubocop:disable RSpec/ExampleLength
      other_user = create(:user)
      wrong_token = PasskeyChallengeService.encode(
        challenge: 'reg-challenge-b64url',
        purpose: PasskeyChallengeService::PURPOSE_REGISTER,
        user_id: other_user.id
      )
      post_register(challenge_token: wrong_token)
      expect(response).to have_http_status(:unauthorized)
    end

    it 'returns 422 when WebAuthn verification fails' do
      allow(fake_reg_credential).to receive(:verify).and_raise(WebAuthn::Error)
      post_register
      expect(response).to have_http_status(:unprocessable_entity)
      expect(json['error']).to eq('Passkey verification failed')
    end

    it 'returns 409 when the credential is already registered' do
      create(:passkey, user: user, external_id: 'new-cred-external-id')
      post_register
      expect(response).to have_http_status(:conflict)
      expect(json['error']).to eq('Passkey already registered')
    end

    it 'returns 401 without authentication' do
      post '/api/v1/auth/passkeys/register',
           params: { challenge_token: reg_challenge_token }.to_json,
           headers: json_headers
      expect(response).to have_http_status(:unauthorized)
    end
  end

  # ─── POST /auth/passkeys/authenticate/options ─────────────────────────────────

  describe 'POST /api/v1/auth/passkeys/authenticate/options' do
    before { allow(WebAuthn::Credential).to receive(:options_for_get).and_return(fake_auth_options) }

    it 'returns 200 with WebAuthn options and a challenge_token (no auth required)' do # rubocop:disable RSpec/ExampleLength
      post '/api/v1/auth/passkeys/authenticate/options',
           params: {}.to_json, headers: json_headers
      expect(response).to have_http_status(:ok)
      expect(json['challenge']).to eq('auth-challenge-b64url')
      expect(json['challenge_token']).to be_present
      expect(json['allowCredentials']).to eq([])
    end
  end

  # ─── POST /auth/passkeys/authenticate ─────────────────────────────────────────

  describe 'POST /api/v1/auth/passkeys/authenticate' do
    let!(:passkey) { create(:passkey, user: user, external_id: 'existing-cred-id') }

    before do
      allow(WebAuthn::Credential).to receive(:from_get).and_return(fake_auth_credential)
      allow(fake_auth_credential).to receive(:verify)
    end

    def post_authenticate(extra = {})
      body = {
        challenge_token: auth_challenge_token,
        id: 'existing-cred-id',
        rawId: 'existing-cred-id',
        type: 'public-key',
        response: {
          clientDataJSON: 'x',
          authenticatorData: 'y',
          signature: 'z',
          userHandle: nil
        }
      }.merge(extra)
      post '/api/v1/auth/passkeys/authenticate',
           params: body.to_json, headers: json_headers
    end

    it 'returns 200 with a JWT and user object' do
      post_authenticate
      expect(response).to have_http_status(:ok)
      expect(json['jwt']).to be_present
      expect(json['user']['email']).to eq(user.email)
    end

    it 'updates the passkey sign_count' do
      post_authenticate
      expect(passkey.reload.sign_count).to eq(1)
    end

    it 'returns 404 when the credential id is not found' do
      post_authenticate(id: 'unknown-cred-id')
      expect(response).to have_http_status(:not_found)
      expect(json['error']).to eq('Passkey not found')
    end

    it 'returns 401 for an invalid challenge_token' do
      post_authenticate(challenge_token: 'bad.token.here')
      expect(response).to have_http_status(:unauthorized)
      expect(json['error']).to eq('Invalid or expired challenge')
    end

    it 'returns 401 when WebAuthn verification fails' do
      allow(fake_auth_credential).to receive(:verify).and_raise(WebAuthn::Error)
      post_authenticate
      expect(response).to have_http_status(:unauthorized)
      expect(json['error']).to eq('Passkey verification failed')
    end
  end

  # ─── GET /auth/passkeys ───────────────────────────────────────────────────────

  describe 'GET /api/v1/auth/passkeys' do
    let!(:iphone_passkey) { create(:passkey, user: user, nickname: 'iPhone') }
    let!(:unnamed_passkey) { create(:passkey, user: user, nickname: nil) }
    before { create(:passkey) } # other user's passkey — must exist but is not referenced

    it "returns the current user's passkeys only" do
      get '/api/v1/auth/passkeys', headers: auth_headers
      expect(response).to have_http_status(:ok)
      ids = json.pluck('id')
      expect(ids).to contain_exactly(iphone_passkey.id, unnamed_passkey.id)
    end

    it 'includes id, nickname, and created_at' do
      get '/api/v1/auth/passkeys', headers: auth_headers
      found = json.find { |pk| pk['id'] == iphone_passkey.id }
      expect(found['nickname']).to eq('iPhone')
      expect(found['created_at']).to be_present
    end

    it 'does not include external_id or public_key' do
      get '/api/v1/auth/passkeys', headers: auth_headers
      json.each do |pk|
        expect(pk.key?('external_id')).to be false
        expect(pk.key?('public_key')).to be false
      end
    end

    it 'returns 401 without authentication' do
      get '/api/v1/auth/passkeys', headers: json_headers
      expect(response).to have_http_status(:unauthorized)
    end
  end

  # ─── DELETE /auth/passkeys/:id ────────────────────────────────────────────────

  describe 'DELETE /api/v1/auth/passkeys/:id' do
    let!(:passkey) { create(:passkey, user: user) }

    it 'deletes the passkey and returns 204' do
      expect do
        delete "/api/v1/auth/passkeys/#{passkey.id}", headers: auth_headers
      end.to change(Passkey, :count).by(-1)
      expect(response).to have_http_status(:no_content)
    end

    it 'returns 404 when the passkey does not belong to the current user' do
      other_pk = create(:passkey)
      delete "/api/v1/auth/passkeys/#{other_pk.id}", headers: auth_headers
      expect(response).to have_http_status(:not_found)
      expect(json['error']).to eq('Passkey not found')
    end

    it 'returns 401 without authentication' do
      delete "/api/v1/auth/passkeys/#{passkey.id}", headers: json_headers
      expect(response).to have_http_status(:unauthorized)
    end
  end
end
