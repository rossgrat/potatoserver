#!/usr/bin/env bash
set -euo pipefail
umask 077
[[ $EUID == 0 ]]
exec 9>/run/potatoserver-k3s-install.lock
if ! flock -n 9; then
  printf 'Another potatoserver K3s installation is running\n' >&2
  exit 1
fi
script_dir=$(cd -- "$(dirname -- "$0")" && pwd)
tools_dir=$(dirname "$script_dir")
k3s_release=$(cat "$tools_dir/k3s/release")
assets="$tools_dir/k3s-assets/$k3s_release"
backup_dir=/home/rossgrat/backups/k3s-baseline-20261111T1754
cd "$assets"
sha256sum --check "$tools_dir/k3s/SHA256SUMS"
(cd "$backup_dir" && sha256sum --check --quiet host-secrets.sha256)
test -s "$backup_dir/restore-results/volumes-summary.txt"
backup_result=$(runuser -u rossgrat -- env XDG_RUNTIME_DIR=/run/user/1000 systemctl --user show potatoserver-backup.service -p Result --value)
[[ "$backup_result" == success ]]
backup_state=$(runuser -u rossgrat -- env XDG_RUNTIME_DIR=/run/user/1000 systemctl --user show potatoserver-backup.service -p ActiveState --value)
[[ "$backup_state" == inactive ]]
install -d -m 700 /home/rossgrat/backups/k3s-install
evidence="/home/rossgrat/backups/k3s-install/$(date -u +%Y%m%dT%H%M%SZ)"
mkdir "$evidence"
mapfile -t containers < <(docker ps -q)
docker inspect "${containers[@]}" > "$evidence/containers-before.json"
docker inspect --format '{{.Id}} {{.Image}} {{.RestartCount}} {{.State.Running}} {{.State.Paused}}' "${containers[@]}" > "$evidence/runtime-before.txt"
iptables-save > "$evidence/iptables-before.txt"
ip6tables-save > "$evidence/ip6tables-before.txt"
if [[ -f /etc/rancher/k3s/config.yaml ]]; then
  cmp /etc/rancher/k3s/config.yaml "$tools_dir/k3s/config.yaml"
fi
if [[ -x /usr/local/bin/k3s ]]; then
  installed_release=$(/usr/local/bin/k3s --version)
  [[ "$installed_release" == "k3s version $k3s_release "* ]]
fi
install -d -m 700 /etc/rancher/k3s /usr/local/libexec/potatoserver-k3s
install -d -m 755 /etc/systemd/system/k3s.service.d
install -m 600 "$tools_dir/k3s/config.yaml" /etc/rancher/k3s/config.yaml
install -m 700 "$tools_dir/ops/k3s-firewall.sh" /usr/local/libexec/potatoserver-k3s/firewall.sh
install -m 644 "$tools_dir/systemd/k3s-potatoserver.conf" /etc/systemd/system/k3s.service.d/potatoserver.conf
install -m 755 "$assets/k3s" /usr/local/bin/k3s
printf 'Installing K3s %s on potatoserver\n' "$k3s_release"
INSTALL_K3S_SKIP_DOWNLOAD=true INSTALL_K3S_SKIP_START=true INSTALL_K3S_SKIP_ENABLE=true \
  INSTALL_K3S_SYMLINK=skip INSTALL_K3S_VERSION="$k3s_release" sh "$assets/install.sh" server
systemctl daemon-reload
systemd-analyze verify k3s.service
trap 'systemctl stop k3s; printf "K3s stopped after a failed installation checkpoint\n" >&2' ERR
printf 'Starting K3s and testing node readiness\n'
systemctl enable --now k3s
/usr/local/bin/k3s kubectl --kubeconfig /etc/rancher/k3s/k3s.yaml wait --for=create --for=condition=Ready node/potatoserver --timeout=180s
for deployment in coredns local-path-provisioner metrics-server; do
  /usr/local/bin/k3s kubectl --kubeconfig /etc/rancher/k3s/k3s.yaml wait --for=create --for=condition=Available \
    "deployment/$deployment" -n kube-system --timeout=180s
done
install -d -m 700 -o rossgrat -g rossgrat /home/rossgrat/.kube
install -m 600 -o rossgrat -g rossgrat /etc/rancher/k3s/k3s.yaml /home/rossgrat/.kube/potatoserver-k3s.yaml
/usr/local/bin/k3s secrets-encrypt status > "$evidence/encryption.txt"
grep -q 'Encryption Status: Enabled' "$evidence/encryption.txt"
docker inspect "${containers[@]}" > "$evidence/containers-after.json"
chown -R rossgrat:rossgrat /home/rossgrat/backups/k3s-install
runuser -u rossgrat -- bash "$tools_dir/ops/verify-k3s.sh" "$evidence"
printf 'Testing existing services while K3s is stopped\n'
systemctl stop k3s
tar -czf "$evidence/cluster-backup.tar.gz" -C / \
  var/lib/rancher/k3s/server/db var/lib/rancher/k3s/server/token etc/rancher/k3s
for url in https://rss.grattafiori.dev/ https://grafana.grattafiori.dev/ https://cms.grattafiori.dev/sign-in https://stats.grattafiori.dev/ https://jobs.grattafiori.dev/ https://wubzduh.grattafiori.dev/ https://alerts.grattafiori.dev/v1/health; do
  curl --fail --max-time 15 --silent --show-error -o /dev/null "$url"
done
systemctl start k3s
/usr/local/bin/k3s kubectl --kubeconfig /etc/rancher/k3s/k3s.yaml wait --for=create --for=condition=Ready node/potatoserver --timeout=180s
docker inspect --format '{{.Id}} {{.Image}} {{.RestartCount}} {{.State.Running}} {{.State.Paused}}' "${containers[@]}" > "$evidence/runtime-after.txt"
cmp "$evidence/runtime-before.txt" "$evidence/runtime-after.txt"
chown -R rossgrat:rossgrat "$evidence"
trap - ERR
printf 'K3s installation and initial verification PASS\n'
