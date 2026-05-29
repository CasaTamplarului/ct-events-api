# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Passkey, type: :model do
  describe 'associations' do
    it { is_expected.to belong_to(:user) }
  end

  describe 'validations' do
    subject { create(:passkey) }

    it { is_expected.to validate_presence_of(:external_id) }
    it { is_expected.to validate_presence_of(:public_key) }
    it { is_expected.to validate_uniqueness_of(:external_id) }
  end
end
