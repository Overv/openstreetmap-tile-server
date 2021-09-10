FROM ubuntu:20.04 AS compiler

# Based on
# https://switch2osm.org/serving-tiles/manually-building-a-tile-server-18-04-lts/
ENV TZ=UTC
ENV AUTOVACUUM=on
ENV UPDATES=disabled
RUN ln -snf /usr/share/zoneinfo/$TZ /etc/localtime && echo $TZ > /etc/timezone

# Install dependencies
RUN apt-get update \
&& apt-get install -y --no-install-recommends \
  # Common
  git-core \
  checkinstall \
  make \
  tar \
  wget \
  # Compile postgis
  postgresql-server-dev-12 \
  # Compile osm2pgsql
  cmake \
  g++ \
  libboost-dev \
  libboost-system-dev \
  libboost-filesystem-dev \
  libexpat1-dev \
  zlib1g-dev \
  libbz2-dev \
  libpq-dev \
  libproj-dev \
  lua5.3 \
  liblua5.3-dev \
  pandoc \
  # Compile mod_tile and renderd
  apache2-dev \
  automake \
  autoconf \
  autotools-dev \
  libtool \
  libmapnik-dev \
  # Configure stylesheet
  npm

# Set up PostGIS
RUN wget https://download.osgeo.org/postgis/source/postgis-3.1.1.tar.gz -O postgis.tar.gz \
 && mkdir -p postgis_src \
 && tar -xvzf postgis.tar.gz --strip 1 -C postgis_src \
 && rm postgis.tar.gz \
 && cd postgis_src \
 && ./configure --without-protobuf \
 && make -j $(nproc) \
 && checkinstall --pkgversion="3.1.1" --install=no --default make install

# Install latest osm2pgsql
RUN cd ~ \
 && git clone -b master --single-branch https://github.com/openstreetmap/osm2pgsql.git --depth 1 \
 && cd osm2pgsql \
 && mkdir build \
 && cd build \
 && cmake .. \
 && make -j $(nproc) \
 && checkinstall --pkgversion="1" --install=no --default make install

# Install mod_tile and renderd
RUN cd ~ \
 && git clone -b switch2osm --single-branch https://github.com/SomeoneElseOSM/mod_tile.git --depth 1 \
 && cd mod_tile \
 && ./autogen.sh \
 && ./configure \
 && make -j $(nproc) \
 && checkinstall --pkgversion="1" --install=no --pkgname "renderd" --default make install \
 && checkinstall --pkgversion="1" --install=no --pkgname "mod_tile" --default make install-mod_tile

# Configure stylesheet
RUN cd ~ \
 && git clone --single-branch --branch v5.3.1 https://github.com/gravitystorm/openstreetmap-carto.git --depth 1 \
 && cd openstreetmap-carto \
 && npm install -g carto@0.18.2 \
 && carto project.mml > mapnik.xml

###########################################################################################################

FROM ubuntu:20.04

# Based on
# https://switch2osm.org/serving-tiles/manually-building-a-tile-server-18-04-lts/
ENV TZ=UTC
ENV AUTOVACUUM=on
ENV UPDATES=disabled
RUN ln -snf /usr/share/zoneinfo/$TZ /etc/localtime && echo $TZ > /etc/timezone

# Get packages
RUN apt-get update \
&& apt-get install -y --no-install-recommends \
  apache2 \
  cron \
  fonts-noto-cjk \
  fonts-noto-hinted \
  fonts-noto-unhinted \
  gdal-bin \
  git-core \
  liblua5.3-dev \
  lua5.3 \
  mapnik-utils \
  osmium-tool \
  osmosis \
  postgresql-12 \
  postgresql-contrib-12 \
  python-is-python3 \
  python3-mapnik \
  python3-lxml \
  python3-psycopg2 \
  python3-shapely \
  python3-pip \
  sudo \
  ttf-unifont \
  wget \
&& apt-get clean autoclean \
&& apt-get autoremove --yes \
&& rm -rf /var/lib/{apt,dpkg,cache,log}/

RUN adduser --disabled-password --gecos "" renderer \
&& mkdir -p /home/renderer/src

# Install python libraries
RUN pip3 install \
 requests \
 pyyaml

# Configure Apache
RUN mkdir /var/lib/mod_tile \
 && chown renderer /var/lib/mod_tile \
 && mkdir /var/run/renderd \
 && chown renderer /var/run/renderd \
 && echo "LoadModule tile_module /usr/lib/apache2/modules/mod_tile.so" >> /etc/apache2/conf-available/mod_tile.conf \
 && echo "LoadModule headers_module /usr/lib/apache2/modules/mod_headers.so" >> /etc/apache2/conf-available/mod_headers.conf \
 && a2enconf mod_tile && a2enconf mod_headers
COPY apache.conf /etc/apache2/sites-available/000-default.conf
COPY leaflet-demo.html /var/www/html/index.html
RUN ln -sf /dev/stdout /var/log/apache2/access.log \
 && ln -sf /dev/stderr /var/log/apache2/error.log

# Configure PosgtreSQL
COPY postgresql.custom.conf.tmpl /etc/postgresql/12/main/
RUN chown -R postgres:postgres /var/lib/postgresql \
 && chown postgres:postgres /etc/postgresql/12/main/postgresql.custom.conf.tmpl \
 && echo "host all all 0.0.0.0/0 md5" >> /etc/postgresql/12/main/pg_hba.conf \
 && echo "host all all ::/0 md5" >> /etc/postgresql/12/main/pg_hba.conf

# Install PostGIS
COPY --from=compiler postgis_src/postgis-src_3.1.1-1_amd64.deb .
RUN dpkg -i postgis-src_3.1.1-1_amd64.deb

# Install osm2pgsql
COPY --from=compiler /root/osm2pgsql/build/build_1-1_amd64.deb .
RUN dpkg -i build_1-1_amd64.deb 

COPY --from=compiler /root/mod_tile/renderd_1-1_amd64.deb .
RUN dpkg -i renderd_1-1_amd64.deb

# Install mod_tile
COPY --from=compiler /root/mod_tile/mod-tile_1-1_amd64.deb .
RUN dpkg -i mod-tile_1-1_amd64.deb && ldconfig

# Install stylesheet
COPY --from=compiler /root/openstreetmap-carto /home/renderer/src/openstreetmap-carto

# Configure renderd
RUN sed -i 's/renderaccount/renderer/g' /usr/local/etc/renderd.conf \
 && sed -i 's/\/truetype//g' /usr/local/etc/renderd.conf \
 && sed -i 's/hot/tile/g' /usr/local/etc/renderd.conf

# Copy update scripts
COPY openstreetmap-tiles-update-expire /usr/bin/
RUN chmod +x /usr/bin/openstreetmap-tiles-update-expire \
 && mkdir /var/log/tiles \
 && chmod a+rw /var/log/tiles \
 && ln -s /home/renderer/src/mod_tile/osmosis-db_replag /usr/bin/osmosis-db_replag \
 && echo "* * * * *   renderer    openstreetmap-tiles-update-expire\n" >> /etc/crontab

# Install trim_osc.py helper script
RUN cd /home/renderer/src \
 && git clone https://github.com/zverik/regional \
 && cd regional \
 && git checkout 889d630a1e1a1bacabdd1dad6e17b49e7d58cd4b \
 && rm -rf .git \
 && chmod u+x /home/renderer/src/regional/trim_osc.py

RUN mkdir /nodes \
 && chown renderer:renderer /nodes

# Start running
COPY run.sh /
ENTRYPOINT ["/run.sh"]
CMD []
EXPOSE 80 5432
