FROM ruby:latest
RUN apt-get update
# RUN apt-get install -y  python-pip python-dev
# RUN pip install --upgrade awscli
ADD ./Gemfile /code/Gemfile
WORKDIR /code
RUN bundle install
ADD . /code
CMD bundle exec ruby ./ec2metadata.rb
