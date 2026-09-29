#!/usr/bin/env bash
set -euo pipefail

# Empty AWS_PROFILE breaks the CLI; treat blank as unset
if [[ -z "${AWS_PROFILE:-}" ]]; then
  unset AWS_PROFILE || true
fi

: "${AWS_REGION:?AWS_REGION must be set in .env}"
: "${BASTION_ID:?BASTION_ID must be set in .env}"
: "${RDS_HOST:?RDS_HOST must be set in .env}"
: "${MSK_B1_HOST:?MSK_B1_HOST must be set in .env}"
: "${MSK_B2_HOST:?MSK_B2_HOST must be set in .env}"
RESTART_DELAY_SEC="${RESTART_DELAY_SEC:-2}"

# SSM binds 127.0.0.1 only. Use distinct loopback ports so socat can
# safely publish the compose-facing ports on 0.0.0.0.
SSM_RDS_PORT=15432
SSM_MSK_B1_PORT=19094
SSM_MSK_B2_PORT=19095
PUB_RDS_PORT=5432
PUB_MSK_B1_PORT=9094
PUB_MSK_B2_PORT=9095

log() {
  echo "[$(date -u +'%Y-%m-%dT%H:%M:%SZ')] $*"
}

supervise_ssm() {
  local name="$1"
  local remote_host="$2"
  local remote_port="$3"
  local local_port="$4"

  while true; do
    log "SSM[${name}] starting → ${remote_host}:${remote_port} (loopback ${local_port})"
    aws ssm start-session \
      --target "${BASTION_ID}" \
      --document-name AWS-StartPortForwardingSessionToRemoteHost \
      --parameters "{\"host\":[\"${remote_host}\"],\"portNumber\":[\"${remote_port}\"],\"localPortNumber\":[\"${local_port}\"]}" \
      --region "${AWS_REGION}" \
      || true
    log "SSM[${name}] disconnected; retrying in ${RESTART_DELAY_SEC}s"
    sleep "${RESTART_DELAY_SEC}"
  done
}

supervise_socat() {
  local name="$1"
  local listen_port="$2"
  local target_port="$3"

  while true; do
    log "socat[${name}] 0.0.0.0:${listen_port} → 127.0.0.1:${target_port}"
    socat \
      TCP-LISTEN:"${listen_port}",bind=0.0.0.0,fork,reuseaddr \
      TCP:127.0.0.1:"${target_port}" \
      || true
    log "socat[${name}] exited; retrying in ${RESTART_DELAY_SEC}s"
    sleep "${RESTART_DELAY_SEC}"
  done
}

log "tunnel-manager starting (region=${AWS_REGION}, bastion=${BASTION_ID})"

supervise_ssm "rds"    "${RDS_HOST}"    5432 "${SSM_RDS_PORT}" &
supervise_ssm "msk-b1" "${MSK_B1_HOST}" 9094 "${SSM_MSK_B1_PORT}" &
supervise_ssm "msk-b2" "${MSK_B2_HOST}" 9094 "${SSM_MSK_B2_PORT}" &

supervise_socat "rds"    "${PUB_RDS_PORT}"    "${SSM_RDS_PORT}" &
supervise_socat "msk-b1" "${PUB_MSK_B1_PORT}" "${SSM_MSK_B1_PORT}" &
supervise_socat "msk-b2" "${PUB_MSK_B2_PORT}" "${SSM_MSK_B2_PORT}" &

log "Supervising 3 SSM + 3 socat loops"
wait
