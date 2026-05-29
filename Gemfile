source "https://rubygems.org"
git_source(:github) { |repo| "https://github.com/#{repo}.git" }

ruby "3.4.2"

# Core
gem "bootsnap", require: false
gem "bcrypt", "~> 3.1"
gem "rails", "~> 8.0"
gem "pg", "~> 1.1"
gem "puma", ">= 6.4.2"
gem "rack-cors"

# Error notifier
gem "sentry-ruby", "~> 5.22"
gem "sentry-rails", "~> 5.22"

# Serialization
gem 'alba', '~> 3.1'
gem 'oj'

# Google Sign-In
gem 'google-id-token', '~> 1.4'
gem 'jwt', '~> 2.8'

# Windows does not include zoneinfo files, so bundle the tzinfo-data gem
gem "tzinfo-data", platforms: %i[ mingw mswin x64_mingw jruby ]

# Configuration
gem 'dotenv-rails'

# Documentation
gem 'apipie-rails', '~> 1.4'

group :development, :test do
  gem "debug"
  gem 'database_cleaner', '~> 2.0'
  gem 'rspec-rails', '~> 7.0'
  gem 'factory_bot_rails', '~> 6.2'
  gem 'faker', '~> 3.2'
  gem 'shoulda-matchers', '~> 6.0'
  gem 'webmock', '~> 3.18'
end

group :development do
  gem 'rubocop', '~> 1.70', require: false
  gem 'rubocop-rails', '~> 2.27', require: false
  gem 'rubocop-rspec', '~> 3.0', require: false
  gem 'rubocop-performance', '~> 1.23', require: false
  gem "web-console"
  gem 'bundler-audit'
end

group :test do
  gem "selenium-webdriver", ">= 4.11"
end
