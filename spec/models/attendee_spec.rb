require 'rails_helper'

RSpec.describe Attendee, type: :model do
  it 'has a valid factory' do
    expect(build(:attendee)).to be_valid
  end
end
