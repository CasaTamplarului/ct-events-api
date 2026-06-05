# frozen_string_literal: true

module Api
  module V1
    module Admin
      class PushNotificationsController < ActionController::API
        include Authenticatable

        before_action :authenticate_user!
        before_action { require_permission!(:can_send_push_notifications) }

        def create
          push_notification = PushNotification.new(
            event:            resolved_event,
            created_by:       current_user,
            translations:     translations_param,
            link:             params[:link].presence,
            directus_file_id: params[:directus_file_id].presence
          )

          unless push_notification.valid?
            return render json: { error: push_notification.errors.full_messages.first },
                          status: :unprocessable_content
          end

          targets = resolve_targets
          return render json: { error: 'Event not found' }, status: :not_found if targets.nil?

          link       = push_notification.link || default_link
          preference = @event ? :event_update_push : :marketing_push

          targets.each do |user|
            t = push_notification.translation_for(user.language)
            FcmService.send_to_user(
              user:       user,
              title:      t['title'],
              body:       t['body'],
              image:      push_notification.image_url,
              link:       link,
              actions:    t['actions'] || [],
              preference: preference
            )
          end

          push_notification.update!(sent_to: targets.size)
          push_notification.save!

          render json: { sent_to: targets.size }, status: :ok
        end

        private

          def translations_param
            params[:translations]&.to_unsafe_h&.deep_stringify_keys
          end

          def resolved_event
            return nil if params[:event_id].blank?

            @event = Event.find_by(id: params[:event_id])
          end

          def resolve_targets
            if params[:event_id].present?
              return nil unless @event

              User.joins(:attendees).where(attendees: { event_id: @event.id }).distinct.to_a
            else
              User.joins(:push_subscriptions).distinct.to_a
            end
          end

          def default_link
            @event ? "/event/#{@event.slug}" : '/'
          end
      end
    end
  end
end
