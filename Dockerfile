FROM ubuntu:latest

RUN apt-get update && apt-get install -y ruby-full build-essential zlib1g-dev \
  && rm -rf /var/lib/dpkg

RUN gem install jekyll bundler

EXPOSE 35729
EXPOSE 4000