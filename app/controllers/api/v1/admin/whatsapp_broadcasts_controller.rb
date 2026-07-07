# frozen_string_literal: true

module Api
  module V1
    module Admin
      class WhatsappBroadcastsController < ActionController::API
        include Authenticatable

        before_action :authenticate_user!
        before_action { require_permission!(:can_send_whatsapp) }

        def index
          broadcasts = WhatsappBroadcast.includes(:whatsapp_template, event: :events_translations)
                                        .order(created_at: :desc)
                                        .limit(50)
          render json: broadcasts.map { |b| broadcast_json(b) }
        end

        def create # rubocop:disable Metrics/AbcSize
          template = WhatsappTemplate.find_by(id: params[:template_id])
          return render json: { error: 'Template not found' }, status: :not_found unless template

          if params[:to].present?
            variables = (params[:variables].respond_to?(:to_unsafe_h) ? params[:variables].to_unsafe_h : {})
                        .stringify_keys
            content_variables = resolve_content_variables(template.variables, variables)
            TwilioService.send_whatsapp(
              to: params[:to],
              content_sid: template.content_sid,
              content_variables: content_variables
            )
            return render json: { sent_to: 1 }, status: :ok
          end

          user_ids           = resolve_user_ids
          unregistered_count = unregistered_attendee_count

          broadcast = WhatsappBroadcast.create!(
            whatsapp_template_id: template.id,
            event_id: params[:event_id].presence,
            sent_by_user_id: current_user.id,
            recipient_count: 0
          )

          SendWhatsappJob.perform_later(
            template_id: template.id,
            user_ids: user_ids,
            broadcast_id: broadcast.id,
            event_id: params[:event_id].presence,
            exclude_broadcast_ids: Array(params[:exclude_broadcast_ids]).presence
          )

          render json: { broadcast_id: broadcast.id, queued_for: user_ids.size + unregistered_count }, status: :ok
        end

        private

          def resolve_content_variables(variable_definitions, vars)
            variable_definitions.to_h do |vd|
              [vd['position'].to_s, vars.fetch(vd['name'].to_s, '')]
            end
          end

          def resolve_user_ids
            scope = User.active.where.not(phone_number: [nil, ''])

            if params[:event_id].present?
              scope = scope.joins(:attendees)
                           .where(attendees: { event_id: params[:event_id] })
                           .where.not(attendees: { payment_status: Attendee.payment_statuses[:attendee_cancelled] })
                           .distinct
            end

            if params[:exclude_broadcast_ids].present?
              already_sent_phones = WhatsappBroadcastRecipient
                                    .where(whatsapp_broadcast_id: Array(params[:exclude_broadcast_ids]))
                                    .pluck(:phone_number)
                                    .map(&:downcase)
              if already_sent_phones.any?
                scope = scope.where.not('LOWER(users.phone_number) IN (?)',
                                        already_sent_phones)
              end
            end

            scope.pluck(:id)
          end

          def unregistered_attendee_count
            return 0 if params[:event_id].blank?

            Attendee.where(event_id: params[:event_id], user_id: nil)
                    .where.not(payment_status: Attendee.payment_statuses[:attendee_cancelled])
                    .where.not(phone_number: [nil, ''])
                    .select(:phone_number)
                    .distinct
                    .count
          end

          def broadcast_json(broadcast)
            event_name = broadcast.event&.events_translations
                                  &.find { |t| t.languages_code == 'ro-RO' }
                                  &.name

            {
              id: broadcast.id,
              template_id: broadcast.whatsapp_template_id,
              template_name: broadcast.whatsapp_template&.name,
              event_id: broadcast.event_id,
              event_name: event_name,
              recipient_count: broadcast.recipient_count,
              sent_at: broadcast.created_at
            }
          end
      end
    end
  end
end
