FROM ubuntu:22.04 AS compiler-common
ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update \
&& apt-get install -y --no-install-recommends \
 git-core \
 checkinstall \
 g++ \
 gnupg2 \
 make \
 tar \
 wget \
 ca-certificates \
&& apt-get update

###########################################################################################################

FROM compiler-common AS compiler-postgis
RUN apt-get update \
&& apt-get install -y --no-install-recommends \
 postgresql-server-dev-14 \
 libxml2-dev \
 libgeos-dev \
 libproj-dev \
&& wget https://download.osgeo.org/postgis/source/postgis-3.2.1.tar.gz -O postgis.tar.gz \
&& mkdir -p postgis_src \
&& tar -xvzf postgis.tar.gz --strip 1 -C postgis_src \
&& rm postgis.tar.gz \
&& cd postgis_src \
&& ./configure --without-protobuf --without-raster \
&& make -j $(nproc) \
&& checkinstall --pkgversion="3.2.1" --install=no --default make install

###########################################################################################################

FROM compiler-common AS compiler-osm2pgsql
RUN apt-get install -y --no-install-recommends \
 cmake \
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
 pandoc
RUN cd ~ \
&& git clone -b master --single-branch https://github.com/openstreetmap/osm2pgsql.git --depth 1 \
&& cd osm2pgsql \
&& mkdir build \
&& cd build \
&& cmake .. \
&& make -j $(nproc) \
&& checkinstall --pkgversion="1" --install=no --default make install

###########################################################################################################

FROM compiler-common AS compiler-modtile-renderd
RUN apt-get install -y --no-install-recommends \
 apache2-dev \
 automake \
 autoconf \
 autotools-dev \
 libtool \
 libmapnik-dev
RUN cd ~ \
&& git clone --single-branch https://github.com/openstreetmap/mod_tile.git --depth 1 \
&& cd mod_tile \
&& ./autogen.sh \
&& ./configure \
&& make -j $(nproc) \
&& checkinstall --pkgversion="1" --install=no --pkgname "renderd" --default make install \
&& checkinstall --pkgversion="1" --install=no --pkgname "mod_tile" --default make install-mod_tile

###########################################################################################################

FROM compiler-common AS compiler-stylesheet
RUN cd ~ \
&& git clone --single-branch --branch v5.4.0 https://github.com/gravitystorm/openstreetmap-carto.git --depth 1 \
&& cd openstreetmap-carto \
&& rm -rf .git

###########################################################################################################

FROM compiler-common AS compiler-helper-script
RUN mkdir -p /home/renderer/src \
&& cd /home/renderer/src \
&& git clone https://github.com/zverik/regional \
&& cd regional \
&& rm -rf .git \
&& chmod u+x /home/renderer/src/regional/trim_osc.py

###########################################################################################################

FROM ubuntu:22.04 AS final

# Based on
# https://switch2osm.org/serving-tiles/manually-building-a-tile-server-18-04-lts/
ENV DEBIAN_FRONTEND=noninteractive
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
 fonts-unifont \
 gnupg2 \
 gdal-bin \
 liblua5.3-dev \
 lua5.3 \
 mapnik-utils \
 npm \
 osmium-tool \
 osmosis \
 postgresql-14 \
 python-is-python3 \
 python3-mapnik \
 python3-lxml \
 python3-psycopg2 \
 python3-shapely \
 python3-pip \
 sudo \
 wget \
&& apt-get clean autoclean \
&& apt-get autoremove --yes \
&& rm -rf /var/lib/{apt,dpkg,cache,log}/

RUN adduser --disabled-password --gecos "" renderer

# Install python libraries
RUN pip3 install \
 requests \
 osmium \
 pyyaml

# Install carto for stylesheet
RUN npm install -g carto@0.18.2

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

# Copy update scripts
COPY openstreetmap-tiles-update-expire.sh /usr/bin/
RUN chmod +x /usr/bin/openstreetmap-tiles-update-expire.sh \
&& mkdir /var/log/tiles \
&& chmod a+rw /var/log/tiles \
&& ln -s /home/renderer/src/mod_tile/osmosis-db_replag /usr/bin/osmosis-db_replag \
&& echo "* * * * *   renderer    openstreetmap-tiles-update-expire.sh\n" >> /etc/crontab

# Configure PosgtreSQL
COPY postgresql.custom.conf.tmpl /etc/postgresql/14/main/
RUN chown -R postgres:postgres /var/lib/postgresql \
&& chown postgres:postgres /etc/postgresql/14/main/postgresql.custom.conf.tmpl \
&& echo "host all all 0.0.0.0/0 md5" >> /etc/postgresql/14/main/pg_hba.conf \
&& echo "host all all ::/0 md5" >> /etc/postgresql/14/main/pg_hba.conf

# Create volume directories
RUN   mkdir  -p  /data/database/  \
  &&  mkdir  -p  /data/style/  \
  &&  mkdir  -p  /home/renderer/src/  \
  &&  chown  -R  renderer:  /data/  \
  &&  chown  -R  renderer:  /home/renderer/src/  \
  &&  mv  /var/lib/postgresql/14/main/  /data/database/postgres/  \
  &&  mv  /var/lib/mod_tile/            /data/tiles/     \
  &&  ln  -s  /data/database/postgres  /var/lib/postgresql/14/main             \
  &&  ln  -s  /data/style              /home/renderer/src/openstreetmap-carto  \
  &&  ln  -s  /data/tiles              /var/lib/mod_tile                       \
;

# Install PostGIS
COPY --from=compiler-postgis postgis_src/postgis-src_3.2.1-1_amd64.deb .
RUN dpkg -i postgis-src_3.2.1-1_amd64.deb \
&& rm postgis-src_3.2.1-1_amd64.deb

# Install osm2pgsql
COPY --from=compiler-osm2pgsql /root/osm2pgsql/build/build_1-1_amd64.deb .
RUN dpkg -i build_1-1_amd64.deb \
&& rm build_1-1_amd64.deb

# Install renderd
COPY --from=compiler-modtile-renderd /root/mod_tile/renderd_1-1_amd64.deb .
RUN dpkg -i renderd_1-1_amd64.deb \
&& rm renderd_1-1_amd64.deb \
&& sed -i 's/renderaccount/renderer/g' /usr/local/etc/renderd.conf \
&& sed -i 's/\/truetype//g' /usr/local/etc/renderd.conf \
&& sed -i 's/hot/tile/g' /usr/local/etc/renderd.conf

# Install mod_tile
COPY --from=compiler-modtile-renderd /root/mod_tile/mod-tile_1-1_amd64.deb .
RUN dpkg -i mod-tile_1-1_amd64.deb \
 && ldconfig \
 && rm mod-tile_1-1_amd64.deb

COPY --from=compiler-modtile-renderd /root/mod_tile/osmosis-db_replag /usr/bin/osmosis-db_replag

# Install helper script
COPY --from=compiler-helper-script /home/renderer/src/regional /home/renderer/src/regional

COPY --from=compiler-stylesheet /root/openstreetmap-carto /home/renderer/src/openstreetmap-carto-backup

# Start running
COPY run.sh /
ENTRYPOINT ["/run.sh"]
CMD []
EXPOSE 80 5432
