# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Attendee do
  it 'has a valid factory' do
    expect(build(:attendee)).to be_valid
  end
end
