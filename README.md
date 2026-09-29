# Loyalty Dev Console

One command starts SSM tunnels (auto-reconnect), Kafka UI, and pgAdmin for an AWS development account.

## Prerequisites (one-time)

- [Docker Desktop](https://www.docker.com/products/docker-desktop/)
- AWS credentials in `~/.aws` that can call **SSM** and **Secrets Manager** in your target region
- Session Manager access to your bastion instance

## Start

```bash
cd /Users/arpan/IdeaProjects/loyalty-dev-console
cp .env.example .env   # first time only; set the required connection values
docker compose up -d
# or: ./dev.sh
```

Before starting, set all values in `.env`. It is ignored by Git and is the only
place for AWS account details, database and broker endpoints, the Secrets
Manager secret ID, and pgAdmin credentials. The stack stops with a clear error
when a required value is missing.

Run `./dev.sh build` after changing the tunnel image or its Dockerfile.

If Docker Hub is flaky (`auth.docker.io` EOF), the tunnel image builds from **ECR Public** (`public.ecr.aws/docker/library/debian`). Kafka UI / pgAdmin use locally cached images (`pull_policy: missing`). To skip rebuild entirely:

```bash
docker compose up -d --no-build
```
| UI | URL |
|----|-----|
| Kafka UI | http://localhost:8050 |
| pgAdmin | http://localhost:5252 |

pgAdmin web login comes from `.env` (`PGADMIN_DEFAULT_EMAIL` / `PGADMIN_DEFAULT_PASSWORD`). RDS username/password are fetched automatically from Secrets Manager into the pre-registered **AwsDev-PG** server.

## Stop (UIs + SSM)

Stops Kafka UI, pgAdmin, broker proxies, **and** `tunnel-manager` (all SSM port-forwards).

```bash
./dev.sh down
# or: docker compose down
```

After this, nothing is listening for MSK/RDS via SSM from this stack.
## What runs

| Service | Role |
|---------|------|
| `tunnel-manager` | Supervises 3 SSM port-forwards (RDS + MSK b-1/b-2) with auto-restart; republishes ports for the compose network |
| `secret-init` | One-shot: Secrets Manager → pgAdmin `servers.json` + `.pgpass` |
| `msk-b1` / `msk-b2` | Docker DNS aliases for advertised MSK broker hostnames |
| `kafka-ui` | Browse topics/messages (`SSL` to MSK) |
| `pgadmin` | Browse all Postgres DBs on the cluster |

You do **not** need to run SSM or secret scripts yourself; compose entrypoints do that.

## Troubleshooting

**Tunnels never become healthy**

```bash
docker compose logs -f tunnel-manager
```

Check AWS profile/credentials, bastion ID, and that nothing else is already bound to host ports `5432` / `9094` / `9095`.

**Kafka UI: brokers offline / connection errors**

- Wait until `tunnel-manager` is healthy (`docker compose ps`)
- Confirm `msk-b1` / `msk-b2` are running
- MSK uses TLS on `9094` (`SECURITY_PROTOCOL=SSL`); IAM/SCRAM are out of scope for v1

**pgAdmin: AwsDev-PG missing or auth fails**

```bash
docker compose logs secret-init
docker compose up -d secret-init   # re-fetch secret, then recreate pgadmin if needed
docker compose up -d --force-recreate pgadmin
```

Ensure the secret id in `.env` (`DB_SECRET_ID`) is correct and your IAM user/role can `secretsmanager:GetSecretValue`.

**Kafka UI slow / topics empty**

Usually the SSM tunnel is half-dead (TCP up, TLS hangs). Restart tunnels, then Kafka UI:

```bash
docker compose restart tunnel-manager
docker compose up -d --force-recreate kafka-ui
```

Wait until `tunnel-manager` is healthy (`docker compose ps`), then reload http://localhost:8050. Topic listing over SSM is slower than a VPC client — give it 15–30s on first load.
