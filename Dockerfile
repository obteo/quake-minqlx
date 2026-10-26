# syntax=docker/dockerfile:1
# Compatible with the proven Quake Live/minqlx Debian 12 SteamCMD runtime.
FROM python:3.9-slim-bookworm AS python39
RUN pip install --no-cache-dir \
    "redis==5.2.1" \
    "pyzmq==26.2.1" \
    "requests==2.32.4"

FROM ghcr.io/ptero-eggs/steamcmd:debian
ARG DEBIAN_FRONTEND=noninteractive
USER root
RUN apt-get update \
    && apt-get install -y --no-install-recommends redis-server redis-tools ca-certificates \
    && rm -rf /var/lib/apt/lists/*
COPY --from=python39 /usr/local/bin/python3.9 /usr/local/bin/python3.9
COPY --from=python39 /usr/local/lib/libpython3.9.so* /usr/local/lib/
COPY --from=python39 /usr/local/lib/python3.9/ /usr/local/lib/python3.9/
COPY --chmod=0755 entrypoint.sh /entrypoint.sh
ENV USER=container HOME=/home/container LD_LIBRARY_PATH=/usr/local/lib
RUN ldconfig \
    && python3.9 -c 'import redis, zmq; print(redis.__version__,zmq.__version__)' \
    && redis-server --version
WORKDIR /home/container
USER container
# Ensure Pterodactyl/Wings launches the supplied entrypoint rather than an upstream one.
ENTRYPOINT []
CMD ["/bin/bash", "/entrypoint.sh"]
