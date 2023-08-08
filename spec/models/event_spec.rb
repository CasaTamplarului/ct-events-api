# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Event do
  let(:event) { create(:event, max_number_of_people: 2) }

  it 'has a valid factory' do
    expect(build(:event)).to be_valid
  end

  describe 'ActiveModel validations' do
    context 'when max number is reached' do
      before do
        create_list(:attendee, 2, event: event)
      end

      it 'returns fully booked' do
        expect(event.fully_booked?).to be true
      end
    end

    context 'when max number is not reached' do
      before do
        create_list(:attendee, 1, event: event)
      end

      it 'returns event not fully booked' do
        expect(event.fully_booked?).to be false
      end
    end
  end
end
