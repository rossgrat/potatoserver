SERVER = potatoserver
REMOTE_DIR = ~/repos/network
include deployments.conf

.PHONY: up down restart logs deploy k3s-apply k3s-diff k3s-stop k3s-logs

up:
	docker network inspect caddy-network >/dev/null 2>&1 || docker network create --driver bridge --subnet 172.18.0.0/16 --gateway 172.18.0.1 caddy-network
	cd caddy && docker compose up -d
ifneq ($(NTFY_RUNTIME),k3s)
	cd ntfy && docker compose up -d
endif
ifneq ($(MINIFLUX_RUNTIME),k3s)
	cd miniflux && docker compose up -d
endif
ifneq ($(LGTM_RUNTIME),k3s)
	cd lgtm && docker compose up -d
endif
ifneq ($(UMAMI_RUNTIME),k3s)
	cd umami && docker compose up -d
endif
	$(MAKE) k3s-apply

down:
	$(MAKE) k3s-stop
ifneq ($(UMAMI_RUNTIME),k3s)
	cd umami && docker compose down
endif
ifneq ($(LGTM_RUNTIME),k3s)
	cd lgtm && docker compose down
endif
	cd caddy && docker compose down
ifneq ($(NTFY_RUNTIME),k3s)
	cd ntfy && docker compose down
endif
ifneq ($(MINIFLUX_RUNTIME),k3s)
	cd miniflux && docker compose down
endif

restart: down up

logs:
	docker logs --tail=100 -f caddy

deploy:
	ssh $(SERVER) "cd $(REMOTE_DIR) && git pull && make up"

k3s-apply:
	bash ops/apply-k3s.sh

k3s-diff:
	bash ops/apply-k3s.sh --diff

k3s-stop:
	bash ops/stop-k3s.sh

k3s-logs:
	@test -n "$(SERVICE)" || { echo 'Pass SERVICE, for example SERVICE=job-board.' >&2; exit 2; }
	K3S_CONFIG_FILE=/dev/null /usr/local/bin/k3s kubectl --kubeconfig /home/rossgrat/.kube/potatoserver-k3s.yaml logs -n $(SERVICE) -l app=$(SERVICE) --all-containers=true --tail=100 --prefix -f

.PHONY: cms-build cms-up cms-logs cms-deploy

cms-build:
	docker build -t potatoserver-pages-cms:2.1.8-r4-node24.22.2 pages-cms

cms-up:
ifeq ($(PAGES_CMS_RUNTIME),k3s)
	@test "$$(docker image inspect --format '{{.Id}}' potatoserver-pages-cms:2.1.8-r4-node24.22.2)" = "$$(cat /home/rossgrat/k3s-migration-tools/state/pages-cms-imported-image-id)" || { echo 'Import the pinned CMS image into K3s before deploying.' >&2; exit 1; }
	K3S_CONFIG_FILE=/dev/null /usr/local/bin/k3s kubectl --kubeconfig /home/rossgrat/.kube/potatoserver-k3s.yaml apply -f k3s/pages-cms.yaml -f k3s/pages-cms-egress.yaml
	K3S_CONFIG_FILE=/dev/null /usr/local/bin/k3s kubectl --kubeconfig /home/rossgrat/.kube/potatoserver-k3s.yaml rollout status deployment/pages-cms -n pages-cms --timeout=180s
else
	cd pages-cms && docker compose up -d --no-build --wait app
endif

cms-logs:
ifeq ($(PAGES_CMS_RUNTIME),k3s)
	K3S_CONFIG_FILE=/dev/null /usr/local/bin/k3s kubectl --kubeconfig /home/rossgrat/.kube/potatoserver-k3s.yaml logs -n pages-cms deployment/pages-cms --tail=100 -f
else
	cd pages-cms && docker compose logs --tail=100 -f app
endif

cms-deploy:
	ssh $(SERVER) 'cd $(REMOTE_DIR) && git pull --ff-only && ./pages-cms/backup.sh /home/rossgrat/backups/pages-cms/$$(date -u +%Y%m%dT%H%M%SZ) && make cms-build cms-up'
