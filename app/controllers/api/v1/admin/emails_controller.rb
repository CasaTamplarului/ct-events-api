# frozen_string_literal: true

module Api
  module V1
    module Admin
      class EmailsController < ActionController::API
        include Authenticatable

        VALID_CHANNELS = EmailUnsubscribeTokenService::PREFERENCE_COLUMNS.freeze

        VARIABLES = [
          { key: 'first_name',      description: 'Recipient first name' },
          { key: 'last_name',       description: 'Recipient last name' },
          { key: 'email',           description: 'Recipient email address' },
          { key: 'event_name',      description: 'Event name (ro-RO) — only when sending to event attendees' },
          { key: 'order_reference', description: 'Order reference — only when sending to event attendees' },
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

        def create
          subject    = params[:subject].presence
          body       = params[:body].presence
          subject_en = params[:subject_en].presence
          body_en    = params[:body_en].presence
          channel    = params[:channel].presence
          to         = params[:to].presence

          return render json: { error: 'subject is required' }, status: :bad_request if subject.blank?
          return render json: { error: 'body is required' },    status: :bad_request if body.blank?

          if to.present?
            preview_vars = (params[:preview_variables] || {}).to_unsafe_h.stringify_keys
                                                             .slice(*SendEmailsJob::VARIABLE_KEYS)
            romanian     = params[:preview_language].to_s != 'en'
            subj         = romanian || subject_en.blank? ? subject : subject_en
            bod          = romanian || body_en.blank?    ? body    : body_en

            SendgridService.send_broadcast(
              to:          to,
              subject:     substitute(subj, preview_vars),
              body_html:   substitute(bod,  preview_vars),
              is_romanian: romanian
            )
            return render json: { sent_to: 1 }, status: :ok
          end

          unless VALID_CHANNELS.include?(channel)
            return render json: { error: "channel must be one of: #{VALID_CHANNELS.join(', ')}" },
                          status: :bad_request
          end

          user_ids = resolve_user_ids

          broadcast = EmailBroadcast.create!(
            subject:         subject,
            body:            body,
            subject_en:      subject_en,
            body_en:         body_en,
            channel:         channel,
            event_id:        params[:event_id].presence,
            sent_by_user_id: current_user.id,
            recipient_count: 0
          )

          SendEmailsJob.perform_later(
            subject:              subject,
            body:                 body,
            subject_en:           subject_en,
            body_en:              body_en,
            channel:              channel,
            user_ids:             user_ids,
            broadcast_id:         broadcast.id,
            event_id:             params[:event_id].presence,
            exclude_broadcast_ids: Array(params[:exclude_broadcast_ids]).presence
          )

          render json: { broadcast_id: broadcast.id, queued_for: user_ids.size + unregistered_attendee_count }, status: :ok
        end

        private

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
              id:              broadcast.id,
              subject:         broadcast.subject,
              channel:         broadcast.channel,
              event_id:        broadcast.event_id,
              event_name:      event_name,
              recipient_count: broadcast.recipient_count,
              sent_at:         broadcast.created_at
            }
          end
      end
    end
  end
end
