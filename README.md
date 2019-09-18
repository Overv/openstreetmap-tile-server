# openstreetmap-tile-server

This container allows you to easily set up an OpenStreetMap PNG tile server given a `.osm.pbf` file. It is based on the [latest Ubuntu 18.04 LTS guide](https://switch2osm.org/manually-building-a-tile-server-18-04-lts/) from [switch2osm.org](https://switch2osm.org/) and therefore uses the default OpenStreetMap style.

## Setting up the server

First create a Docker volume to hold the PostgreSQL database that will contain the OpenStreetMap data:

    docker volume create openstreetmap-data

Next, download an .osm.pbf extract from geofabrik.de for the region that you're interested in. You can then start importing it into PostgreSQL by running a container and mounting the file as `/data.osm.pbf`. For example:

```
docker run \
    -v /absolute/path/to/luxembourg.osm.pbf:/data.osm.pbf \
    -v openstreetmap-data:/var/lib/postgresql/10/main \
    overv/openstreetmap-tile-server \
    import
```

If the container exits without errors, then your data has been successfully imported and you are now ready to run the tile server.

### Automatic updates (optional)

If your import is an extract of the planet and has polygonal bounds associated with it, like those from geofabrik.de, then it is possible to set your server up for automatic updates. Make sure to reference both the OSM file and the polygon file during the import process to facilitate this:

```
docker run \
    -v /absolute/path/to/luxembourg.osm.pbf:/data.osm.pbf \
    -v /absolute/path/to/luxembourg.poly:/data.poly \
    -v openstreetmap-data:/var/lib/postgresql/10/main \
    overv/openstreetmap-tile-server \
    import
```

Refer to the section *Automatic updating and tile expiry* to actually enable the updates.

## Running the server

Run the server like this:

```
docker run \
    -p 80:80 \
    -v openstreetmap-data:/var/lib/postgresql/10/main \
    -d overv/openstreetmap-tile-server \
    run
```

Your tiles will now be available at `http://localhost:80/tile/{z}/{x}/{y}.png`. The demo map in `leaflet-demo.html` will then be available on `http://localhost:80`. Note that it will initially take quite a bit of time to render the larger tiles for the first time.

### Preserving rendered tiles

Tiles that have already been rendered will be stored in `/var/lib/mod_tile`. To make sure that this data survives container restarts, you should create another volume for it:

```
docker volume create openstreetmap-rendered-tiles
docker run \
    -p 80:80 \
    -v openstreetmap-data:/var/lib/postgresql/10/main \
    -v openstreetmap-rendered-tiles:/var/lib/mod_tile \
    -d overv/openstreetmap-tile-server \
    run
```

### Enabling automatic updating (optional)

Given that you've specified both the OSM data and polygon as specified in the *Automatic updates* section during server setup, you can enable the updating process by setting the variable `UPDATES` to `enabled`:

```
docker run \
    -p 80:80 \
    -e UPDATES=enabled \
    -v openstreetmap-data:/var/lib/postgresql/10/main \
    -v openstreetmap-rendered-tiles:/var/lib/mod_tile \
    -d overv/openstreetmap-tile-server \
    run
```

This will enable a background process that automatically downloads changes from the OpenStreetMap server, filters them for the relevant region polygon you specified, updates the database and finally marks the affected tiles for rerendering.

### Cross-origin resource sharing

To enable the `Access-Control-Allow-Origin` header to be able to retrieve tiles from other domains, simply set the `ALLOW_CORS` variable to `1`:

```
docker run \
    -p 80:80 \
    -v openstreetmap-data:/var/lib/postgresql/10/main \
    -e ALLOW_CORS=1 \
    -d overv/openstreetmap-tile-server \
    run
```

## Performance tuning and tweaking

Details for update procedure and invoked scripts can be found here [link](https://ircama.github.io/osm-carto-tutorials/updating-data/).

### THREADS

The import and tile serving processes use 4 threads by default, but this number can be changed by setting the `THREADS` environment variable. For example:
```
docker run \
    -p 80:80 \
    -e THREADS=24 \
    -v openstreetmap-data:/var/lib/postgresql/10/main \
    -d overv/openstreetmap-tile-server \
    run
```

### CACHE

The import and tile serving processes use 800 MB RAM cache by default, but this number can be changed by option -C. For example:
```
docker run \
    -p 80:80 \
    -e "OSM2PGSQL_EXTRA_ARGS=-C 4096" \
    -v openstreetmap-data:/var/lib/postgresql/10/main \
    -d overv/openstreetmap-tile-server \
    run
```

### AUTOVACUUM

The database use the autovacuum feature by default. This behavior can be changed with `AUTOVACUUM` environment variable. For example:
```
docker run \
    -p 80:80 \
    -e AUTOVACUUM=off \
    -v openstreetmap-data:/var/lib/postgresql/10/main \
    -d overv/openstreetmap-tile-server \
    run
```

### Flat nodes

If you are planning to import the entire planet or you are running into memory errors then you may want to enable the `--flat-nodes` option for osm2pgsql. This option takes a path to a file that must be persisted so we should first set up a volume with the right permissions:

```
docker run -it -v openstreetmap-nodes:/nodes --entrypoint=bash overv/openstreetmap-tile-server
$ chown renderer:renderer -R /nodes
$ exit
```

You can then use it during the import process as follows:

```
docker run \
    -v /absolute/path/to/luxembourg.osm.pbf:/data.osm.pbf \
    -v openstreetmap-nodes:/nodes \
    -v openstreetmap-data:/var/lib/postgresql/10/main \
    -e "OSM2PGSQL_EXTRA_ARGS=--flat-nodes /nodes/flat_nodes.bin" \
    overv/openstreetmap-tile-server \
    import
```

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
    -p 80:80 \
    -v openstreetmap-data:/var/lib/postgresql/10/main \
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

    http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.
```
