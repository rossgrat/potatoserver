SERVER = potatoserver
REMOTE_DIR = ~/repos/network
include deployments.conf

.PHONY: up down restart logs deploy k3s-apply k3s-diff k3s-stop k3s-logs

up:
	$(MAKE) k3s-apply

down:
	$(MAKE) k3s-stop

restart: down up

logs:
	$(MAKE) k3s-logs SERVICE=caddy

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

.PHONY: cms-build cms-up cms-logs

cms-build:
	@test "$$(hostname)" != potatoserver || { echo 'Build the CMS image on your workstation, then import its archive on potatoserver.' >&2; exit 2; }
	docker build --platform linux/amd64 -t potatoserver-pages-cms:2.1.8-r4-node24.22.2 pages-cms

cms-up:
	bash ops/deploy-cms.sh

cms-logs:
	K3S_CONFIG_FILE=/dev/null /usr/local/bin/k3s kubectl --kubeconfig /home/rossgrat/.kube/potatoserver-k3s.yaml logs -n pages-cms deployment/pages-cms --tail=100 -f
