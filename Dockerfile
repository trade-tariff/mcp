ARG RUBY_VERSION=4.0.5
ARG ALPINE_VERSION=3.23

FROM ruby:${RUBY_VERSION}-alpine${ALPINE_VERSION} AS builder

WORKDIR /app

RUN apk add \
  --update \
  --no-cache \
  build-base \
  git \
  libyaml-dev \
  tzdata \
  && \
  cp /usr/share/zoneinfo/Europe/London /etc/localtime && \
  echo "Europe/London" > /etc/timezone

RUN bundle config set without 'development test'
COPY .ruby-version Gemfile Gemfile.lock /app/
RUN bundle install --jobs=4 --no-binstubs

COPY . /app/

RUN rm -rf log tmp && \
  rm -rf /usr/local/bundle/cache && \
  rm -rf .env && \
  find /usr/local/bundle/gems -name "*.c" -delete && \
  find /usr/local/bundle/gems -name "*.h" -delete && \
  find /usr/local/bundle/gems -name "*.o" -delete && \
  find /usr/local/bundle/gems -name "*.html" -delete

FROM ruby:${RUBY_VERSION}-alpine${ALPINE_VERSION} AS production

RUN apk add --no-cache \
    bash \
    netcat-openbsd \
    tzdata && \
    cp /usr/share/zoneinfo/Europe/London /etc/localtime && \
    echo "Europe/London" > /etc/timezone

RUN bundle config set without 'development test'

WORKDIR /app

ENV RAILS_ENV=production \
  RUBYOPT="--enable-yjit" \
  MALLOC_ARENA_MAX="2"

COPY --from=builder /app/ /app
COPY --from=builder /usr/local/bundle/ /usr/local/bundle/

RUN bundle config set without 'development test'

RUN addgroup -S tariff && \
  adduser -S tariff -G tariff && \
  chown -R tariff:tariff /app && \
  chown -R tariff:tariff /usr/local/bundle

HEALTHCHECK CMD nc -z 0.0.0.0 $SSL_PORT

USER tariff

CMD ["bundle", "exec", "puma", "-C", "config/puma.rb"]
