# Migration Guide — Hardcoded Credentials → AWS Secrets Manager

This guide documents the steps to move an existing application from hardcoded or `.env`-based credentials to AWS Secrets Manager.

## Step 1 — Audit the codebase for leaked credentials

Run these tools before doing anything else:

```bash
# Search git history for password strings (finds secrets even after deletion)
git log -S "password" --all -p | less

# Scan for common secret patterns (API keys, tokens, passwords)
trufflehog git file://. --only-verified

# Prevent future accidental commits
git secrets --install
git secrets --register-aws
```

## Step 2 — Create the secret in Secrets Manager

This project provisions the secret via Terraform (`terraform/secrets.tf`).
If migrating an existing credential manually:

```bash
aws secretsmanager create-secret \
  --name "prod/database/credentials" \
  --kms-key-id alias/prod/secrets-manager \
  --secret-string '{
    "username": "app_user",
    "password": "your-current-password",
    "host": "your-db.xxxx.us-east-1.rds.amazonaws.com",
    "port": 5432,
    "dbname": "appdb"
  }' \
  --region us-east-1
```

## Step 3 — Attach the IAM role to your compute

| Compute type | How to attach |
|---|---|
| EC2 | Attach instance profile containing `prod-web-app-role` |
| ECS / Fargate | Set `taskRoleArn` to `prod-web-app-role` ARN |
| Lambda | Set `role` to `prod-web-app-role` ARN |

No access keys are needed — the IAM role grants temporary credentials automatically.

## Step 4 — Swap the application code

**Before (anti-pattern):**
```python
DB_PASS = os.environ.get("DB_PASSWORD")  # or hardcoded
conn = psycopg2.connect(host=HOST, user=USER, password=DB_PASS)
```

**After (see `examples/secure/secrets-manager-client.py`):**
```python
import boto3, json

def get_db_credentials():
    client = boto3.client("secretsmanager", region_name="us-east-1")
    response = client.get_secret_value(SecretId="prod/database/credentials")
    return json.loads(response["SecretString"])

creds = get_db_credentials()
conn = psycopg2.connect(host=creds["host"], user=creds["username"],
                        password=creds["password"], dbname=creds["dbname"])
```

## Step 5 — Rotate the old credential immediately after migration

Once the app is deployed and verified against the new secret, immediately rotate to invalidate the previously exposed credential:

```bash
aws secretsmanager rotate-secret \
  --secret-id prod/database/credentials \
  --region us-east-1
```

Then verify your app is still connecting successfully (the rotation Lambda
promotes the new password and your app fetches AWSCURRENT on next call).

## Step 6 — Remove old credentials from all locations

- [ ] Delete the `.env` file from the repository
- [ ] Remove environment variable definitions from CI/CD pipelines
- [ ] Rotate any API keys shared over Slack/email
- [ ] Force-push a cleaned git history if credentials were committed:
  ```bash
  git filter-repo --path .env --invert-paths
  ```
  Note: this rewrites history — coordinate with your team before running it.
