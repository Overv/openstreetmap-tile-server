#!/bin/bash

set -x

function CreatePostgressqlConfig()
{
  cp /etc/postgresql/10/main/postgresql.custom.conf.tmpl /etc/postgresql/10/main/postgresql.custom.conf
  sudo -u postgres echo "autovacuum = $AUTOVACUUM" >> /etc/postgresql/10/main/postgresql.custom.conf
  cat /etc/postgresql/10/main/postgresql.custom.conf
}

if [ "$#" -ne 1 ]; then
    echo "usage: <import|run>"
    echo "commands:"
    echo "    import: Set up the database and import /data.osm.pbf"
    echo "    run: Runs Apache and renderd to serve tiles at /tile/{z}/{x}/{y}.png"
    echo "environment variables:"
    echo "    THREADS: defines number of threads used for importing / tile rendering"
    exit 1
fi

if [ "$1" = "import" ]; then
    # Initialize PostgreSQL
    CreatePostgressqlConfig
    service postgresql start
    su postgres << EOSU
    createuser renderer
    createdb -E UTF8 -O renderer gis
    psql -d gis -c "CREATE EXTENSION postgis;"
    psql -d gis -c "CREATE EXTENSION hstore;"
    psql -d gis -c "ALTER TABLE geometry_columns OWNER TO renderer;"
    psql -d gis -c "ALTER TABLE spatial_ref_sys OWNER TO renderer;"
    psql -d gis -c "CREATE INDEX planet_osm_roads_admin ON planet_osm_roads USING GIST (way)
      WHERE boundary = 'administrative';"
    psql -d gis -c "CREATE INDEX planet_osm_roads_roads_ref ON planet_osm_roads USING GIST (way)
      WHERE highway IS NOT NULL AND ref IS NOT NULL;"
    psql -d gis -c "CREATE INDEX planet_osm_roads_admin_low ON planet_osm_roads USING GIST (way)
      WHERE boundary = 'administrative' AND admin_level IN ('0', '1', '2', '3', '4');"
    psql -d gis -c "CREATE INDEX planet_osm_line_ferry ON planet_osm_line USING GIST (way)
      WHERE route = 'ferry';"
    psql -d gis -c "CREATE INDEX planet_osm_line_river ON planet_osm_line USING GIST (way)
      WHERE waterway = 'river';"
    psql -d gis -c "CREATE INDEX planet_osm_line_name ON planet_osm_line USING GIST (way)
      WHERE name IS NOT NULL;"
    psql -d gis -c "CREATE INDEX planet_osm_polygon_water ON planet_osm_polygon USING GIST (way)
      WHERE waterway IN ('dock', 'riverbank', 'canal') OR landuse IN ('reservoir', 'basin')
        OR \"natural\" IN ('water', 'glacier');"
    psql -d gis -c "CREATE INDEX planet_osm_polygon_nobuilding ON planet_osm_polygon USING GIST (way)
      WHERE building IS NULL;"
    psql -d gis -c "CREATE INDEX planet_osm_polygon_name ON planet_osm_polygon USING GIST (way)
      WHERE name IS NOT NULL;"
    psql -d gis -c "CREATE INDEX planet_osm_polygon_way_area_z10 ON planet_osm_polygon USING GIST (way)
      WHERE way_area > 23300;"
    psql -d gis -c "CREATE INDEX planet_osm_polygon_military ON planet_osm_polygon USING GIST (way)
      WHERE (landuse = 'military' OR military = 'danger_area') AND building IS NULL;"
    psql -d gis -c "CREATE INDEX planet_osm_polygon_way_area_z6 ON planet_osm_polygon USING GIST (way)
      WHERE way_area > 5980000;"
    psql -d gis -c "CREATE INDEX planet_osm_point_place ON planet_osm_point USING GIST (way)
      WHERE place IS NOT NULL AND name IS NOT NULL;"
EOSU
    # Download Luxembourg as sample if no data is provided
    if [ ! -f /data.osm.pbf ]; then
        echo "WARNING: No import file at /data.osm.pbf, so importing Luxembourg as example..."
        wget -nv https://download.geofabrik.de/europe/ukraine-latest.osm.pbf -O /data.osm.pbf
    fi

    # Import data
    sudo -u renderer osm2pgsql -d gis --create --slim -G --hstore --tag-transform-script /home/renderer/src/openstreetmap-carto/openstreetmap-carto.lua -C 2048 --number-processes ${THREADS:-4} -S /home/renderer/src/openstreetmap-carto/openstreetmap-carto.style /data.osm.pbf
    service postgresql stop

    exit 0
fi

if [ "$1" = "run" ]; then
    # Initialize PostgreSQL and Apache
    CreatePostgressqlConfig
    service postgresql start
    service apache2 restart

    # Configure renderd threads
    sed -i -E "s/num_threads=[0-9]+/num_threads=${THREADS:-4}/g" /usr/local/etc/renderd.conf

    # Run
    sudo -u renderer renderd -f -c /usr/local/etc/renderd.conf
    service postgresql stop

    exit 0
fi

echo "invalid command"
exit 1
