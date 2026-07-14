# frozen_string_literal: true

require 'rails_helper'

RSpec.describe EventTeamsChannel, type: :channel do
  let(:admin) { create(:user, role: 'admin') }
  let(:volunteer) { create(:user, role: 'volunteer') }
  let(:attendee) { create(:user, role: 'attendee') }
  let(:event) { create(:event, slug: 'test-event-teams') }

  context 'when user is admin' do
    before { stub_connection current_user: admin }

    it 'subscribes and streams from the event channel' do
      subscribe event_slug: event.slug
      expect(subscription).to be_confirmed
      expect(subscription.streams).to include("event_teams_#{event.slug}")
    end
  end

  context 'when user is volunteer' do
    before { stub_connection current_user: volunteer }

    it 'subscribes successfully' do
      subscribe event_slug: event.slug
      expect(subscription).to be_confirmed
    end
  end

  context 'rejection cases' do
    before { stub_connection current_user: admin }

    it 'rejects when event_slug is blank' do
      subscribe event_slug: ''
      expect(subscription).to be_rejected
    end

    it 'rejects when event does not exist' do
      subscribe event_slug: 'no-such-event'
      expect(subscription).to be_rejected
    end
  end

  context 'when user lacks permission' do
    it 'rejects when current_user is nil' do
      stub_connection current_user: nil
      subscribe event_slug: event.slug
      expect(subscription).to be_rejected
    end

    it 'rejects when role is attendee' do
      stub_connection current_user: attendee
      subscribe event_slug: event.slug
      expect(subscription).to be_rejected
    end
  end
end
