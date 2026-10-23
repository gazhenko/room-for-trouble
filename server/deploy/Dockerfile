# Room for Trouble — authoritative private-room service (§20.6).
# Build context: build/server (the exported ServerLinux artifact).
#   docker build -f server/deploy/Dockerfile -t room-for-trouble-server build/server
FROM debian:bookworm-slim@sha256:7ff6ba31527b9e336162fa061746c366c4b2032f4d2cff2078bea43f78efe3f8
RUN apt-get update && apt-get install -y --no-install-recommends ca-certificates libfontconfig1 \
    && rm -rf /var/lib/apt/lists/* \
    && groupadd --system rft && useradd --system --gid rft --home-dir /var/lib/rft --shell /usr/sbin/nologin rft \
    && mkdir -p /opt/rft /var/lib/rft && chown rft:rft /var/lib/rft
COPY --chown=root:root RoomForTroubleServer.x86_64 /opt/rft/RoomForTroubleServer.x86_64
RUN chmod 0555 /opt/rft/RoomForTroubleServer.x86_64
USER rft
ENV RFT_PORT=8080 RFT_BIND=0.0.0.0 RFT_DATA_DIR=/var/lib/rft RFT_MAX_ROOMS=16 RFT_LOG_LEVEL=info \
    HOME=/var/lib/rft XDG_DATA_HOME=/var/lib/rft
VOLUME ["/var/lib/rft"]
EXPOSE 8080
STOPSIGNAL SIGTERM
HEALTHCHECK --interval=30s --timeout=8s --start-period=10s --retries=3 \
  CMD ["/opt/rft/RoomForTroubleServer.x86_64", "--headless", "--", "--probe", "ws://127.0.0.1:8080"]
ENTRYPOINT ["/opt/rft/RoomForTroubleServer.x86_64", "--headless", "--"]
CMD ["--server"]
