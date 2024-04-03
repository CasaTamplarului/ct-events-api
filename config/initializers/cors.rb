# frozen_string_literal: true

Rails.application.config.middleware.insert_before 0, Rack::Cors do
  allow do
    origins '*'

    resource '*',
             headers: :any,
             methods: %i[get post put patch delete options head],
             expose: %w[X-total X-per-page x-current-page]
  end
end
