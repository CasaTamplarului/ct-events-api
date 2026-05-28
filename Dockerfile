FROM ruby:3.4.2-slim

RUN apt-get update -qq && apt-get install -y \
  build-essential \
  libpq-dev \
  libyaml-dev \
  curl \
  && rm -rf /var/lib/apt/lists/*

WORKDIR /app

COPY Gemfile Gemfile.lock ./
RUN bundle config set --local without "development test" && \
    bundle install

COPY . .

RUN bundle exec bootsnap precompile --gemfile app/ lib/

RUN mkdir -p tmp/pids tmp/cache tmp/sockets log

EXPOSE 3000

CMD ["sh", "-c", "bundle exec rails db:migrate && bundle exec puma -C config/puma.rb"]
