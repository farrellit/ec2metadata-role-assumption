FROM alpine:3.4

ENV BUILD_PACKAGES ca-certificates ruby-dev build-base
ENV RUBY_PACKAGES ruby ruby-bundler
ENV PYTHON_PACKAGES python py-virtualenv
# Update and install base packages
RUN apk update && apk upgrade && \
    apk add $BUILD_PACKAGES && \
    apk add $RUBY_PACKAGES && \
    apk add $PYTHON_PACKAGES && \
    rm -rf /var/cache/apk/*

ADD ./Gemfile /code/Gemfile
ADD ./Gemfile.lock /code/Gemfile.lock

WORKDIR /code
RUN bundle install
ADD . /code

RUN virtualenv /virtualenv
RUN /virtualenv/bin/pip install awscli

ENV PATH="/virtualenv/bin:${PATH}"
CMD bundle exec ruby ./ec2metadata.rb
