# frozen_string_literal: true

require 'rails_helper'

RSpec.describe MealStamp, type: :model do
  let(:event)    { create(:event, start_date: 2.days.from_now, end_date: 3.days.from_now) }
  let(:ticket)   { create(:ticket, event: event) }
  let(:order)    { create(:order) }
  let(:attendee) { create(:attendee, event: event, order: order, ticket: ticket) }
  let(:slot)     { create(:ticket_meal_slot, ticket: ticket, occurs_on: 2.days.from_now, meal_type: 'lunch') }
  let(:stamper)  { create(:user) }

  it 'is valid with attendee, ticket_meal_slot, and stamped_by_user_id' do
    stamp = described_class.new(attendee: attendee, ticket_meal_slot: slot, stamped_by_user_id: stamper.id)
    expect(stamp).to be_valid
  end

  it 'is invalid without stamped_by_user_id' do
    stamp = described_class.new(attendee: attendee, ticket_meal_slot: slot)
    expect(stamp).not_to be_valid
  end

  it 'allows duplicate attendee + slot (seconds)' do
    create(:meal_stamp, attendee: attendee, ticket_meal_slot: slot, stamped_by_user_id: stamper.id)
    second = described_class.new(attendee: attendee, ticket_meal_slot: slot, stamped_by_user_id: stamper.id)
    expect(second).to be_valid
  end
end
