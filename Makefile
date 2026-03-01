.PHONY: up down restart logs

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
