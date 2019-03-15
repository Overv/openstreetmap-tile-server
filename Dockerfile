FROM ubuntu:18.04

# Based on
# https://switch2osm.org/manually-building-a-tile-server-18-04-lts/

# Set up environment
ENV TZ=UTC
RUN ln -snf /usr/share/zoneinfo/$TZ /etc/localtime && echo $TZ > /etc/timezone

# Install dependencies
RUN echo "deb [ allow-insecure=yes ] http://apt.postgresql.org/pub/repos/apt/ bionic-pgdg main" >> /etc/apt/sources.list.d/pgdg.list \
  && apt-get update \
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
  postgresql-10-postgis-2.4 \
  postgresql-contrib-10 \
  protobuf-c-compiler \
  python-mapnik \
  sudo \
  tar \
  ttf-unifont \
  unzip \
  wget \
  zlib1g-dev \
&& apt-get clean autoclean \
&& apt-get autoremove --yes \
&& rm -rf /var/lib/{apt,dpkg,cache,log}/

# Set up renderer user
RUN adduser --disabled-password --gecos "" renderer
USER renderer

ENV GIT_SSL_NO_VERIFY=true

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
RUN git clone https://github.com/gravitystorm/openstreetmap-carto.git
WORKDIR /home/renderer/src/openstreetmap-carto
USER root
RUN npm config set strict-ssl=false \
  && npm install -g carto
USER renderer
RUN carto project.mml > mapnik.xml

# Load shapefiles
WORKDIR /home/renderer/src/openstreetmap-carto
ENV PYTHONHTTPSVERIFY=0
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
  && a2enconf mod_tile
COPY apache.conf /etc/apache2/sites-available/000-default.conf
COPY leaflet-demo.html /var/www/html/index.html
RUN ln -sf /proc/1/fd/1 /var/log/apache2/access.log \
  && ln -sf /proc/1/fd/2 /var/log/apache2/error.log

# Configure PosgtreSQL
RUN chown -R postgres:postgres /var/lib/postgresql

# Start running
COPY run.sh /
ENTRYPOINT ["/run.sh"]
CMD []

EXPOSE 80 5432
