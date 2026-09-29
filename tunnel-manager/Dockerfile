# ECR Public mirror — avoids flaky Docker Hub auth (auth.docker.io EOF)
FROM public.ecr.aws/docker/library/debian:bookworm-slim

ARG TARGETARCH

# Corporate TLS inspection often breaks apt/curl cert checks during build.
ENV DEBIAN_FRONTEND=noninteractive

RUN set -eux; \
    printf '%s\n' \
      'Acquire::https::Verify-Peer "false";' \
      'Acquire::https::Verify-Host "false";' \
      > /etc/apt/apt.conf.d/99insecure; \
    apt-get update; \
    apt-get install -y --no-install-recommends \
      ca-certificates \
      curl \
      unzip \
      socat \
      netcat-openbsd \
      python3 \
      procps \
      less; \
    case "${TARGETARCH}" in \
      amd64) \
        AWS_CLI_ARCH=x86_64; \
        SSM_ARCH=ubuntu_64bit; \
        ;; \
      arm64) \
        AWS_CLI_ARCH=aarch64; \
        SSM_ARCH=ubuntu_arm64; \
        ;; \
      *) echo "unsupported TARGETARCH=${TARGETARCH}" >&2; exit 1 ;; \
    esac; \
    curl -fkSL "https://awscli.amazonaws.com/awscli-exe-linux-${AWS_CLI_ARCH}.zip" -o /tmp/awscliv2.zip; \
    unzip -q /tmp/awscliv2.zip -d /tmp; \
    /tmp/aws/install; \
    rm -rf /tmp/aws /tmp/awscliv2.zip; \
    curl -fkSL \
      "https://s3.amazonaws.com/session-manager-downloads/plugin/latest/${SSM_ARCH}/session-manager-plugin.deb" \
      -o /tmp/session-manager-plugin.deb; \
    dpkg -i /tmp/session-manager-plugin.deb; \
    rm -f /tmp/session-manager-plugin.deb; \
    rm -rf /var/lib/apt/lists/*

COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

EXPOSE 5432 9094 9095

HEALTHCHECK --interval=10s --timeout=5s --start-period=90s --retries=18 \
  CMD nc -z 127.0.0.1 15432 && nc -z 127.0.0.1 19094 && nc -z 127.0.0.1 19095 || exit 1

ENTRYPOINT ["/entrypoint.sh"]
