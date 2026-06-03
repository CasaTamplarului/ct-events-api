# frozen_string_literal: true

require 'rails_helper'

RSpec.describe TicketMealSlot, type: :model do
  let(:ticket) { create(:ticket) }

  it 'is valid with ticket, occurs_on, and meal_type' do
    slot = described_class.new(ticket: ticket, occurs_on: Date.today, meal_type: 'lunch')
    expect(slot).to be_valid
  end

  it 'is invalid without occurs_on' do
    slot = described_class.new(ticket: ticket, meal_type: 'lunch')
    expect(slot).not_to be_valid
  end

  it 'is invalid without meal_type' do
    slot = described_class.new(ticket: ticket, occurs_on: Date.today)
    expect(slot).not_to be_valid
  end

  it 'is invalid with an unknown meal_type' do
    slot = described_class.new(ticket: ticket, occurs_on: Date.today, meal_type: 'brunch')
    expect(slot).not_to be_valid
  end

  it 'accepts all valid meal types' do
    %w[breakfast lunch dinner snack].each do |type|
      slot = described_class.new(ticket: ticket, occurs_on: Date.today, meal_type: type)
      expect(slot).to be_valid, "expected #{type} to be valid"
    end
  end
end
