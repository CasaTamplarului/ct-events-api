# frozen_string_literal: true

Apipie.configure do |config|
  config.app_name                = 'CT Events'
  config.api_base_url            = '/api'
  config.doc_base_url            = '/apipie'
  config.translate               = false
  config.api_controllers_matcher = Rails.root.join('app/controllers/**/*.rb')
  config.show_all_examples       = true
  config.namespaced_resources    = true
  config.authenticate = proc do
    authenticate_or_request_with_http_basic do |username, password|
      username == Credentials[:apipie][:username] && password == Credentials[:apipie][:password]
    end
  end
end
