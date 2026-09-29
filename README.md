# Loyalty Dev Console

Run Kafka UI and pgAdmin locally through AWS SSM tunnels.

## Prerequisites

- [Docker Desktop](https://www.docker.com/products/docker-desktop/)
- AWS credentials in `~/.aws`
- Permission to use Session Manager and read the configured Secrets Manager secret

## Configure

```bash
cp .env.example .env
```

Set these values in `.env`:

- `AWS_PROFILE` (optional)
- `AWS_REGION`
- `BASTION_ID`
- `RDS_HOST`
- `MSK_B1_HOST`
- `MSK_B2_HOST`
- `DB_SECRET_ID`
- `PGADMIN_DEFAULT_EMAIL`
- `PGADMIN_DEFAULT_PASSWORD`

`.env` is ignored by Git and is the only place for account-specific settings and credentials.

## Start

```bash
docker compose up -d --build
```

For later starts, use:

```bash
./dev.sh up
```

## Open

| UI | URL |
|----|-----|
| Kafka UI | http://localhost:8050 |
| pgAdmin | http://localhost:5252 |

Sign in to pgAdmin with `PGADMIN_DEFAULT_EMAIL` and `PGADMIN_DEFAULT_PASSWORD` from `.env`. The preconfigured `AwsDev-PG` server uses credentials fetched from Secrets Manager.

## Stop

```bash
./dev.sh down
```

To rebuild the tunnel image after changing its Dockerfile:

```bash
./dev.sh build
```

## Required AWS Access

The selected AWS profile needs permission to start SSM port-forwarding sessions
through the bastion and read the configured database secret. Direct RDS, MSK,
EC2, and IAM administration permissions are not required.

```json
{
	"Version": "2012-10-17",
	"Statement": [
		{
			"Sid": "StartPortForwardingSession",
			"Effect": "Allow",
			"Action": "ssm:StartSession",
			"Resource": [
				"arn:aws:ec2:REGION:ACCOUNT_ID:instance/BASTION_INSTANCE_ID",
				"arn:aws:ssm:REGION::document/AWS-StartPortForwardingSessionToRemoteHost"
			]
		},
		{
			"Sid": "ManageOwnSessions",
			"Effect": "Allow",
			"Action": [
				"ssm:TerminateSession",
				"ssm:ResumeSession"
			],
			"Resource": "arn:aws:ssm:REGION:ACCOUNT_ID:session/${aws:username}-*"
		},
		{
			"Sid": "ReadDatabaseSecret",
			"Effect": "Allow",
			"Action": "secretsmanager:GetSecretValue",
			"Resource": "SECRET_ARN"
		}
	]
}
```

Add `kms:Decrypt` for the specific KMS key only when the secret uses a
customer-managed KMS key.
