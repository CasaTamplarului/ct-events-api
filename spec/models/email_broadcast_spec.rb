# frozen_string_literal: true

require 'rails_helper'

RSpec.describe EmailBroadcast do
  it { is_expected.to have_many_attached(:attachments) }

  describe '#attachment_urls' do
    it 'defaults to an empty array' do
      broadcast = EmailBroadcast.new
      expect(broadcast.attachment_urls).to eq([])
    end
  end
end
