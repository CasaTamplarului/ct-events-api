# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Auth endpoint rate limiting' do
  before do
    Rack::Attack.cache.store = ActiveSupport::Cache::MemoryStore.new
  end

  let(:valid_registration_params) do
    { first_name: 'Ion', email: "ion#{SecureRandom.hex(4)}@example.com", password: 'Password123' }
  end

  def post_registration(params)
    post '/api/v1/auth/registration',
         params: params.to_json,
         headers: { 'Content-Type' => 'application/json' }
  end

  def post_session(params)
    post '/api/v1/auth/session',
         params: params.to_json,
         headers: { 'Content-Type' => 'application/json' }
  end

  describe 'POST /api/v1/auth/registration' do
    it 'allows the first 5 requests and blocks the 6th with 429' do
      5.times { post_registration(valid_registration_params.merge(email: "ion#{SecureRandom.hex(4)}@example.com")) }
      post_registration(valid_registration_params.merge(email: "ion#{SecureRandom.hex(4)}@example.com"))

      expect(response).to have_http_status(:too_many_requests)
      expect(json['error']).to eq('Too many requests. Please try again later.')
    end
  end

  describe 'POST /api/v1/auth/session' do
    it 'allows the first 5 requests and blocks the 6th with 429' do
      6.times { post_session({ email: 'x@example.com', password: 'wrong' }) }

      expect(response).to have_http_status(:too_many_requests)
      expect(json['error']).to eq('Too many requests. Please try again later.')
    end
  end

  def post_forgot(email)
    post '/api/v1/auth/password/forgot',
         params: { email: email }.to_json,
         headers: { 'Content-Type' => 'application/json' }
  end

  describe 'POST /api/v1/auth/password/forgot' do
    before do
      allow(SendgridService).to receive(:send_password_reset)
    end

    it 'allows the first 3 requests and blocks the 4th with 429' do
      3.times { post_forgot('nobody@example.com') }
      post_forgot('nobody@example.com')

      expect(response).to have_http_status(:too_many_requests)
      expect(json['error']).to eq('Too many requests. Please try again later.')
    end
  end
end
