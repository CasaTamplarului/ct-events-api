# frozen_string_literal: true

class SendPushNotificationsJob < ApplicationJob
  queue_as :default

  def perform(push_notification_id, target_user_ids)
    push_notification = PushNotification.find_by(id: push_notification_id)
    return unless push_notification

    users = User.where(id: target_user_ids)
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
end
