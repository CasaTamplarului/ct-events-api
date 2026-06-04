# frozen_string_literal: true

module Api
  module V1
    class UploadsController < ActionController::API
      ALLOWED_TYPES = %w[application/pdf image/jpeg image/png].freeze

      def create
        file = params[:file]
        return render json: { error: 'file is required' }, status: :bad_request if file.blank?

        unless ALLOWED_TYPES.include?(file.content_type)
          return render json: { error: 'unsupported file type' }, status: :bad_request
        end

        uuid = DirectusUploadService.upload(file)
        render json: { directus_files_id: uuid }, status: :created
      rescue DirectusUploadService::UploadError => e
        Rails.logger.error("Directus upload failed: #{e.message}")
        render json: { error: 'file upload failed' }, status: :bad_gateway
      end
    end
  end
end
