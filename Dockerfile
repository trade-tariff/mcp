ARG RUBY_VERSION=4.0.6
ARG ALPINE_VERSION=3.24

FROM ruby:${RUBY_VERSION}-alpine${ALPINE_VERSION} AS builder

WORKDIR /app

RUN apk add \
  --update \
  --no-cache \
  build-base \
  git \
  openssl-dev \
  yaml-dev \
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
  find /usr/local/bundle/gems -name "*.html" -delete && \
  find /usr/local/bundle/gems -maxdepth 2 -name "Gemfile.lock" -delete && \
  find /usr/local/bundle/gems -maxdepth 2 -name "Gemfile" -delete

FROM ruby:${RUBY_VERSION}-alpine${ALPINE_VERSION} AS production

RUN apk add --no-cache \
    bash \
    netcat-openbsd \
    openssl \
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

# The base Ruby image bundles its own copies of some gems (json as a
# default gem, net-imap as a regular pre-installed gem) that can lag
# behind the versions pinned in Gemfile.lock and get flagged by scanners
# even though the app never loads them: it always boots via `bundle exec`,
# which activates the Bundler-installed gem instead. json's default gem
# also leaves an empty "gems/json-<version>" stub directory behind (a
# RubyGems bookkeeping artifact for default gems) that some scanners key
# off by directory name alone, independent of the gemspec, so it has to
# be removed explicitly rather than relying on gem uninstall.
RUN find /usr/local/lib/ruby/gems -path "*/specifications/default/json-*.gemspec" -delete && \
  find /usr/local/lib/ruby -maxdepth 2 -name "json.rb" -delete && \
  find /usr/local/lib/ruby -maxdepth 2 -type d -name "json" -exec rm -rf {} + && \
  find /usr/local/lib/ruby/gems -maxdepth 3 -type d -name "json-*" -exec rm -rf {} + && \
  find /usr/local/lib/ruby/gems -path "*/extensions/*/json-*" -exec rm -rf {} + && \
  gem uninstall net-imap --force --ignore-dependencies --executables --all \
    --install-dir /usr/local/lib/ruby/gems/4.0.0 2>/dev/null || true

RUN addgroup -S tariff && \
  adduser -S tariff -G tariff && \
  chown -R tariff:tariff /app && \
  chown -R tariff:tariff /usr/local/bundle

HEALTHCHECK CMD nc -z 0.0.0.0 $SSL_PORT

USER tariff

CMD ["bundle", "exec", "puma", "-C", "config/puma.rb"]
