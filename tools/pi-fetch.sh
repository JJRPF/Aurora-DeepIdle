#!/bin/bash
# Resumable fetch of a Pi hypervisor-run directory over the flaky wifi (GH-5).
# usage: tools/pi-fetch.sh <run-dir-name or glob suffix> [dest]   e.g.  tools/pi-fetch.sh latew /tmp/x
# Compresses on the Pi first (one .gz per file, kept next to the originals), then rsyncs with --partial --append-verify,
# retrying until done. Uses the key-based pi-ssh helper's host.
set -u
PAT=${1:?run dir name or suffix}; DEST=${2:-$HOME/Work/hvruns}; mkdir -p "$DEST"
SSH="$HOME/.local/state/deepidle/pi-ssh"
for i in $(seq 12); do
    DIR=$(timeout 60 "$SSH" "ls -dt ~/deepidle/hv/*$PAT* 2>/dev/null | head -1") && [ -n "$DIR" ] && break
    sleep 8
done
[ -n "${DIR:-}" ] || { echo "pi unreachable or no run matches $PAT" >&2; exit 1; }
for i in $(seq 12); do
    timeout 120 "$SSH" "cd $DIR && for f in hv.log console.txt run.txt; do [ -f \$f ] && [ ! -s \$f.gz -o \$f -nt \$f.gz ] && gzip -kf \$f; done; ls" >/dev/null 2>&1 && break
    sleep 8
done
RS="ssh -o BatchMode=yes -o ConnectTimeout=20 -o ServerAliveInterval=10 -o ServerAliveCountMax=3 -o IdentitiesOnly=yes -i $HOME/.ssh/id_ed25519_pi"
HOST=jjrpfister@192.168.5.111
for i in $(seq 40); do
    rsync -a --partial --append-verify -e "$RS" "$HOST:$DIR/" "$DEST/$(basename $DIR)/" && { echo "fetched $DIR -> $DEST/$(basename $DIR)"; exit 0; }
    sleep 6
done
echo "gave up after retries" >&2; exit 1
