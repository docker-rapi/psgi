FROM rapi/rapidapp:1.1005
MAINTAINER Henry Van Styn <vanstyn@cpan.org>

RUN mkdir -p /opt/app
VOLUME       /opt/app
WORKDIR      /opt/app

EXPOSE 5000
CMD start_server --port=5000 -- plackup -s Gazelle
