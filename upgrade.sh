#!/bin/bash

set -x

docker run --rm  \
  -v /${CWD}://tmp  \
  -v openstreetmap-data://var/lib/postgresql/12/main  \
  -w //tmp  \
  postgres:12 \
  pg_dumpall -c -v -U prostgres > dump.sql

docker run --rm  \
  -v /${CWD}://tmp  \
  -v openstreetmap-data://var/lib/postgresql/13/main  \
  -w //tmp  \
  postgres:13  \
  psql -U postgres -d gis < dump.sql

rm ./dump.sql
