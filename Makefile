SERVER = potatoserver
REMOTE_DIR = ~/repos/network

.PHONY: up down restart logs deploy

up:
	docker network create --driver bridge caddy-network 2>/dev/null || true
	cd caddy && docker-compose up -d
	cd miniflux && docker-compose up -d

down:
	cd caddy && docker-compose down
	cd miniflux && docker-compose down

restart: down up

logs:
	docker-compose -f caddy/docker-compose.yml -f miniflux/docker-compose.yml logs -f

deploy:
	ssh $(SERVER) "cd $(REMOTE_DIR) && git pull && make restart"
