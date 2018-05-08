.PHONY: build push test

build:
	docker build -t overv/openstreetmap-tile-server .

push: build
	docker push overv/openstreetmap-tile-server:latest

test: build
	docker volume create openstreetmap-data
	docker run -v openstreetmap-data:/var/lib/postgresql/10/main overv/openstreetmap-tile-server import
	docker run -v openstreetmap-data:/var/lib/postgresql/10/main -p 80:80 -d overv/openstreetmap-tile-server run