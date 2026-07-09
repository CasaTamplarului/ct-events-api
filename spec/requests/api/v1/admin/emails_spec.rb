# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'POST /api/v1/admin/emails' do
  let(:admin)   { create(:user, role: 'admin') }
  let(:token)   { JwtService.encode(admin.id) }
  let(:headers) { auth_headers(token, with_default_headers: false) }

  before do
    stub_request(:post, 'https://api.sendgrid.com/v3/mail/send')
      .to_return(status: 202, body: '', headers: {})
    allow(Rails.application.credentials).to receive(:dig).and_call_original
    allow(Rails.application.credentials).to receive(:dig)
      .with(:sendgrid, :api_key).and_return('SG.testkey')
    allow(Rails.application.credentials).to receive(:dig)
      .with(:sendgrid, :from_email).and_return('noreply@test.com')
  end

  def pdf_upload(name: 'file.pdf', size: 1.kilobyte)
    Rack::Test::UploadedFile.new(
      StringIO.new('A' * size),
      'application/pdf',
      original_filename: name
    )
  end

  describe 'test send (to: present)' do
    it 'sends with a direct upload attachment' do
      post '/api/v1/admin/emails',
           params: {
             subject: 'Test', body: '<p>Hi</p>', to: 'ion@example.com',
             preview_language: 'ro',
             attachments: [pdf_upload(name: 'programme.pdf')]
           },
           headers: headers

      expect(response).to have_http_status(:ok)
      body = JSON.parse(WebMock::RequestRegistry.instance.requested_signatures.hash.keys.last.body)
      expect(body['attachments']&.first).to include('filename' => 'programme.pdf', 'type' => 'application/pdf')
    end

    it 'fetches and sends a Directus file' do
      allow(Rails.application.credentials).to receive(:dig)
        .with(:directus, :admin_token).and_return('directus-token')
      stub_request(:get, "#{ENV.fetch('DIRECTUS_URL', 'http://localhost:8055')}/assets/uuid-123?download=1")
        .to_return(
          status: 200,
          body: 'PDF bytes',
          headers: { 'Content-Type' => 'application/pdf', 'Content-Disposition' => 'attachment; filename="doc.pdf"' }
        )

      post '/api/v1/admin/emails',
           params: {
             subject: 'Test', body: '<p>Hi</p>', to: 'ion@example.com',
             preview_language: 'ro',
             directus_file_ids: ['uuid-123']
           },
           headers: headers

      expect(response).to have_http_status(:ok)
      body = JSON.parse(WebMock::RequestRegistry.instance.requested_signatures.hash.keys.last.body)
      expect(body['attachments']&.first).to include('filename' => 'doc.pdf')
    end

    it 'returns 422 when a Directus file UUID is not found' do
      allow(Rails.application.credentials).to receive(:dig)
        .with(:directus, :admin_token).and_return('directus-token')
      stub_request(:get, "#{ENV.fetch('DIRECTUS_URL', 'http://localhost:8055')}/assets/bad-uuid?download=1")
        .to_return(status: 404, body: 'Not Found', headers: {})

      post '/api/v1/admin/emails',
           params: {
             subject: 'Test', body: '<p>Hi</p>', to: 'ion@example.com',
             preview_language: 'ro',
             directus_file_ids: ['bad-uuid']
           },
           headers: headers

      expect(response).to have_http_status(:unprocessable_entity)
      expect(JSON.parse(response.body)['error']).to match(/bad-uuid/)
    end
  end

  describe 'bulk send' do
    let(:subscribed_user) { create(:user, email: 'ion@example.com', marketing_emails: true) }

    it 'returns 422 when a single file exceeds 10 MB' do
      post '/api/v1/admin/emails',
           params: {
             subject: 'Test', body: '<p>Hi</p>', channel: 'marketing_emails',
             attachments: [pdf_upload(name: 'big.pdf', size: 11.megabytes)]
           },
           headers: headers

      expect(response).to have_http_status(:unprocessable_entity)
      expect(JSON.parse(response.body)['error']).to match(/10 MB/)
    end

    it 'returns 422 when total attachments exceed 25 MB' do
      post '/api/v1/admin/emails',
           params: {
             subject: 'Test', body: '<p>Hi</p>', channel: 'marketing_emails',
             attachments: [
               pdf_upload(name: 'a.pdf', size: 9.megabytes),
               pdf_upload(name: 'b.pdf', size: 9.megabytes),
               pdf_upload(name: 'c.pdf', size: 9.megabytes)
             ]
           },
           headers: headers

      expect(response).to have_http_status(:unprocessable_entity)
      expect(JSON.parse(response.body)['error']).to match(/25 MB/)
    end

    it 'attaches a direct upload file to the broadcast' do
      subscribed_user

      post '/api/v1/admin/emails',
           params: {
             subject: 'Test', body: '<p>Hi</p>', channel: 'marketing_emails',
             attachments: [pdf_upload(name: 'programme.pdf')]
           },
           headers: headers

      expect(response).to have_http_status(:ok)
      broadcast = EmailBroadcast.last
      expect(broadcast.attachments.count).to eq(1)
      expect(broadcast.attachments.first.filename.to_s).to eq('programme.pdf')
    end

    it 'stores the Directus URL in attachment_urls for a Directus file' do
      allow(Rails.application.credentials).to receive(:dig)
        .with(:directus, :admin_token).and_return('directus-token')
      directus_base = ENV.fetch('DIRECTUS_URL', 'http://localhost:8055')
      stub_request(:get, "#{directus_base}/assets/uuid-abc?download=1")
        .to_return(
          status: 200,
          body: 'PDF bytes',
          headers: { 'Content-Type' => 'application/pdf', 'Content-Disposition' => 'attachment; filename="guide.pdf"' }
        )

      post '/api/v1/admin/emails',
           params: {
             subject: 'Test', body: '<p>Hi</p>', channel: 'marketing_emails',
             directus_file_ids: ['uuid-abc']
           },
           headers: headers

      expect(response).to have_http_status(:ok)
      broadcast = EmailBroadcast.last
      expect(broadcast.attachment_urls).to include(
        { 'name' => 'guide.pdf', 'url' => "#{directus_base}/assets/uuid-abc" }
      )
    end
  end

  describe 'GET /api/v1/admin/emails' do
    it 'includes attachments in broadcast history' do
      broadcast = create(:email_broadcast, attachment_urls: [{ 'name' => 'doc.pdf', 'url' => 'https://example.com/doc.pdf' }])

      get '/api/v1/admin/emails', headers: headers

      data = JSON.parse(response.body)
      entry = data.find { |b| b['id'] == broadcast.id }
      expect(entry['attachments']).to eq([{ 'name' => 'doc.pdf', 'url' => 'https://example.com/doc.pdf' }])
    end
  end
end
