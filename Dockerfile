# syntax=docker/dockerfile:1
FROM ruby:3.3.0
WORKDIR /app
COPY . .

RUN apt-get -y update
RUN apt-get -y upgrade
RUN apt-get install -y sqlite3 libsqlite3-dev

RUN bundle install

ENV LYRICAT_DATA_DIR=/data
ENV LYRICAT_RES_DIR=/res

ENTRYPOINT [ "/app/main.rb" ]
