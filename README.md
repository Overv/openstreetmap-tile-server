# openstreetmap-tile-server

[![Build Status](https://travis-ci.org/Overv/openstreetmap-tile-server.svg?branch=master)](https://travis-ci.org/Overv/openstreetmap-tile-server) [![](https://images.microbadger.com/badges/image/overv/openstreetmap-tile-server.svg)](https://microbadger.com/images/overv/openstreetmap-tile-server "openstreetmap-tile-server")

This container allows you to easily set up an OpenStreetMap PNG tile server given a `.osm.pbf` file. It is based on the [latest Ubuntu 18.04 LTS guide](https://switch2osm.org/manually-building-a-tile-server-18-04-lts/) from [switch2osm.org](https://switch2osm.org/) and therefore uses the default OpenStreetMap style.

## Setting up the server

First create a Docker volume to hold the PostgreSQL database that will contain the OpenStreetMap data:

    docker volume create openstreetmap-data

Next, download an .osm.pbf extract from geofabrik.de for the region that you're interested in. You can then start importing it into PostgreSQL by running a container and mounting the file as `/data.osm.pbf`. For example:

```
docker run \
    -v /absolute/path/to/luxembourg.osm.pbf:/data.osm.pbf \
    -v openstreetmap-data:/var/lib/postgresql/12/main \
    overv/openstreetmap-tile-server \
    import
```

If the container exits without errors, then your data has been successfully imported and you are now ready to run the tile server.

### Automatic updates (optional)

If your import is an extract of the planet and has polygonal bounds associated with it, like those from geofabrik.de, then it is possible to set your server up for automatic updates. Make sure to reference both the OSM file and the polygon file during the import process to facilitate this, and also include the `UPDATES=enabled` variable:

```
docker run \
    -e UPDATES=enabled \
    -v /absolute/path/to/luxembourg.osm.pbf:/data.osm.pbf \
    -v /absolute/path/to/luxembourg.poly:/data.poly \
    -v openstreetmap-data:/var/lib/postgresql/12/main \
    overv/openstreetmap-tile-server \
    import
```

Refer to the section *Automatic updating and tile expiry* to actually enable the updates while running the tile server.

### Letting the container download the file

It is also possible to let the container download files for you rather than mounting them in advance by using the `DOWNLOAD_PBF` and `DOWNLOAD_POLY` parameters:

```
docker run \
    -e DOWNLOAD_PBF=https://download.geofabrik.de/europe/luxembourg-latest.osm.pbf \
    -e DOWNLOAD_POLY=https://download.geofabrik.de/europe/luxembourg.poly \
    -v openstreetmap-data:/var/lib/postgresql/12/main \
    overv/openstreetmap-tile-server \
    import
```

## Running the server

Run the server like this:

```
docker run \
    -p 8080:80 \
    -v openstreetmap-data:/var/lib/postgresql/12/main \
    -d overv/openstreetmap-tile-server \
    run
```

Your tiles will now be available at `http://localhost:8080/tile/{z}/{x}/{y}.png`. The demo map in `leaflet-demo.html` will then be available on `http://localhost:8080`. Note that it will initially take quite a bit of time to render the larger tiles for the first time.

### Using Docker Compose

The `docker-compose.yml` file included with this repository shows how the aforementioned command can be used with Docker Compose to run your server.

### Preserving rendered tiles

Tiles that have already been rendered will be stored in `/var/lib/mod_tile`. To make sure that this data survives container restarts, you should create another volume for it:

```
docker volume create openstreetmap-rendered-tiles
docker run \
    -p 8080:80 \
    -v openstreetmap-data:/var/lib/postgresql/12/main \
    -v openstreetmap-rendered-tiles:/var/lib/mod_tile \
    -d overv/openstreetmap-tile-server \
    run
```

**If you do this, then make sure to also run the import with the `openstreetmap-rendered-tiles` volume to make sure that caching works properly across updates!**

### Enabling automatic updating (optional)

Given that you've set up your import as described in the *Automatic updates* section during server setup, you can enable the updating process by setting the `UPDATES` variable while running your server as well:

```
docker run \
    -p 8080:80 \
    -e UPDATES=enabled \
    -v openstreetmap-data:/var/lib/postgresql/12/main \
    -v openstreetmap-rendered-tiles:/var/lib/mod_tile \
    -d overv/openstreetmap-tile-server \
    run
```

This will enable a background process that automatically downloads changes from the OpenStreetMap server, filters them for the relevant region polygon you specified, updates the database and finally marks the affected tiles for rerendering.

### Cross-origin resource sharing

To enable the `Access-Control-Allow-Origin` header to be able to retrieve tiles from other domains, simply set the `ALLOW_CORS` variable to `enabled`:

```
docker run \
    -p 8080:80 \
    -v openstreetmap-data:/var/lib/postgresql/12/main \
    -e ALLOW_CORS=enabled \
    -d overv/openstreetmap-tile-server \
    run
```

### Connecting to Postgres

To connect to the PostgreSQL database inside the container, make sure to expose port 5432:

```
docker run \
    -p 8080:80 \
    -p 5432:5432 \
    -v openstreetmap-data:/var/lib/postgresql/12/main \
    -d overv/openstreetmap-tile-server \
    run
```

Use the user `renderer` and the database `gis` to connect.

```
psql -h localhost -U renderer gis
```

The default password is `renderer`, but it can be changed using the `PGPASSWORD` environment variable:

```
docker run \
    -p 8080:80 \
    -p 5432:5432 \
    -e PGPASSWORD=secret \
    -v openstreetmap-data:/var/lib/postgresql/12/main \
    -d overv/openstreetmap-tile-server \
    run
```

## Performance tuning and tweaking

Details for update procedure and invoked scripts can be found here [link](https://ircama.github.io/osm-carto-tutorials/updating-data/).

### THREADS

The import and tile serving processes use 4 threads by default, but this number can be changed by setting the `THREADS` environment variable. For example:
```
docker run \
    -p 8080:80 \
    -e THREADS=24 \
    -v openstreetmap-data:/var/lib/postgresql/12/main \
    -d overv/openstreetmap-tile-server \
    run
```

### CACHE

The import and tile serving processes use 800 MB RAM cache by default, but this number can be changed by option -C. For example:
```
docker run \
    -p 8080:80 \
    -e "OSM2PGSQL_EXTRA_ARGS=-C 4096" \
    -v openstreetmap-data:/var/lib/postgresql/12/main \
    -d overv/openstreetmap-tile-server \
    run
```

### AUTOVACUUM

The database use the autovacuum feature by default. This behavior can be changed with `AUTOVACUUM` environment variable. For example:
```
docker run \
    -p 8080:80 \
    -e AUTOVACUUM=off \
    -v openstreetmap-data:/var/lib/postgresql/12/main \
    -d overv/openstreetmap-tile-server \
    run
```

### Flat nodes

If you are planning to import the entire planet or you are running into memory errors then you may want to enable the `--flat-nodes` option for osm2pgsql. You can then use it during the import process as follows:

```
docker run \
    -v /absolute/path/to/luxembourg.osm.pbf:/data.osm.pbf \
    -v openstreetmap-nodes:/nodes \
    -v openstreetmap-data:/var/lib/postgresql/12/main \
    -e "OSM2PGSQL_EXTRA_ARGS=--flat-nodes /nodes/flat_nodes.bin" \
    overv/openstreetmap-tile-server \
    import
```

>Note that if you use a folder other than `/nodes` then you must make sure that you manually set the owner to `renderer`!

### Benchmarks

You can find an example of the import performance to expect with this image on the [OpenStreetMap wiki](https://wiki.openstreetmap.org/wiki/Osm2pgsql/benchmarks#debian_9_.2F_openstreetmap-tile-server).

## Troubleshooting

### ERROR: could not resize shared memory segment / No space left on device

If you encounter such entries in the log, it will mean that the default shared memory limit (64 MB) is too low for the container and it should be raised:
```
renderd[121]: ERROR: failed to render TILE ajt 2 0-3 0-3
renderd[121]: reason: Postgis Plugin: ERROR: could not resize shared memory segment "/PostgreSQL.790133961" to 12615680 bytes: ### No space left on device
```
To raise it use `--shm-size` parameter. For example:
```
docker run \
    -p 8080:80 \
    -v openstreetmap-data:/var/lib/postgresql/12/main \
    --shm-size="192m" \
    -d overv/openstreetmap-tile-server \
    run
```
For too high values you may notice excessive CPU load and memory usage. It might be that you will have to experimentally find the best values for yourself.

### The import process unexpectedly exits

You may be running into problems with memory usage during the import. Have a look at the "Flat nodes" section in this README.

## License

```
Copyright 2019 Alexander Overvoorde

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

    https://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.
```
