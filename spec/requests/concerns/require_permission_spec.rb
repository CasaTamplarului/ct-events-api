# frozen_string_literal: true

require 'rails_helper'

class PermissionTestController < ActionController::API
  include Authenticatable

  before_action :authenticate_user!
  before_action { require_permission!(:can_check_in_attendees) }

  def index
    render json: { ok: true }
  end
end

RSpec.describe 'require_permission! (Authenticatable concern)' do
  before(:all) do
    Rails.application.routes.draw do
      get '/spec/permission_check', to: 'permission_test#index'
    end
  end

  after(:all) { Rails.application.reload_routes! }

  let(:attendee)  { create(:user, role: 'attendee') }
  let(:volunteer) { create(:user, role: 'volunteer') }

  def call_endpoint(user)
    get '/spec/permission_check',
        headers: {
          'Authorization'  => "Bearer #{JwtService.encode(user.id)}",
          'Content-Type'   => 'application/json'
        }
  end

  it 'returns 403 Forbidden when user lacks the permission' do
    call_endpoint(attendee)
    expect(response).to have_http_status(:forbidden)
    expect(json['error']).to eq('Forbidden')
  end

  it 'returns 200 OK when user has the permission' do
    call_endpoint(volunteer)
    expect(response).to have_http_status(:ok)
    expect(json['ok']).to be true
  end

  it 'returns 401 Unauthorized when no token is provided' do
    get '/spec/permission_check', headers: { 'Content-Type' => 'application/json' }
    expect(response).to have_http_status(:unauthorized)
    expect(json['error']).to eq('Unauthorized')
  end
end
