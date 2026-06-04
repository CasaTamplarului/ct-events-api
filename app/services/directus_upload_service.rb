# frozen_string_literal: true

class DirectusUploadService
  DIRECTUS_URL = ENV.fetch('DIRECTUS_URL', 'http://localhost:8091')

  class UploadError < StandardError; end

  def self.upload(file)
    new(file).upload
  end

  def initialize(file)
    @file = file
  end

  def upload
    uri = URI("#{DIRECTUS_URL}/files")
    boundary = "RailsBoundary#{SecureRandom.hex(8)}"

    req = Net::HTTP::Post.new(uri)
    req['Authorization'] = "Bearer #{admin_token}"
    req['Content-Type'] = "multipart/form-data; boundary=#{boundary}"
    req.body = build_multipart_body(boundary)

    res = Net::HTTP.start(uri.hostname, uri.port, use_ssl: uri.scheme == 'https') do |http|
      http.request(req)
    end

    raise UploadError, "Directus upload failed: #{res.code}" unless res.is_a?(Net::HTTPSuccess)

    JSON.parse(res.body).dig('data', 'id')
  end

  private

    def build_multipart_body(boundary)
      crlf = "\r\n"
      parts = [
        "--#{boundary}#{crlf}",
        "Content-Disposition: form-data; name=\"file\"; filename=\"#{@file.original_filename}\"#{crlf}",
        "Content-Type: #{@file.content_type}#{crlf}",
        crlf,
        @file.read,
        "#{crlf}--#{boundary}--#{crlf}"
      ]
      parts.map(&:b).join
    end

    def admin_token
      Rails.application.credentials.dig(:directus, :admin_token)
    end
end
