# frozen_string_literal: true

require 'rails_helper'

RSpec.describe WhatsappTemplate, type: :model do
  it 'is valid with name and content_sid' do
    expect(build(:whatsapp_template)).to be_valid
  end

  it 'is invalid without name' do
    expect(build(:whatsapp_template, name: nil)).not_to be_valid
  end

  it 'is invalid without content_sid' do
    expect(build(:whatsapp_template, content_sid: nil)).not_to be_valid
  end

  it 'defaults variables to an empty array' do
    t = create(:whatsapp_template, variables: nil)
    expect(t.reload.variables).to eq([])
  end
end
