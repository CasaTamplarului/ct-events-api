# frozen_string_literal: true

require 'rails_helper'

RSpec.describe AttendeeBooleanFieldResponse, type: :model do
  subject(:response) { build(:attendee_boolean_field_response) }

  it { is_expected.to belong_to(:attendee) }
  it { is_expected.to belong_to(:event_boolean_field) }
  it { is_expected.to validate_inclusion_of(:value).in_array([true, false]) }
  it { is_expected.to validate_uniqueness_of(:event_boolean_field_id).scoped_to(:attendee_id) }
end
