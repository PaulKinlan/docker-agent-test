.PHONY: help build up down restart shell logs clean

help:
	@echo "Available commands:"
	@echo "  make build    - Build the Docker image"
	@echo "  make up       - Start the container in detached mode"
	@echo "  make down     - Stop and remove the container"
	@echo "  make restart  - Restart the container"
	@echo "  make shell    - Open a bash shell in the container"
	@echo "  make logs     - View container logs"
	@echo "  make clean    - Remove image and cleanup"

build:
	docker-compose build

up:
	docker-compose up -d

down:
	docker-compose down

restart: down up

shell:
	docker-compose exec arch-dev /bin/bash

logs:
	docker-compose logs -f

clean: down
	docker rmi arch-dev:latest || true
	@echo "Note: home directory contents preserved"
