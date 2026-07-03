# frozen_string_literal: true

require 'net/http'

class SendPushNotificationsJob < ApplicationJob
  queue_as :default

  def perform(push_notification_id, target_user_ids)
    push_notification = PushNotification.find_by(id: push_notification_id)
    return unless push_notification

    users = User.where(id: target_user_ids)
    warm_image_transform(push_notification.image_url)
    link = push_notification.link || (push_notification.event ? "/event/#{push_notification.event.slug}" : '/')
    preference = push_notification.event ? :event_update_push : :marketing_push

    users.each do |user|
      t = push_notification.translation_for(user.language)
      FcmService.send_to_user(
        user: user,
        title: t['title'],
        body: t['body'],
        image: push_notification.image_url,
        link: link,
        actions: t['actions'] || [],
        preference: preference
      )
    end

    # Anonymous mobile devices receive marketing broadcasts only.
    if preference == :marketing_push
      t = push_notification.translation_for('ro')
      FcmService.send_to_anonymous(
        title: t['title'],
        body: t['body'],
        image: push_notification.image_url,
        link: link,
        actions: t['actions'] || []
      )
    end

    push_notification.update!(sent_to: users.size)
  end

  private

    # Directus generates transforms lazily; the first render of a large
    # image can take ~1 minute — far beyond the iOS notification service
    # extension's time budget. Requesting it here caches it before any
    # device fetches.
    def warm_image_transform(url)
      return if url.blank?

      uri = URI(url)
      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = uri.scheme == 'https'
      http.read_timeout = 120
      http.get(uri.request_uri)
    rescue StandardError => e
      Rails.logger.warn("Push image warm-up failed: #{e.class}: #{e.message}")
    end
end
