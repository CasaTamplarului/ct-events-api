source "https://rubygems.org"
git_source(:github) { |repo| "https://github.com/#{repo}.git" }

ruby "3.2.2"

# Core
gem "bootsnap", require: false
gem "rails", "~> 7.0.6"
gem "sprockets-rails"
gem "pg", "~> 1.1"
gem "puma", "~> 5.0"
gem "importmap-rails"
gem "turbo-rails"
gem "stimulus-rails"
gem "jbuilder"

# Error notifier
gem "sentry-ruby"
gem "sentry-rails"

# Windows does not include zoneinfo files, so bundle the tzinfo-data gem
gem "tzinfo-data", platforms: %i[ mingw mswin x64_mingw jruby ]

# Configuration
gem 'dotenv-rails'

# Documentation
gem 'apipie-rails', '~> 1.2', '>= 1.2.2'

group :development, :test do
  gem "byebug"
  gem 'database_cleaner', '~> 2.0', '>= 2.0.2'
  gem 'rspec-rails', '~> 6.0', '>= 6.0.3'
  gem 'factory_bot_rails', '~> 6.2'
  gem 'faker', '~> 3.2'
  gem 'shoulda-matchers', '~> 4.5', '>= 4.5.1'
  gem 'webmock', '~> 3.18', '>= 3.18.1'
end

group :development do
  gem 'rubocop', '~> 1.55', '>= 1.55.1', require: false
  gem 'rubocop-rails', '~> 2.20', '>= 2.20.2', require: false
  gem 'rubocop-rspec', '~> 2.23', require: false
  gem 'rubocop-performance', '~> 1.18', require: false
  gem "web-console"

  # gem "rack-mini-profiler"

  # gem "spring"
end

group :test do
  gem "selenium-webdriver"
  gem "webdrivers"
  gem 'shoulda', '~> 4.0'
end
