FROM ruby:3.1.3
RUN gem install jekyll bundler jekyll-paginate-v2
WORKDIR /svr/jekyll