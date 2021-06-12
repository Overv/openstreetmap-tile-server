#!/bin/bash

set -x

docker run --rm  \
  -v /${CWD}://tmp  \
  -v openstreetmap-data://var/lib/postgresql/12/main  \
  -w //tmp  \
  postgis/postgis:12-3.1 \
  pg_dumpall -c -v -U prostgres > dump.sql

docker run --rm  \
  -v /${CWD}://tmp  \
  -v openstreetmap-data://var/lib/postgresql/13/main  \
  -w //tmp  \
  postgis/postgis:13-3.1  \
  psql -U postgres -d gis < dump.sql
  
sudo -u postgres psql -d gis -c "SELECT PostGIS_Extensions_Upgrade();"

rm ./dump.sql
