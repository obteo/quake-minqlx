# Quake Live + minqlx + embedded Redis (Pterodactyl v2)

**By Teo** · Dedicated Pterodactyl v2 container image for legacy Quake Live/minqlx installations.

Based on the proven `ghcr.io/ptero-eggs/steamcmd:debian` (Debian 12) runtime with Python 3.9, redis-py 5.2.1, pyzmq 26.2.1 and Redis Server installed.

## How it runs

- Wings mounts the game directory at `/home/container` and sets the `STARTUP` environment variable.
- The image entrypoint starts Redis on **127.0.0.1:6379 only**, waits for `PONG`, and then starts the normal Quake Live script from `STARTUP`.
- Redis persistence (AOF) is stored under `/home/container/.redis`, within the Pterodactyl game volume. Back this directory up together with the game files.
- No extra Docker network or Redis container is needed.
- On stop, the entrypoint forwards the signal to the game and shuts down Redis gracefully.
- No root privileges at runtime, no Redis port published or external exposure.

## Installation

Create a new GitHub repository (recommended: `obteo/quake-minqlx-redis`) and upload all files including `.github/workflows/docker-publish.yml` to `main`. GitHub Actions builds and pushes to GHCR. Set the GitHub Package visibility to **Public** if Wings must pull anonymously.

In the Quake Live egg's **Docker Images** field:

```text
Quake Live + minqlx + Redis|ghcr.io/obteo/quake-minqlx-redis:1.3
```

Set the existing server's Startup Command to:

```bash
bash /home/container/run_server_x64_minqlx.sh
```

Do not change the working minqlx script. The image does not contain game files or `minqlx.x64.so`: keep them in the server's persistent `/home/container` volume.

In `baseq3/server.cfg`:

```cfg
set qlx_database "Redis"
set qlx_redisAddress "127.0.0.1"
set qlx_redisPort "6379"
set qlx_redisDatabase "0"
set qlx_redisUnixSocket "0"
set qlx_redisPassword ""
```

Make sure the startup script executes the intended server.cfg (e.g. `+exec server.cfg`). Do not use the host's public IP for `net_ip` or ZMQ bind addresses; use `0.0.0.0` where needed. Do not set the same TCP port for ZMQ RCON and statistics.

Before switching, **backup the existing `ql-redis` database** if it contains any plugin state that should migrate. An embedded Redis instance starts with its own data at `/home/container/.redis`; it will not automatically import the database from the prior `ql-redis` container. Keep the old container running until migration is verified, and do not delete its Docker volume. Database migration should be performed during a maintenance window with the game stopped to avoid divergence.

## Build on a node

```bash
docker build -t quake-minqlx-redis:1.3 .
docker run --rm --entrypoint /bin/bash quake-minqlx-redis:1.3 -c 'python3.9 -c "import redis, zmq"; redis-server --version'
```

For a node-local image use `~quake-minqlx-redis:1.3` in the egg Docker Images field. Wings uses the local image without pulling a remote registry. For GHCR use the full published image name without `~`.

## Caveats

- Redis is private to **each** game container and uses resources from the server's Pterodactyl limits.
- The embedded Redis listens without a password on loopback **inside the same container** only; do not change binding to `0.0.0.0` without setting Redis ACL/password and firewall rules.
- Python 3.9 is end-of-life. This is a compatibility image for the legacy `minqlx.x64.so` build, not a modern Python recommendation.
- This is a **source package**, not an already built or tested GHCR release. Validate the image on de4 before using it on production servers.

References: https://docs.pterodactyl.io/v2/guides/egg-creation/egg-docker-images and https://docs.pterodactyl.io/v2/guides/egg-creation/creating-custom-image
