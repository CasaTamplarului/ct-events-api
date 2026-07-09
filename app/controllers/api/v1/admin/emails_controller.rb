# frozen_string_literal: true

require 'net/http'

module Api
  module V1
    module Admin
      class EmailsController < ActionController::API
        include Authenticatable
        include ActiveStorage::SetCurrent

        VALID_CHANNELS = EmailUnsubscribeTokenService::PREFERENCE_COLUMNS.freeze
        MAX_FILE_SIZE  = 10.megabytes
        MAX_TOTAL_SIZE = 25.megabytes

        VARIABLES = [
          { key: 'first_name',      description: 'Recipient first name' },
          { key: 'last_name',       description: 'Recipient last name' },
          { key: 'email',           description: 'Recipient email address' },
          { key: 'event_name',      description: 'Event name (ro-RO) — only when sending to event attendees' },
          { key: 'order_reference', description: 'Order reference — only when sending to event attendees' }
        ].freeze

        before_action :authenticate_user!
        before_action { require_permission!(:can_send_emails) }

        def index
          broadcasts = EmailBroadcast.includes(:event)
                                     .order(created_at: :desc)
                                     .limit(50)
          render json: broadcasts.map { |b| broadcast_json(b) }
        end

        def variables
          render json: { variables: VARIABLES }
        end

        def create # rubocop:disable Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/MethodLength, Metrics/PerceivedComplexity
          subject    = params[:subject].presence
          body       = params[:body].presence
          subject_en = params[:subject_en].presence
          body_en    = params[:body_en].presence
          channel    = params[:channel].presence
          to         = params[:to].presence

          return render json: { error: 'subject is required' }, status: :bad_request if subject.blank?
          return render json: { error: 'body is required' },    status: :bad_request if body.blank?

          direct_files = Array(params[:attachments]).compact
          directus_ids = Array(params[:directus_file_ids]).compact

          return if size_limit_exceeded?(direct_files)

          if to.present?
            raw_vars     = params[:preview_variables]
            preview_vars = (raw_vars.respond_to?(:to_unsafe_h) ? raw_vars.to_unsafe_h : {})
                           .stringify_keys.slice(*SendEmailsJob::VARIABLE_KEYS)
            romanian     = params[:preview_language].to_s != 'en'
            subj         = romanian || subject_en.blank? ? subject : subject_en
            bod          = romanian || body_en.blank?    ? body    : body_en

            encoded, urls = build_test_attachments(direct_files, directus_ids)
            return if encoded.nil?

            SendgridService.send_broadcast(
              to: to,
              subject: substitute(subj, preview_vars),
              body_html: substitute(bod, preview_vars),
              is_romanian: romanian,
              attachments: encoded,
              attachment_urls: urls
            )
            return render json: { sent_to: 1 }, status: :ok
          end

          unless VALID_CHANNELS.include?(channel)
            return render json: { error: "channel must be one of: #{VALID_CHANNELS.join(', ')}" },
                          status: :bad_request
          end

          fetched_directus = fetch_all_directus(directus_ids)
          return if fetched_directus.nil?

          user_ids  = resolve_user_ids
          broadcast = EmailBroadcast.create!(
            subject: subject,
            body: body,
            subject_en: subject_en,
            body_en: body_en,
            channel: channel,
            event_id: params[:event_id].presence,
            sent_by_user_id: current_user.id,
            recipient_count: 0
          )

          attach_urls = attach_files(broadcast, direct_files, fetched_directus)
          broadcast.update!(attachment_urls: attach_urls)

          SendEmailsJob.perform_later(
            subject: subject,
            body: body,
            subject_en: subject_en,
            body_en: body_en,
            channel: channel,
            user_ids: user_ids,
            broadcast_id: broadcast.id,
            event_id: params[:event_id].presence,
            exclude_broadcast_ids: Array(params[:exclude_broadcast_ids]).presence
          )

          render json: { broadcast_id: broadcast.id, queued_for: user_ids.size + unregistered_attendee_count },
                 status: :ok
        end

        private

          def size_limit_exceeded?(files)
            files.each do |f|
              next unless f.size > MAX_FILE_SIZE

              render json: { error: "#{f.original_filename} exceeds the 10 MB per-file limit" },
                     status: :unprocessable_content
              return true
            end
            if files.sum(&:size) > MAX_TOTAL_SIZE
              render json: { error: 'Total attachments exceed the 25 MB limit' }, status: :unprocessable_content
              return true
            end
            false
          end

          def build_test_attachments(direct_files, directus_ids)
            encoded = direct_files.map do |f|
              { content: Base64.strict_encode64(f.read), type: f.content_type, filename: f.original_filename }
            end
            urls = []

            directus_ids.each do |uuid|
              res = fetch_directus_file(uuid)
              unless res.is_a?(Net::HTTPSuccess)
                render json: { error: "Directus file #{uuid} not found" }, status: :unprocessable_content
                return nil
              end
              ct       = res['Content-Type'].to_s.split(';').first.strip
              filename = extract_directus_filename(res, uuid)
              encoded << { content: Base64.strict_encode64(res.body), type: ct, filename: filename }
              urls    << { 'name' => filename, 'url' => "#{directus_base}/assets/#{uuid}" }
            end

            [encoded, urls]
          end

          def fetch_all_directus(directus_ids)
            directus_ids.map do |uuid|
              res = fetch_directus_file(uuid)
              unless res.is_a?(Net::HTTPSuccess)
                render json: { error: "Directus file #{uuid} not found" }, status: :unprocessable_content
                return nil
              end
              { uuid: uuid, response: res }
            end
          end

          def attach_files(broadcast, direct_files, fetched_directus)
            urls = []

            direct_files.each do |file|
              broadcast.attachments.attach(file)
              blob = broadcast.attachments.blobs.reload.order(:id).last
              urls << { 'name' => file.original_filename, 'url' => blob.url(expires_in: 30.days) }
            end

            fetched_directus.each do |item|
              res      = item[:response]
              uuid     = item[:uuid]
              ct       = res['Content-Type'].to_s.split(';').first.strip
              filename = extract_directus_filename(res, uuid)
              broadcast.attachments.attach(
                io: StringIO.new(res.body),
                filename: filename,
                content_type: ct
              )
              urls << { 'name' => filename, 'url' => "#{directus_base}/assets/#{uuid}" }
            end

            urls
          end

          def fetch_directus_file(uuid)
            uri = URI("#{directus_base}/assets/#{uuid}?download=1")
            req = Net::HTTP::Get.new(uri)
            req['Authorization'] = "Bearer #{Rails.application.credentials.dig(:directus, :admin_token)}"
            Net::HTTP.start(uri.hostname, uri.port, use_ssl: uri.scheme == 'https') { |h| h.request(req) }
          rescue StandardError => e
            Rails.logger.error("Directus fetch failed for #{uuid}: #{e.message}")
            nil
          end

          def extract_directus_filename(response, uuid)
            disposition = response['Content-Disposition'].to_s
            match       = disposition.match(/filename[*]?=(?:UTF-8'')?["']?([^"';\r\n]+)["']?/i)
            match ? CGI.unescape(match[1].delete('"\'').strip) : "attachment-#{uuid}"
          end

          def directus_base
            ENV.fetch('DIRECTUS_URL', 'http://localhost:8055').chomp('/')
          end

          def substitute(text, variables)
            variables.reduce(text) { |t, (k, v)| t.gsub("{{#{k}}}", v.to_s) }
          end

          def resolve_user_ids
            scope = User.active.where.not(email: nil)

            if params[:event_id].present?
              scope = scope.joins(:attendees)
                           .where(attendees: { event_id: params[:event_id] })
                           .where.not(attendees: { payment_status: Attendee.payment_statuses[:attendee_cancelled] })
                           .distinct
            end

            if params[:exclude_broadcast_ids].present?
              already_sent = EmailBroadcastRecipient
                             .where(email_broadcast_id: Array(params[:exclude_broadcast_ids]))
                             .pluck(:user_id)
              scope = scope.where.not(id: already_sent)
            end

            scope.pluck(:id)
          end

          def unregistered_attendee_count
            return 0 if params[:event_id].blank?

            Attendee.where(event_id: params[:event_id], user_id: nil)
                    .where.not(payment_status: Attendee.payment_statuses[:attendee_cancelled])
                    .where.not(email_address: [nil, ''])
                    .select(:email_address)
                    .distinct
                    .count
          end

          def broadcast_json(broadcast)
            event_name = broadcast.event&.events_translations
                                  &.find { |t| t.languages_code == 'ro-RO' }
                                  &.name

            {
              id: broadcast.id,
              subject: broadcast.subject,
              channel: broadcast.channel,
              event_id: broadcast.event_id,
              event_name: event_name,
              recipient_count: broadcast.recipient_count,
              sent_at: broadcast.created_at,
              attachments: broadcast.attachment_urls
            }
          end
      end
    end
  end
end
