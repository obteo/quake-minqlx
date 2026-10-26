#!/usr/bin/env bash
set -Eeuo pipefail
cd /home/container
export TZ="${TZ:-UTC}"

if [[ -z "${STARTUP:-}" ]]; then
    echo '[ERROR] STARTUP is empty: configure the server startup command in Pterodactyl.' >&2
    exit 1
fi

# Bind to loopback only. There is no exposed Redis port or shared Docker network.
# Redis data lives on Wings' persistent game-server volume.
REDIS_DIR="/home/container/.redis"
mkdir -p "$REDIS_DIR"
if [[ ! -w "$REDIS_DIR" ]]; then
    echo "[ERROR] Redis data directory is not writable: $REDIS_DIR" >&2
    exit 1
fi

redis_pid=''
game_pid=''
cleanup() {
    local signal="${1:-TERM}"
    trap - INT TERM
    if [[ -n "$game_pid" ]] && kill -0 "$game_pid" 2>/dev/null; then
        kill "-$signal" "$game_pid" 2>/dev/null || true
        # Wait for the game before exiting; Wings can force-stop if needed.
        wait "$game_pid" 2>/dev/null || true
    fi
    if [[ -n "$redis_pid" ]] && kill -0 "$redis_pid" 2>/dev/null; then
        redis-cli -h 127.0.0.1 -p 6379 shutdown save >/dev/null 2>&1 || true
        kill -TERM "$redis_pid" 2>/dev/null || true
        wait "$redis_pid" 2>/dev/null || true
    fi
}
trap 'cleanup INT; exit 130' INT
trap 'cleanup TERM; exit 143' TERM

# Redis does not run as root: Wings supplies the runtime UID.
redis-server \
    --bind 127.0.0.1 \
    --port 6379 \
    --protected-mode yes \
    --dir "$REDIS_DIR" \
    --appendonly yes \
    --appendfsync everysec \
    --daemonize no &
redis_pid=$!

ready=0
for _ in $(seq 1 60); do
    if ! kill -0 "$redis_pid" 2>/dev/null; then
        echo '[ERROR] Redis stopped during startup.' >&2
        wait "$redis_pid" || true
        exit 1
    fi
    if redis-cli -h 127.0.0.1 -p 6379 ping 2>/dev/null | grep -qx 'PONG'; then
        ready=1
        break
    fi
    sleep 0.2
done
if [[ "$ready" -ne 1 ]]; then
    echo '[ERROR] Redis did not become ready.' >&2
    cleanup TERM
    exit 1
fi

echo '[minqlx image] Embedded Redis ready at 127.0.0.1:6379.'
# Match the placeholder transformation from obteo/yob-debian13-amd64-multiarch.
MODIFIED_STARTUP="$(printf '%s' "$STARTUP" | sed -e 's/{{/${/g' -e 's/}}/}/g')"
printf ':/home/container$ %s\n' "$MODIFIED_STARTUP"
# Wrapper stays PID 1 in order to manage two processes and deliver signals.
# exec within the child shell makes the game/script its direct process.
/bin/bash -c "exec $MODIFIED_STARTUP" &
game_pid=$!

set +e
wait "$game_pid"
result=$?
set -e
# Game exited: shut Redis down cleanly without terminating the game again.
game_pid=''
cleanup TERM
exit "$result"
