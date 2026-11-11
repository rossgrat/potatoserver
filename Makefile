SERVER = potatoserver
REMOTE_DIR = ~/repos/network

.PHONY: up down restart logs deploy

up:
	docker network create --driver bridge caddy-network 2>/dev/null || true
	cd caddy && docker compose up -d
	cd ntfy && docker compose up -d
	cd miniflux && docker compose up -d
	cd lgtm && docker compose up -d
	cd goatcounter && docker compose up -d

down:
	cd goatcounter && docker compose down
	cd lgtm && docker compose down
	cd caddy && docker compose down
	cd ntfy && docker compose down
	cd miniflux && docker compose down

restart: down up

logs:
	docker compose -f caddy/docker-compose.yml -f ntfy/docker-compose.yml -f miniflux/docker-compose.yml -f lgtm/docker-compose.yml -f goatcounter/docker-compose.yml logs -f

deploy:
	ssh $(SERVER) "cd $(REMOTE_DIR) && git pull && make restart"

.PHONY: cms-build cms-up cms-logs cms-deploy

cms-build:
	docker build -t potatoserver-pages-cms:2.1.8-node24.22.2 pages-cms

cms-up:
	cd pages-cms && docker compose up -d --no-build --wait app

cms-logs:
	cd pages-cms && docker compose logs --tail=100 -f app

cms-deploy:
	ssh $(SERVER) 'cd $(REMOTE_DIR) && git pull --ff-only && ./pages-cms/backup.sh /home/rossgrat/backups/pages-cms/$$(date -u +%Y%m%dT%H%M%SZ) && make cms-build cms-up'
