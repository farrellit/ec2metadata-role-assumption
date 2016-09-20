FROM ruby:2.1
RUN apt-get update
RUN apt-get install -y  awscli
ADD . /code
WORKDIR /code
RUN bundle install
CMD bundle exec ruby ./ec2metadata.rb
