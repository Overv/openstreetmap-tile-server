FROM ubuntu:18.04

# Based on
# https://switch2osm.org/manually-building-a-tile-server-18-04-lts/

# Set up environment
ENV TZ=UTC
ENV AUTOVACUUM=on
ENV UPDATES=disabled
ENV RENDERERAPP=renderd
RUN ln -snf /usr/share/zoneinfo/$TZ /etc/localtime && echo $TZ > /etc/timezone

# Install dependencies
RUN echo "deb [ allow-insecure=yes ] http://apt.postgresql.org/pub/repos/apt/ bionic-pgdg main" >> /etc/apt/sources.list.d/pgdg.list \
  && apt-get update \
  && apt-get install -y apt-transport-https ca-certificates \
  && apt-get install -y --no-install-recommends --allow-unauthenticated \
  apache2 \
  apache2-dev \
  autoconf \
  build-essential \
  bzip2 \
  cmake \
  fonts-noto-cjk \
  fonts-noto-hinted \
  fonts-noto-unhinted \
  clang \
  gdal-bin \
  git-core \
  libagg-dev \
  libboost-all-dev \
  libbz2-dev \
  libcairo-dev \
  libcairomm-1.0-dev \
  libexpat1-dev \
  libfreetype6-dev \
  libgdal-dev \
  libgeos++-dev \
  libgeos-dev \
  libgeotiff-epsg \
  libicu-dev \
  liblua5.3-dev \
  libmapnik-dev \
  libpq-dev \
  libproj-dev \
  libprotobuf-c0-dev \
  libtiff5-dev \
  libtool \
  libxml2-dev \
  lua5.3 \
  make \
  mapnik-utils \
  nodejs \
  npm \
  postgis \
  postgresql-10 \
  postgresql-10-postgis-2.5 \
  postgresql-10-postgis-2.5-scripts \
  postgresql-contrib-10 \
  protobuf-c-compiler \
  python-mapnik \
  sudo \
  tar \
  ttf-unifont \
  unzip \
  wget \
  zlib1g-dev \
  osmosis \
  osmium-tool \
  cron \
  python3-psycopg2 python3-shapely python3-lxml \
  libipc-sharelite-perl libjson-perl libgd-gd2-perl libwww-perl devscripts \
  nano mc psmisc \
&& apt-get clean autoclean \
&& apt-get autoremove --yes \
&& rm -rf /var/lib/{apt,dpkg,cache,log}

# Set up renderer user
RUN adduser --disabled-password --gecos "" renderer
USER renderer

# Install latest osm2pgsql
RUN mkdir /home/renderer/src
WORKDIR /home/renderer/src
RUN git clone https://github.com/openstreetmap/osm2pgsql.git
WORKDIR /home/renderer/src/osm2pgsql
RUN mkdir build
WORKDIR /home/renderer/src/osm2pgsql/build
RUN cmake .. \
  && make -j $(nproc)
USER root
RUN make install
RUN mkdir /nodes \
    && chown renderer:renderer /nodes
USER renderer

# Install and test Mapnik
RUN python -c 'import mapnik'

# Install mod_tile and renderd
WORKDIR /home/renderer/src
RUN git clone -b switch2osm https://github.com/SomeoneElseOSM/mod_tile.git
WORKDIR /home/renderer/src/mod_tile
RUN ./autogen.sh \
  && ./configure \
  && make -j $(nproc)
USER root
RUN make -j $(nproc) install \
  && make -j $(nproc) install-mod_tile \
  && ldconfig
USER renderer

# Configure stylesheet
WORKDIR /home/renderer/src
RUN git clone https://github.com/gravitystorm/openstreetmap-carto.git \
 && git -C openstreetmap-carto checkout v4.23.0
WORKDIR /home/renderer/src/openstreetmap-carto
USER root
RUN npm install -g carto@0.18.2
USER renderer
RUN carto project.mml > mapnik.xml

# Load shapefiles
WORKDIR /home/renderer/src/openstreetmap-carto
RUN scripts/get-shapefiles.py

