# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Attendee, type: :model do
  it 'has a valid factory' do
    expect(build(:attendee)).to be_valid
  end

  describe 'CANCELLATION_REASONS' do
    it 'includes all expected preset keys' do
      expect(Attendee::CANCELLATION_REASONS).to match_array(
        %w[cant_attend health financial plans_changed other]
      )
    end
  end

  describe 'cancellation_reason column' do
    it 'defaults to nil' do
      attendee = build(:attendee)
      expect(attendee.cancellation_reason).to be_nil
    end
  end

  describe 'cancellation_reason_text column' do
    it 'defaults to nil' do
      attendee = build(:attendee)
      expect(attendee.cancellation_reason_text).to be_nil
    end
  end
end
