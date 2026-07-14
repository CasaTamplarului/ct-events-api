# frozen_string_literal: true

require 'spec_helper'

ENV['RAILS_ENV'] ||= 'test'
require File.expand_path('../config/environment', __dir__)
abort('The Rails environment is running in production mode!') if Rails.env.production?
require 'rspec/rails'
require 'webmock/rspec'
# require 'stripe_mock'

Dir['./spec/support/**/*.rb'].each { |f| require f }

begin
  ActiveRecord::Migration.maintain_test_schema!
rescue ActiveRecord::PendingMigrationError
  exit 1
end

RSpec.configure do |config|
  config.use_transactional_fixtures = true
  config.infer_spec_type_from_file_location!
  config.filter_rails_from_backtrace!
  config.include FactoryBot::Syntax::Methods
  config.include RequestSpecHelper, type: :request
  config.include ActionCable::TestHelper
  config.after do
    I18n.locale = I18n.default_locale
    Faker::UniqueGenerator.clear
    DatabaseCleaner.clean
  end

  config.before(:suite) do
    DatabaseCleaner.clean_with(:truncation)
  end

  config.before do
    WebMock.globally_stub_request(:after_local_stubs) do |request|
      { status: 200, body: '{}', headers: {} } if /fonts.googleapis.com|fcm.googleapis.com/.match?(request.uri.to_s)
    end
    DatabaseCleaner.start
    Rack::Attack.cache.store = ActiveSupport::Cache::MemoryStore.new
  end
end

Shoulda::Matchers.configure do |config|
  config.integrate do |with|
    with.test_framework :rspec
    with.library :rails
  end
end