# Configure renderd
USER root
RUN sed -i 's/renderaccount/renderer/g' /usr/local/etc/renderd.conf \
  && sed -i 's/hot/tile/g' /usr/local/etc/renderd.conf
USER renderer

# Configure Apache
USER root
RUN mkdir /var/lib/mod_tile \
  && chown renderer /var/lib/mod_tile \
  && mkdir /var/run/renderd \
  && chown renderer /var/run/renderd
RUN echo "LoadModule tile_module /usr/lib/apache2/modules/mod_tile.so" >> /etc/apache2/conf-available/mod_tile.conf \
    && echo "LoadModule headers_module /usr/lib/apache2/modules/mod_headers.so" >> /etc/apache2/conf-available/mod_headers.conf \
  && a2enconf mod_tile && a2enconf mod_headers
COPY apache.conf /etc/apache2/sites-available/000-default.conf
COPY leaflet-demo.html /var/www/html/index.html
RUN ln -sf /dev/stdout /var/log/apache2/access.log \
  && ln -sf /dev/stderr /var/log/apache2/error.log

# Configure PosgtreSQL
COPY postgresql.custom.conf.tmpl /etc/postgresql/10/main/
RUN chown -R postgres:postgres /var/lib/postgresql \
  && chown postgres:postgres /etc/postgresql/10/main/postgresql.custom.conf.tmpl \
  && echo "\ninclude 'postgresql.custom.conf'" >> /etc/postgresql/10/main/postgresql.conf
RUN echo "host all all 0.0.0.0/0 md5" >> /etc/postgresql/10/main/pg_hba.conf \
      && echo "host all all ::/0 md5" >> /etc/postgresql/10/main/pg_hba.conf

# copy update scripts
COPY openstreetmap-tiles-update-expire /usr/bin/
RUN chmod +x /usr/bin/openstreetmap-tiles-update-expire \
    && mkdir /var/log/tiles \
    && chmod a+rw /var/log/tiles \
    && ln -s /home/renderer/src/mod_tile/osmosis-db_replag /usr/bin/osmosis-db_replag \
    && echo "*  *    * * *   renderer    openstreetmap-tiles-update-expire\n" >> /etc/crontab

# install trim_osc.py helper script
USER renderer
RUN cd ~/src \
    && git clone https://github.com/zverik/regional \
    && cd regional \
    && git checkout 612fe3e040d8bb70d2ab3b133f3b2cfc6c940520 \
    && chmod u+x ~/src/regional/trim_osc.py

# clone, build and install tirex
# according to fpllowing wiki article:
#   https://wiki.openstreetmap.org/wiki/Tirex/Building_and_Installing
USER renderer
WORKDIR /home/renderer/src
RUN git clone https://github.com/openstreetmap/tirex.git \
 && git -C tirex checkout v0.6.1
WORKDIR /home/renderer/src/tirex
RUN make

USER root
RUN make install
RUN  mkdir /var/lib/tirex \
  && mkdir /var/log/tirex \
  && mkdir /var/run/tirex \
  && mkdir /var/lib/mod_tile/ajx \
  && chown renderer:renderer /var/lib/tirex \
  && chown renderer:renderer /var/run/tirex \
  && chown renderer:renderer /var/log/tirex \
  && chown renderer /var/lib/mod_tile/ajx

COPY ajt.conf /etc/tirex/renderer/mapnik/
COPY mapnik.conf /etc/tirex/renderer/
COPY tirex.conf /etc/tirex/tirex.conf

RUN ln -s /var/lib/mod_tile  /var/lib/tirex/tiles

# remove not required tirex sample renderer and maps
RUN  rm -fr /etc/tirex/renderer/openseamap \
	&& rm -fr /etc/tirex/renderer/wms \
	&& rm -fr /etc/tirex/renderer/mapserver \
	&& rm -fr /etc/tirex/renderer/openseamap.conf \
	&& rm -fr /etc/tirex/renderer/wms.conf \
	&& rm -fr /etc/tirex/renderer/mapserver.conf

# Start running
USER root
COPY run.sh /
COPY indexes.sql /
ENTRYPOINT ["/run.sh"]
CMD []

EXPOSE 80 5432
