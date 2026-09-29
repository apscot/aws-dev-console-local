#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "${ROOT}"

if [[ ! -f .env ]]; then
  echo "No .env found — copying .env.example → .env"
  cp .env.example .env
fi

usage() {
  cat <<EOF
Usage: ./dev.sh [up|down|stop|logs|ps|build]

  up      Start UIs + SSM tunnels
  down    Stop everything: Kafka UI, pgAdmin, and all SSM tunnels
  stop    Same as down
  logs    docker compose logs -f
  ps      docker compose ps
  build   docker compose build
EOF
}

cmd="${1:-up}"

case "${cmd}" in
  up)
    docker compose up -d
    echo
    echo "Kafka UI:  http://localhost:8050"
    echo "pgAdmin:   http://localhost:5252"
    echo "  (login credentials are configured in .env)"
    echo
    echo "Stop later with:  ./dev.sh down"
    ;;
  down|stop)
    echo "Stopping UIs and SSM tunnels..."
    docker compose down --remove-orphans
    # In case a UI was started outside this compose project name
    docker rm -f loyalty-kafka-ui loyalty-pgadmin loyalty-tunnel-manager \
      loyalty-msk-b1 loyalty-msk-b2 loyalty-secret-init 2>/dev/null || true
    echo
    echo "Stopped:"
    echo "  - Kafka UI / pgAdmin"
    echo "  - tunnel-manager (RDS + MSK SSM port-forwards)"
    echo "  - msk-b1 / msk-b2 proxies"
    ;;
  logs)
    docker compose logs -f
    ;;
  ps)
    docker compose ps
    ;;
  build)
    docker compose build
    ;;
  -h|--help|help)
    usage
    ;;
  *)
    echo "Unknown command: ${cmd}"
    usage
    exit 1
    ;;
esac
