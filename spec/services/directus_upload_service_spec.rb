# frozen_string_literal: true

require 'rails_helper'

RSpec.describe DirectusUploadService do
  let(:directus_url) { ENV.fetch('DIRECTUS_URL', 'http://localhost:8091') }
  let(:file) do
    instance_double(
      ActionDispatch::Http::UploadedFile,
      original_filename: 'consent.pdf',
      content_type: 'application/pdf',
      read: '%PDF-1.4 fake pdf content'
    )
  end

  describe '.upload' do
    context 'when Directus responds successfully' do
      before do
        stub_request(:post, "#{directus_url}/files")
          .to_return(
            status: 200,
            body: { data: { id: 'abc-0000-0000-0000-000000000000' } }.to_json,
            headers: { 'Content-Type' => 'application/json' }
          )
      end

      it 'returns the directus file UUID' do
        result = described_class.upload(file)
        expect(result).to eq('abc-0000-0000-0000-000000000000')
      end

      it 'sends a multipart POST to the Directus /files endpoint' do
        described_class.upload(file)
        expect(WebMock).to have_requested(:post, "#{directus_url}/files")
          .with(headers: { 'Content-Type' => /multipart\/form-data/ })
      end
    end

    context 'when Directus returns a non-2xx response' do
      before do
        stub_request(:post, "#{directus_url}/files")
          .to_return(status: 500, body: 'Internal Server Error')
      end

      it 'raises DirectusUploadService::UploadError' do
        expect { described_class.upload(file) }.to raise_error(DirectusUploadService::UploadError)
      end
    end
  end
end
