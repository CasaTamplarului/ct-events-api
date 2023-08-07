# frozen_string_literal: true
unless Rails.env.in?(%w[development test])
  Sentry.init do |config|
    config.dsn = Credentials[:sentry_dsn]
    config.environment = Rails.env
    config.traces_sample_rate = 1
    config.breadcrumbs_logger = %i[active_support_logger http_logger]
  end
end