# openstreetmap-tile-server

This container allows you to easily set up an OpenStreetMap PNG tile server given a `.osm.pbf` file. It is based on the [latest Ubuntu 18.04 LTS guide](https://switch2osm.org/manually-building-a-tile-server-18-04-lts/) from [switch2osm.org](https://switch2osm.org/) and therefore uses the default OpenStreetMap style.

## Setting up the server

First create a Docker volume to hold the PostgreSQL database that will contain the OpenStreetMap data:

    docker volume create openstreetmap-data

Next, download an .osm.pbf extract from geofabrik.de for the region that you're interested in. You can then start importing it into PostgreSQL by running a container and mounting the file as `/data.osm.pbf`. For example:

    docker run -v /absolute/path/to/luxembourg.osm.pbf:/data.osm.pbf -v openstreetmap-data:/var/lib/postgresql/10/main overv/openstreetmap-tile-server import

If the container exits without errors, then your data has been successfully imported and you are now ready to run the tile server.

## Running the server

Run the server like this:

    docker run -p 80:80 -v openstreetmap-data:/var/lib/postgresql/10/main -d overv/openstreetmap-tile-server run

Your tiles will now be available at `http://localhost:80/tile/{z}/{x}/{y}.png`. The demo map in `leaflet-demo.html` will then be available on `http://localhost:80`. Note that it will initially quite a bit of time to render the larger tiles for the first time.

## Preserving rendered tiles

Tiles that have already been rendered will be stored in `/var/lib/mod_tile`. To make sure that this data survives container restarts, you should create another volume for it:

    docker volume create openstreetmap-rendered-tiles
    docker run -p 80:80 -v openstreetmap-data:/var/lib/postgresql/10/main -v openstreetmap-rendered-tiles:/var/lib/mod_tile -d overv/openstreetmap-tile-server run

## Performance tuning

### THREADS

The import and tile serving processes use 4 threads by default, but this number can be changed by setting the `THREADS` environment variable. For example:

    docker run -p 80:80 -e THREADS=24 -v openstreetmap-data:/var/lib/postgresql/10/main -d overv/openstreetmap-tile-server run

### AUTOVACUUM

The database use the autovacuum feature by default. This behavior can be changed with `AUTOVACUUM` environment variable. For example:

    docker run -p 80:80 -e AUTOVACUUM=off -v openstreetmap-data:/var/lib/postgresql/10/main -d overv/openstreetmap-tile-server

## Troubleshooting

### ERROR: could not resize shared memory segment

If you encounter such entries in the log, it will mean that the default shared memory limit (64 MB) is too low for the container and it should be raised:

    renderd[126]: ERROR: failed to render TILE ajt 6 32-39 16-23,
    renderd[126]: reason: Postgis Plugin: ERROR: could not resize shared memory segment

To raise it use `--shm-size` parameter. For example:

    docker run -p 80:80 -v openstreetmap-data:/var/lib/postgresql/10/main --shm-size="192m" -d overv/openstreetmap-tile-server run

For too high values you may notice excessive CPU load and memory usage. It might be that you will have to experimentally find the best values for yourself.

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
