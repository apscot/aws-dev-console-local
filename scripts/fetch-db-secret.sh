#!/usr/bin/env bash
set -euo pipefail

if [[ -z "${AWS_PROFILE:-}" ]]; then
  unset AWS_PROFILE || true
fi

: "${AWS_REGION:?AWS_REGION must be set in .env}"
: "${DB_SECRET_ID:?DB_SECRET_ID must be set in .env}"
PG_HOST="${PG_HOST:-tunnel-manager}"
PG_PORT="${PG_PORT:-5432}"
PG_MAINTENANCE_DB="${PG_MAINTENANCE_DB:-postgres}"
PG_USERNAME_FALLBACK="${PG_USERNAME_FALLBACK:-postgres}"
OUT_DIR="${OUT_DIR:-/out}"
TEMPLATE="${TEMPLATE:-/template/servers.json.template}"

log() {
  echo "[$(date -u +'%Y-%m-%dT%H:%M:%SZ')] $*"
}

mkdir -p "${OUT_DIR}"

DB_USERNAME="${PG_USERNAME_FALLBACK}"
DB_PASSWORD=""
HAVE_PASSWORD=0

log "Fetching RDS secret: ${DB_SECRET_ID} (${AWS_REGION})"
set +e
SECRET_JSON="$(
  aws secretsmanager get-secret-value \
    --secret-id "${DB_SECRET_ID}" \
    --region "${AWS_REGION}" \
    --query SecretString \
    --output text 2>/tmp/secret-init.err
)"
SECRET_RC=$?
set -e

if [[ "${SECRET_RC}" -eq 0 && -n "${SECRET_JSON}" ]]; then
  eval "$(
    SECRET_JSON="${SECRET_JSON}" python3 - <<'PY'
import json, os, shlex, sys
data = json.loads(os.environ["SECRET_JSON"])
user = data.get("username") or data.get("Username")
password = data.get("password") or data.get("Password")
if not user or password is None:
    sys.exit("secret JSON missing username/password")
print(f"DB_USERNAME={shlex.quote(user)}")
print(f"DB_PASSWORD={shlex.quote(password)}")
PY
  )"
  HAVE_PASSWORD=1
  log "Secret fetched successfully"
else
  log "ERROR: could not fetch secret (IAM / network)."
  if [[ -s /tmp/secret-init.err ]]; then
    sed 's/^/  /' /tmp/secret-init.err || true
  fi
  if [[ -f "${OUT_DIR}/servers.json" && -f "${OUT_DIR}/pgpass" ]]; then
    log "Retaining the existing pgAdmin configuration."
    exit 0
  fi
  log "No existing pgAdmin configuration is available."
  exit 1
fi

log "Writing servers.json for ${PG_HOST}:${PG_PORT} (user=${DB_USERNAME})"

umask 077
{
  printf '%s:%s:*:%s:%s\n' "${PG_HOST}" "${PG_PORT}" "${DB_USERNAME}" "${DB_PASSWORD}"
  printf 'localhost:%s:*:%s:%s\n' "${PG_PORT}" "${DB_USERNAME}" "${DB_PASSWORD}"
} > "${OUT_DIR}/pgpass"
chmod 600 "${OUT_DIR}/pgpass"
PASSFILE_LINE='/config/pgpass'

sed \
  -e "s|__PG_HOST__|${PG_HOST}|g" \
  -e "s|__PG_PORT__|${PG_PORT}|g" \
  -e "s|__PG_MAINTENANCE_DB__|${PG_MAINTENANCE_DB}|g" \
  -e "s|__PG_USERNAME__|${DB_USERNAME}|g" \
  -e "s|__PG_PASSFILE__|${PASSFILE_LINE}|g" \
  "${TEMPLATE}" > "${OUT_DIR}/servers.json"

chown -R 5050:5050 "${OUT_DIR}" 2>/dev/null || true
[[ -f "${OUT_DIR}/pgpass" ]] && chmod 600 "${OUT_DIR}/pgpass"
chmod 644 "${OUT_DIR}/servers.json"

log "Secret init complete → ${OUT_DIR}/servers.json"
exit 0
