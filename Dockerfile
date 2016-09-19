FROM ruby:2.1-onbuild
ADD . /code
WORKDIR /code
RUN apt-get update
RUN apt-get install -y  awscli
#RUN npm install
RUN bundle install
CMD bundle exec ruby ./ec2metadata.rb
