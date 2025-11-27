FROM alpine:3.22
ARG TARGETARCH

ENV TZ=UTC \
  LANG=en_US.UTF-8 \
  LANGUAGE=en_US:en \
  LC_ALL=en_US.UTF-8

# user/group precreated explicitly with fixed uid/gid on purpose.
# It is especially important for rootless containers: in that case entrypoint
# can't do chown and owners of mounted volumes should be configured externally.
# We do that in advance at the begining of Dockerfile before any packages will be
# installed to prevent picking those uid / gid by some unrelated software.
ARG DEFAULT_UID="101"
ARG DEFAULT_GID="101"
RUN addgroup -S -g "${DEFAULT_GID}" zorian && \
  adduser -S -h "/var/lib/zorian" -s /bin/bash -G zorian -u "${DEFAULT_UID}" zorian

RUN apk add --no-cache tini tzdata \
  && cp /usr/share/zoneinfo/UTC /etc/localtime \
  && echo "UTC" > /etc/timezone

ARG DEFAULT_DATA_DIR="/var/lib/zorian"
ARG DEFAULT_LOG_DIR="/var/log/zorian"
ARG DEFAULT_CONFIG_FILE="/etc/zorian.zon"

# Build app using `zig build -Doptimize=ReleaseSafe --prefix zig-out/amd64/`
COPY package/zorian.zon ${DEFAULT_CONFIG_FILE}
COPY zig-out/${TARGETARCH}/bin/zorian /zorian

# we need to allow "others" access to Zorian folders, because docker containers
# can be started with arbitrary uids (OpenShift usecase)
RUN mkdir -p "${DEFAULT_DATA_DIR}" "${DEFAULT_LOG_DIR}" \
  && chown root:zorian "${DEFAULT_LOG_DIR}" \
  && chown zorian:zorian "${DEFAULT_DATA_DIR}" \
  && chmod ugo+Xrw -R "${DEFAULT_DATA_DIR}" "${DEFAULT_LOG_DIR}" "${DEFAULT_CONFIG_FILE}"

VOLUME "${DEFAULT_DATA_DIR}"
EXPOSE 8000

ENTRYPOINT ["tini", "--", "/zorian"]
