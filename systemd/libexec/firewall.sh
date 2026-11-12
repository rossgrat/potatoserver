#!/usr/bin/env bash
set -euo pipefail

ip -4 address show dev tailscale0 | grep -q '100.108.26.48/'
for command in iptables ip6tables; do
  "$command" -w -N POTATO-K3S-IN 2>/dev/null || true
  "$command" -w -F POTATO-K3S-IN
  for interface in lo tailscale0 cni0 flannel.1; do
    "$command" -w -A POTATO-K3S-IN -i "$interface" -j ACCEPT
  done
  "$command" -w -A POTATO-K3S-IN -j DROP
  if ! "$command" -w -C INPUT -p tcp -m multiport --dports 6443,10250 -j POTATO-K3S-IN 2>/dev/null; then
    "$command" -w -I INPUT 1 -p tcp -m multiport --dports 6443,10250 -j POTATO-K3S-IN
  fi
  if ! "$command" -w -C INPUT -p udp --dport 8472 -j POTATO-K3S-IN 2>/dev/null; then
    "$command" -w -I INPUT 1 -p udp --dport 8472 -j POTATO-K3S-IN
  fi
done
