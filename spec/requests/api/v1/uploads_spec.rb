# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'POST /api/v1/uploads' do
  let(:pdf_file) do
    fixture_file_upload(Rails.root.join('spec/fixtures/files/test.pdf'), 'application/pdf')
  end

  before do
    allow(DirectusUploadService).to receive(:upload).and_return('new-uuid-0000-0000-000000000000')
  end

  describe 'success' do
    it 'returns 201 with directus_files_id' do
      post '/api/v1/uploads', params: { file: pdf_file }

      expect(response).to have_http_status(:created)
      expect(json['directus_files_id']).to eq('new-uuid-0000-0000-000000000000')
    end

    it 'calls DirectusUploadService.upload with the uploaded file' do
      post '/api/v1/uploads', params: { file: pdf_file }

      expect(DirectusUploadService).to have_received(:upload)
        .with(an_instance_of(ActionDispatch::Http::UploadedFile)).once
    end
  end

  describe 'missing file' do
    it 'returns 400' do
      post '/api/v1/uploads', params: {}

      expect(response).to have_http_status(:bad_request)
      expect(json['error']).to be_present
    end
  end

  describe 'unsupported MIME type' do
    let(:txt_file) do
      fixture_file_upload(Rails.root.join('spec/fixtures/files/test.pdf'), 'text/plain')
    end

    it 'returns 400' do
      post '/api/v1/uploads', params: { file: txt_file }

      expect(response).to have_http_status(:bad_request)
      expect(json['error']).to be_present
    end
  end

  describe 'when Directus upload fails' do
    before do
      allow(DirectusUploadService).to receive(:upload)
        .and_raise(DirectusUploadService::UploadError, 'upstream error')
    end

    it 'returns 502' do
      post '/api/v1/uploads', params: { file: pdf_file }

      expect(response).to have_http_status(:bad_gateway)
    end
  end
end
