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
          { key: 'order_reference', description: 'Order reference — only when sending to event attendees' }
        ].freeze

        before_action :authenticate_user!
        before_action { require_permission!(:can_send_emails) }

        def variables
          render json: { variables: VARIABLES }
        end

        def create
          subject = params[:subject].presence
          body    = params[:body].presence
          channel = params[:channel].presence
          to      = params[:to].presence

          return render json: { error: 'subject is required' }, status: :bad_request if subject.blank?
          return render json: { error: 'body is required' },    status: :bad_request if body.blank?

          if to.present?
            preview_vars = (params[:preview_variables] || {}).to_unsafe_h.stringify_keys
                                                             .slice(*SendEmailsJob::VARIABLE_KEYS)
            personalized_subject = substitute(subject, preview_vars)
            personalized_body    = substitute(body,    preview_vars)

            AdminMailer.with(to: to, subject: personalized_subject, body: personalized_body)
                       .send_email.deliver_later
            return render json: { sent_to: 1 }, status: :ok
          end

          unless VALID_CHANNELS.include?(channel)
            return render json: { error: "channel must be one of: #{VALID_CHANNELS.join(', ')}" },
                          status: :bad_request
          end

          user_ids = resolve_user_ids
          SendEmailsJob.perform_later(
            subject:  subject,
            body:     body,
            channel:  channel,
            user_ids: user_ids,
            event_id: params[:event_id].presence
          )

          render json: { queued_for: user_ids.size }, status: :ok
        end

        private

          def substitute(text, variables)
            variables.reduce(text) { |t, (k, v)| t.gsub("{{#{k}}}", v.to_s) }
          end

          def resolve_user_ids
            scope = User.active.where.not(email: nil)

            if params[:event_id].present?
              scope = scope.joins(:attendees).where(attendees: { event_id: params[:event_id] }).distinct
            end

            scope.pluck(:id)
          end
      end
    end
  end
end
