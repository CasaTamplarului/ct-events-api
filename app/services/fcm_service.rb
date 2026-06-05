# frozen_string_literal: true

require 'googleauth'

class FcmService
  FCM_SCOPE    = 'https://www.googleapis.com/auth/firebase.messaging'
  FCM_ENDPOINT = 'https://fcm.googleapis.com/v1/projects/%s/messages:send'
  DEFAULT_ICON = 'https://ctevents.chiciudean.family/images/ct-logo-white-email.png'

  def self.push_enabled?
    Rails.application.credentials.dig(:fcm, :project_id).present?
  end

  def self.send_to_user(user:, title:, body:, image: nil, link: nil, actions: [], preference: nil)
    return unless push_enabled?
    return if preference && !user.public_send(preference)

    token = access_token
    user.push_subscriptions.each do |subscription|
      deliver(subscription: subscription, title: title, body: body,
              image: image, link: link, actions: actions, access_token: token)
    end
  end

  class << self
    private

      def access_token
        creds = Google::Auth::ServiceAccountCredentials.make_creds(
          json_key_io: StringIO.new(service_account_json),
          scope: FCM_SCOPE
        )
        creds.fetch_access_token!
        creds.access_token
      end

      def service_account_json
        {
          type: 'service_account',
          project_id: Rails.application.credentials.dig(:fcm, :project_id),
          client_email: Rails.application.credentials.dig(:fcm, :client_email),
          private_key: Rails.application.credentials.dig(:fcm, :private_key)
        }.to_json
      end

      def deliver(subscription:, title:, body:, image:, link:, actions:, access_token:)
        project_id = Rails.application.credentials.dig(:fcm, :project_id)
        uri        = URI(FCM_ENDPOINT % project_id)
        reg_token  = fcm_token(subscription.token)

        req = Net::HTTP::Post.new(uri)
        req['Authorization'] = "Bearer #{access_token}"
        req['Content-Type']  = 'application/json'
        req.body = build_payload(reg_token, title, body, image, link, actions).to_json

        res = Net::HTTP.start(uri.hostname, uri.port, use_ssl: true) { |http| http.request(req) }
        return if res.code.to_i.between?(200, 299)

        if unregistered?(res)
          subscription.destroy
        else
          Rails.logger.error("FCM error for token #{reg_token}: #{res.code} #{res.body}")
        end
      end

      def build_payload(token, title, body, image, link, actions)
        shared_data = { 'title' => title, 'body' => body, 'icon' => DEFAULT_ICON }
        shared_data['image']   = image           if image.present?
        shared_data['link']    = link            if link.present?
        shared_data['actions'] = actions.to_json if actions.present?

        webpush = { headers: { 'Urgency' => 'high' }, data: shared_data }
        webpush[:fcm_options] = { link: link } if link.present?

        { message: { token: token, data: shared_data, webpush: webpush } }
      end

      def fcm_token(token)
        token.include?('/fcm/send/') ? token.split('/fcm/send/').last : token
      end

      def unregistered?(res)
        body = JSON.parse(res.body)
        body.dig('error', 'details')&.any? { |d| d['errorCode'] == 'UNREGISTERED' }
      rescue JSON::ParserError
        false
      end
  end
end
