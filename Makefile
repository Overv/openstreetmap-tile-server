.PHONY: build push test

DOCKER_IMAGE=overv/openstreetmap-tile-server

build:
	docker build -t ${DOCKER_IMAGE} .

push: build
	docker push ${DOCKER_IMAGE}:latest

test: build
	docker volume create openstreetmap-data
	docker run --rm -v openstreetmap-data:/var/lib/postgresql/12/main ${DOCKER_IMAGE} import
	docker run --rm -v openstreetmap-data:/var/lib/postgresql/12/main -p 8080:80 -d ${DOCKER_IMAGE} run

stop:
	docker rm -f `docker ps | grep '${DOCKER_IMAGE}' | awk '{ print $$1 }'` || true
	docker volume rm -f openstreetmap-data
