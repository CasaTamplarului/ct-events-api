# frozen_string_literal: true

module Api
  module V1
    module Admin
      class EmailsController < ActionController::API
        include Authenticatable

        VALID_CHANNELS = EmailUnsubscribeTokenService::PREFERENCE_COLUMNS.freeze

        before_action :authenticate_user!
        before_action { require_permission!(:can_send_emails) }

        def create
          subject = params[:subject].presence
          body    = params[:body].presence
          channel = params[:channel].presence
          to      = params[:to].presence

          return render json: { error: 'subject is required' }, status: :bad_request if subject.blank?
          return render json: { error: 'body is required' },    status: :bad_request if body.blank?

          if to.present?
            AdminMailer.with(to: to, subject: subject, body: body).send_email.deliver_later
            return render json: { sent_to: 1 }, status: :ok
          end

          unless VALID_CHANNELS.include?(channel)
            return render json: { error: "channel must be one of: #{VALID_CHANNELS.join(', ')}" },
                          status: :bad_request
          end

          user_ids = resolve_user_ids
          SendEmailsJob.perform_later(subject: subject, body: body, channel: channel, user_ids: user_ids)

          render json: { queued_for: user_ids.size }, status: :ok
        end

        private

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
