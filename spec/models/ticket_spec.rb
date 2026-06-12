# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Ticket, type: :model do
  let(:event) { create(:event) }

  describe 'valid_to_not_before_valid_from' do
    it 'is valid when only valid_from is set' do
      ticket = build(:ticket, event: event, valid_from: Date.today, valid_to: nil)
      expect(ticket).to be_valid
    end

    it 'is valid when only valid_to is set' do
      ticket = build(:ticket, event: event, valid_from: nil, valid_to: Date.today)
      expect(ticket).to be_valid
    end

    it 'is valid when neither date is set' do
      ticket = build(:ticket, event: event, valid_from: nil, valid_to: nil)
      expect(ticket).to be_valid
    end

    it 'is valid when valid_from equals valid_to' do
      ticket = build(:ticket, event: event, valid_from: Date.today, valid_to: Date.today)
      expect(ticket).to be_valid
    end

    it 'is valid when valid_from is before valid_to' do
      ticket = build(:ticket, event: event, valid_from: Date.today, valid_to: Date.today + 1)
      expect(ticket).to be_valid
    end

    it 'is invalid when valid_to is before valid_from' do
      ticket = build(:ticket, event: event, valid_from: Date.today, valid_to: Date.today - 1)
      expect(ticket).not_to be_valid
      expect(ticket.errors[:valid_to]).to include('must be on or after valid_from')
    end
  end
end
