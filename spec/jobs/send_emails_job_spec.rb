# frozen_string_literal: true

require 'rails_helper'

RSpec.describe SendEmailsJob do
  let(:user) { create(:user, email: 'ion@example.com', language: 'ro-RO', marketing_emails: true) }
  let(:broadcast) { create(:email_broadcast, subject: 'Test', body: 'Hello', channel: 'marketing_emails') }

  before do
    stub_request(:post, 'https://api.sendgrid.com/v3/mail/send')
      .to_return(status: 202, body: '', headers: {})
    allow(Rails.application.credentials).to receive(:dig).and_call_original
    allow(Rails.application.credentials).to receive(:dig)
      .with(:sendgrid, :api_key).and_return('SG.testkey')
    allow(Rails.application.credentials).to receive(:dig)
      .with(:sendgrid, :from_email).and_return('noreply@test.com')
  end

  describe '#perform' do
    context 'with no attachments' do
      it 'sends email and records recipient' do
        described_class.new.perform(
          subject: 'Test', body: 'Hello', channel: 'marketing_emails',
          user_ids: [user.id], broadcast_id: broadcast.id
        )
        expect(WebMock).to have_requested(:post, 'https://api.sendgrid.com/v3/mail/send').once
        expect(broadcast.reload.recipient_count).to eq(1)
      end
    end

    context 'with an attachment on the broadcast' do
      before do
        broadcast.attachments.attach(
          io: StringIO.new('PDF content'),
          filename: 'programme.pdf',
          content_type: 'application/pdf'
        )
        broadcast.update!(attachment_urls: [{ 'name' => 'programme.pdf', 'url' => 'https://example.com/file.pdf' }])
      end

      it 'passes the encoded blob to SendgridService' do
        allow(SendgridService).to receive(:send_broadcast).and_call_original

        described_class.new.perform(
          subject: 'Test', body: 'Hello', channel: 'marketing_emails',
          user_ids: [user.id], broadcast_id: broadcast.id
        )

        expect(SendgridService).to have_received(:send_broadcast).with(
          hash_including(
            attachments: [{ content: Base64.strict_encode64('PDF content'), type: 'application/pdf', filename: 'programme.pdf' }],
            attachment_urls: [{ 'name' => 'programme.pdf', 'url' => 'https://example.com/file.pdf' }]
          )
        )
      end

      it 'downloads each blob only once regardless of recipient count' do
        user2 = create(:user, email: 'maria@example.com', language: 'ro-RO', marketing_emails: true)
        blob  = broadcast.attachments.blobs.first
        allow(blob).to receive(:download).and_call_original

        described_class.new.perform(
          subject: 'Test', body: 'Hello', channel: 'marketing_emails',
          user_ids: [user.id, user2.id], broadcast_id: broadcast.id
        )

        # download called once even though two recipients
        expect(blob).to have_received(:download).once
      end
    end
  end
end
