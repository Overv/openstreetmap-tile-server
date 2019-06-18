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
    echo "    UPDATES: consecutive updates (enabled/disabled)"
    exit 1
fi

if [ "$1" = "import" ]; then
    # Initialize PostgreSQL
    CreatePostgressqlConfig
    service postgresql start
    sudo -u postgres createuser renderer
    sudo -u postgres createdb -E UTF8 -O renderer gis
    sudo -u postgres psql -d gis -c "CREATE EXTENSION postgis;"
    sudo -u postgres psql -d gis -c "CREATE EXTENSION hstore;"
    sudo -u postgres psql -d gis -c "ALTER TABLE geometry_columns OWNER TO renderer;"
    sudo -u postgres psql -d gis -c "ALTER TABLE spatial_ref_sys OWNER TO renderer;"

    # Download Luxembourg as sample if no data is provided
    if [ ! -f /data.osm.pbf ]; then
        echo "WARNING: No import file at /data.osm.pbf, so importing Luxembourg as example..."
        wget -nv http://download.geofabrik.de/europe/luxembourg-latest.osm.pbf -O /data.osm.pbf
        wget -nv http://download.geofabrik.de/europe/luxembourg.poly -O /data.poly
    fi

    # determine and set osmosis_replication_timestamp (for consecutive updates)
    osmium fileinfo /data.osm.pbf > /var/lib/mod_tile/data.osm.pbf.info
    osmium fileinfo /data.osm.pbf | grep 'osmosis_replication_timestamp=' | cut -b35-44 > /var/lib/mod_tile/replication_timestamp.txt
    REPLICATION_TIMESTAMP=$(cat /var/lib/mod_tile/replication_timestamp.txt)

    # initial setup of osmosis workspace (for consecutive updates)
    sudo -u renderer openstreetmap-tiles-update-expire $REPLICATION_TIMESTAMP

    # copy polygon file if available
    if [ -f /data.poly ]; then
        sudo -u renderer cp /data.poly /var/lib/mod_tile/data.poly
    fi

    # Import data
    sudo -u renderer osm2pgsql -d gis --create --slim -G --hstore --tag-transform-script /home/renderer/src/openstreetmap-carto/openstreetmap-carto.lua -C 2048 --number-processes ${THREADS:-4} -S /home/renderer/src/openstreetmap-carto/openstreetmap-carto.style /data.osm.pbf

    # Create indexes
    sudo -u postgres psql -d gis -f indexes.sql

    service postgresql stop

    exit 0
fi

if [ "$1" = "run" ]; then
    # Clean /tmp
    rm -rf /tmp/*
    
    # Fix postgres data privileges
    chown postgres:postgres /var/lib/postgresql -R

    # Initialize PostgreSQL and Apache
    CreatePostgressqlConfig
    service postgresql start
    service apache2 restart

    # Configure renderd threads
    sed -i -E "s/num_threads=[0-9]+/num_threads=${THREADS:-4}/g" /usr/local/etc/renderd.conf

    # start cron job to trigger consecutive updates
    if [ "$UPDATES" = "enabled" ]; then
      /etc/init.d/cron start
    fi

    # Run
    sudo -u renderer renderd -f -c /usr/local/etc/renderd.conf
    service postgresql stop

    exit 0
fi

echo "invalid command"
exit 1
