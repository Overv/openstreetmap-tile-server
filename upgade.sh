#!/bin/bash

set -x

docker run --rm -v ${CWD}:/tmp -v openstreetmap-data:/var/lib/postgresql/12/main -w /tmp overv/openstreetmap-tile-server pg_dumpall -U prostgres > dump.sql

docker run --rm -v ${CWD}:/tmp -v openstreetmap-data:/var/lib/postgresql/13/main -w /tmp overv/openstreetmap-tile-server:2.0.0 psql -U postgres -d gis  < dump.sql
