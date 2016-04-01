FROM rapi/rapidapp:1.1007
MAINTAINER Henry Van Styn <vanstyn@cpan.org>

# Install some misc useful Plack packages:
RUN cpanm \
 Plack::Middleware::Headers \
 Plack::Middleware::TemplateToolkit \
&& rm -rf .cpanm/

RUN mkdir -p /opt/app
VOLUME       /opt/app
WORKDIR      /opt/app

# Extra mountable directory for misc/dev use
RUN mkdir -p /opt/misc
VOLUME       /opt/misc

EXPOSE 3000
EXPOSE 3500
EXPOSE 5000

COPY prepare_and_plackup.pl /

# Alias/symlink to allow calling different commands using `docker run ...`
RUN ln -sf /prepare_and_plackup.pl /bin/via-git

# env flag used by CMD script to prevent running except from here
ENV RAPI_PSGI_DOCKERIZED 1

CMD /prepare_and_plackup.pl
