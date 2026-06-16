# AWS Secrets Management & Credential Hygiene

A production-grade secrets management system built on AWS that replaces hardcoded credentials with a centrally managed, automatically rotating, least-privilege secrets architecture — mirroring how real remediation work happens in security and cloud engineering roles.

---

## Before You Start — What You Must Change

If you are using this project yourself, these are the values you **must replace** before deploying. Everything else has a working default.

| # | File | Value to change | What to replace it with |
|---|---|---|---|
| 1 | `terraform/backend.tf` | `aj-cloudsentrics-bucket` | Your own S3 bucket name |
| 2 | `terraform/backend.tf` | `my-lock-table` | Your own DynamoDB table name |
| 3 | `terraform/backend.tf` | `us-east-1` (region) | Your AWS region |
| 4 | `terraform/terraform.tfvars` | `aws_region = "us-east-1"` | Your AWS region |
| 5 | `terraform/terraform.tfvars` | `environment = "prod"` | Your environment name (dev/staging/prod) |
| 6 | `terraform/terraform.tfvars` | `db_name`, `db_username` | Your preferred DB name and master username |

**Optional — change only if needed:**

| File | Value | Default | Change when… |
|---|---|---|---|
| `terraform/terraform.tfvars` | `db_instance_class` | `db.t3.micro` | You need more DB compute |
| `terraform/terraform.tfvars` | `db_engine_version` | `16.4` | You need a specific Postgres version |
| `terraform/terraform.tfvars` | `db_allocated_storage` | `20` (GB) | You need more storage |

**Backend prerequisites — must exist before `terraform init`:**

```bash
# 1. Create the S3 bucket (replace with your bucket name and region)
aws s3api create-bucket \
  --bucket YOUR-BUCKET-NAME \
  --region YOUR-REGION

# Enable versioning so you can recover from bad state writes
aws s3api put-bucket-versioning \
  --bucket YOUR-BUCKET-NAME \
  --versioning-configuration Status=Enabled

# 2. Create the DynamoDB lock table (replace with your table name)
aws dynamodb create-table \
  --table-name YOUR-LOCK-TABLE-NAME \
  --attribute-definitions AttributeName=LockID,AttributeType=S \
  --key-schema AttributeName=LockID,KeyType=HASH \
  --billing-mode PAY_PER_REQUEST \
  --region YOUR-REGION

# 3. Update backend.tf with your bucket, table, and region, then:
cd terraform && terraform init
```

## AWS Services Used

| Service | Purpose |
|---|---|
| AWS Secrets Manager | Central secret storage and lifecycle management |
| AWS KMS | Two customer-managed CMKs — one for secrets, one for RDS storage |
| AWS Lambda | 4-step rotation function with `psycopg2` bundled in the deployment zip |
| AWS IAM | Least-privilege role per workload, trust policies scoped to service principals |
| AWS CloudTrail | Full audit log of every `GetSecretValue` and `RotateSecret` call |
| AWS RDS (PostgreSQL) | Private database instance the rotation Lambda manages passwords for |
| AWS VPC | Fully private network — Lambda reaches AWS APIs via interface endpoints, no NAT |
| Terraform | Infrastructure as code for all 29 resources |

---

## Deliverables Checklist

- [x] Anti-patterns documented with code examples and risk explanations
- [x] Secure Secrets Manager client implementation
- [x] Customer-managed KMS keys with automatic rotation
- [x] IAM policies scoped to least privilege per workload
- [x] Rotation Lambda with 4-step protocol (create → set → test → finish)
- [x] Terraform for all infrastructure (S3 backend + DynamoDB state locking)
- [x] Migration guide (hardcoded → managed secrets)
- [x] Incident response playbook for leaked secrets
- [x] CloudTrail audit log verification
- [x] CI/CD integration pattern for secret access

---

## Questions Answered

### 1. What insecure patterns are you fixing?

Three anti-patterns documented in [`examples/insecure/`](examples/insecure/):

**Pattern 1 — Hardcoded credentials** (`hardcoded-creds.py`)
```python
# NEVER DO THIS IN PRODUCTION
DB_PASS = "SuperSecretPassword123!"
API_KEY  = "sk-live-abc123def456"
```
Risk: committed to git history forever, no rotation, no audit trail, visible to anyone with repo access.

**Pattern 2 — .env files** (`env-file-example.py`)
```python
DB_PASS    = os.environ.get("DB_PASSWORD")   # sourced from .env
STRIPE_KEY = os.environ.get("STRIPE_KEY")    # visible in `ps aux`
```
Risk: `.env` files get committed by accident, shared over Slack with no expiry, visible in process listings and crash dumps, no rotation.

**Pattern 3 — Shared credentials**
One password used by all team members and all environments — no accountability, can't revoke one person's access, rotation requires coordinating everyone.

---

### 2. How are secrets accessed at runtime?

```
┌─────────────────────────────────────────────────────────────────────────────────┐
│                    HOW APPLICATIONS GET SECRETS                                 │
└─────────────────────────────────────────────────────────────────────────────────┘

    ┌─────────────────┐
    │   Application   │
    │   starts up     │
    └────────┬────────┘
             │
             ▼
    ┌─────────────────────────────────────────────────────────────────────────┐
    │  1. Application assumes IAM role (via instance profile / ECS task role) │
    └────────┬────────────────────────────────────────────────────────────────┘
             │
             ▼
    ┌─────────────────────────────────────────────────────────────────────────┐
    │  2. Application calls: GetSecretValue("prod/database/credentials")      │
    └────────┬────────────────────────────────────────────────────────────────┘
             │
             ▼
    ┌─────────────────────────────────────────────────────────────────────────┐
    │  3. Secrets Manager checks the caller's IAM role:                       │
    │     • Is GetSecretValue allowed on this specific ARN? ✓                 │
    │     • Decrypt with KMS CMK (caller needs kms:Decrypt too) ✓            │
    │     • Log the access event to CloudTrail                                │
    └────────┬────────────────────────────────────────────────────────────────┘
             │
             ▼
    ┌─────────────────────────────────────────────────────────────────────────┐
    │  4. JSON secret returned — application connects to database             │
    │     No secrets in code, no environment variables, no .env files        │
    └─────────────────────────────────────────────────────────────────────────┘
```

Implemented in [`examples/secure/secrets-manager-client.py`](examples/secure/secrets-manager-client.py):
```python
import os, boto3, json, psycopg2
from functools import lru_cache

@lru_cache(maxsize=1)
def get_db_credentials(secret_name="prod/database/credentials"):
    client = boto3.client("secretsmanager", region_name=os.environ["AWS_REGION"])
    return json.loads(client.get_secret_value(SecretId=secret_name)["SecretString"])

def get_db_connection():
    creds = get_db_credentials()
    return psycopg2.connect(host=creds["host"], port=creds["port"],
                            user=creds["username"], password=creds["password"],
                            dbname=creds["dbname"])
```

---

### 3. What happens when a secret leaks?

```
┌─────────────────────────────────────────────────────────────────────────────────┐
│                    WHAT HAPPENS WHEN A SECRET LEAKS?                            │
├─────────────────────────────────────────────────────────────────────────────────┤
│                                                                                 │
│  WITHOUT PROPER MANAGEMENT:            WITH PROPER MANAGEMENT:                  │
│  ══════════════════════════            ═══════════════════════                  │
│                                                                                 │
│  Secret leaked → Attacker has:         Secret leaked → Attacker has:            │
│                                                                                 │
│  ┌────────────────────────────┐        ┌────────────────────────────┐          │
│  │ • Production database      │        │ • One specific secret      │          │
│  │ • All API keys             │        │ • That may already be      │          │
│  │ • AWS credentials          │        │   rotated (30-day cycle)   │          │
│  │ • No audit trail of use    │        │ • With full CloudTrail     │          │
│  │ • No rotation — works      │        │   showing every access     │          │
│  │   forever                  │        │ • Blast radius contained   │          │
│  └────────────────────────────┘        └────────────────────────────┘          │
│                                                                                 │
│  Response time: hours to days          Response time: ONE CLI command           │
│  Impact: CATASTROPHIC                  Impact: CONTAINED                        │
│                                                                                 │
└─────────────────────────────────────────────────────────────────────────────────┘
```

**Immediate response — one command:**
```bash
aws secretsmanager rotate-secret \
  --secret-id prod/database/credentials \
  --region us-east-1
```

Full step-by-step playbook in [`docs/incident-response.md`](docs/incident-response.md): rotate → query CloudTrail for all access → identify blast radius → revoke sessions → harden IAM conditions.

---

### 4. How does rotation reduce blast radius?

Rotation limits the damage window. A leaked credential that rotates every 30 days is usable for at most 30 days. Combined with IAM least-privilege scoping each role to a single secret ARN:

```
┌─────────────────────────────────────────────────────────────────────────────────┐
│                    AUTOMATIC SECRET ROTATION — 4-STEP PROTOCOL                  │
└─────────────────────────────────────────────────────────────────────────────────┘

    Secrets Manager invokes the Lambda 4× per rotation event:

    Step 1 — createSecret
    ┌──────────────────────────────────────────────────────────────────────┐
    │  Generate new 32-char password, store as AWSPENDING version          │
    │  AWSCURRENT still active — app is not disrupted                      │
    └──────────────────────────────────────────────────────────────────────┘
                    │
                    ▼
    Step 2 — setSecret
    ┌──────────────────────────────────────────────────────────────────────┐
    │  Connect to RDS using AWSCURRENT creds                              │
    │  ALTER USER app_user WITH PASSWORD '<new>';                         │
    │  RDS now accepts BOTH old and new password                          │
    └──────────────────────────────────────────────────────────────────────┘
                    │
                    ▼
    Step 3 — testSecret
    ┌──────────────────────────────────────────────────────────────────────┐
    │  Open a test connection to RDS using AWSPENDING creds               │
    │  Run SELECT 1 — if this fails, rotation aborts here                 │
    │  AWSCURRENT is never changed — app keeps working                    │
    └──────────────────────────────────────────────────────────────────────┘
                    │
                    ▼
    Step 4 — finishSecret
    ┌──────────────────────────────────────────────────────────────────────┐
    │  Promote AWSPENDING → AWSCURRENT                                    │
    │  Old version demoted to AWSPREVIOUS                                 │
    │  App fetches new AWSCURRENT on next GetSecretValue call             │
    └──────────────────────────────────────────────────────────────────────┘

    RESULT: Zero-downtime rotation. App never sees an invalid password.
```

See [`examples/secure/rotation-lambda.py`](examples/secure/rotation-lambda.py) for the full implementation. Rotation schedule and Lambda wiring in [`terraform/rotation.tf`](terraform/rotation.tf).

---

### 5. How is access audited?

Every call to `GetSecretValue`, `RotateSecret`, `DescribeSecret`, and `PutSecretValue` is automatically recorded in AWS CloudTrail with:

- **Who** — the IAM role ARN and session name
- **When** — timestamp to the millisecond
- **From where** — source IP address and VPC endpoint ID
- **What** — which secret ARN was accessed

```bash
# Query all secret access events in the last 24 hours
aws cloudtrail lookup-events \
  --lookup-attributes AttributeKey=EventName,AttributeValue=GetSecretValue \
  --start-time $(date -u -v-24H '+%Y-%m-%dT%H:%M:%SZ') \
  --region us-east-1 \
  --query 'Events[*].{Time:EventTime,User:Username}' \
  --output table
```

Because every workload uses a **separate IAM role** scoped to a specific secret ARN (see `terraform/iam.tf`), CloudTrail tells you exactly which service accessed which secret — not just "something used the DB password."

---

### 6. How would you handle secrets in CI/CD?

**Never store long-lived AWS access keys in CI/CD environment variables.** Instead, use IAM OIDC federation — your pipeline authenticates as itself and AWS issues temporary credentials via `sts:AssumeRoleWithWebIdentity`.

```
┌─────────────────────────────────────────────────────────────────────────────────┐
│                    CI/CD SECRET ACCESS — OIDC PATTERN                           │
└─────────────────────────────────────────────────────────────────────────────────┘

    GitHub Actions / GitLab CI
           │
           │  1. Workflow requests OIDC token from the CI provider
           ▼
    ┌─────────────────────┐
    │   OIDC ID Token     │──────────▶ AWS STS AssumeRoleWithWebIdentity
    │   (JWT, short-lived)│
    └─────────────────────┘
                                              │
                                              ▼
                                    ┌──────────────────────┐
                                    │  Temporary creds     │
                                    │  (15 min – 1 hour)   │
                                    │  via deploy IAM role │
                                    └──────────┬───────────┘
                                               │
                                               ▼
                                    ┌──────────────────────┐
                                    │  Secrets Manager     │
                                    │  GetSecretValue      │
                                    │  (read-only, scoped  │
                                    │   to deploy secrets) │
                                    └──────────────────────┘
```

**GitHub Actions example (no stored AWS keys):**
```yaml
permissions:
  id-token: write
  contents: read

jobs:
  deploy:
    steps:
      - uses: aws-actions/configure-aws-credentials@v4
        with:
          role-to-assume: arn:aws:iam::YOUR_ACCOUNT_ID:role/prod-deploy-role  # CHANGE: your AWS account ID
          aws-region: YOUR_REGION                                              # CHANGE: your AWS region

      - name: Fetch deploy secret
        run: |
          aws secretsmanager get-secret-value \
            --secret-id prod/database/credentials \
            --query SecretString --output text
```

**CI/CD IAM role policy (read-only, deploy secrets only):**
```json
{
  "Effect": "Allow",
  "Action": ["secretsmanager:GetSecretValue"],
  "Resource": "arn:aws:secretsmanager:us-east-1:*:secret:prod/deploy/*"
}
```

The deploy role can only read deployment secrets, not DB credentials or API keys. All access is logged to CloudTrail under the pipeline's role ARN.

---

## Architecture Overview

```
┌─────────────────────────────────────────────────────────────────────────────────┐
│                    SECRETS MANAGEMENT ARCHITECTURE                              │
└─────────────────────────────────────────────────────────────────────────────────┘

                    ┌──────────────────────────────────────┐
                    │          AWS SECRETS MANAGER          │
                    │   Encrypted with Customer KMS CMK    │
                    │                                      │
                    │  ┌──────────────────────────────┐   │
                    │  │ prod/database/credentials    │   │
                    │  │  username, password, host... │   │
                    │  │  auto-rotates every 30 days  │   │
                    │  └──────────────────────────────┘   │
                    │                                      │
                    │  ┌──────────────────────────────┐   │
                    │  │ prod/api/stripe              │   │
                    │  │  api_key (populated manually)│   │
                    │  └──────────────────────────────┘   │
                    └──────────────┬───────────────────────┘
                                   │
               ┌───────────────────┼───────────────────┐
               │                   │                   │
               ▼                   ▼                   ▼
       ┌───────────────┐   ┌───────────────┐   ┌───────────────┐
       │ Web App (EC2) │   │ Rotation      │   │ CI/CD         │
       │               │   │ Lambda        │   │ Pipeline      │
       │ IAM Role:     │   │               │   │               │
       │ prod-web-app  │   │ IAM Role:     │   │ IAM Role:     │
       │               │   │ rotation-role │   │ deploy-role   │
       │ GetSecretValue│   │ Get+Put+Stage │   │ GetSecretValue│
       │ db/* only     │   │ db/* only     │   │ deploy/* only │
       └───────┬───────┘   └───────┬───────┘   └───────────────┘
               │                   │
               ▼                   ▼
       ┌───────────────────────────────────┐
       │         RDS PostgreSQL            │
       │  Private subnet — no public       │
       │  access. KMS encrypted at rest.   │
       │  Password managed by rotation     │
       │  Lambda via ALTER USER.           │
       └───────────────────────────────────┘

       All traffic stays private:
       Lambda → Secrets Manager via VPC endpoint
       Lambda → KMS via VPC endpoint
       Lambda → CloudWatch Logs via VPC endpoint
       No NAT gateway. No internet egress.
```

---

## Least Privilege Access Patterns

```
┌─────────────────────────────────────────────────────────────────────────────────┐
│                    LEAST PRIVILEGE ACCESS PATTERNS                              │
├─────────────────────────────────────────────────────────────────────────────────┤
│                                                                                 │
│  WORKLOAD                       SECRETS ACCESS                                  │
│  ════════                       ══════════════                                  │
│                                                                                 │
│  ┌────────────────────┐         ┌────────────────────────────────────────┐     │
│  │ Web App (EC2)      │────────▶│ prod/database/credentials   (read)    │     │
│  └────────────────────┘         └────────────────────────────────────────┘     │
│                                                                                 │
│  ┌────────────────────┐         ┌────────────────────────────────────────┐     │
│  │ Rotation Lambda    │────────▶│ prod/database/credentials (read/write) │     │
│  └────────────────────┘         └────────────────────────────────────────┘     │
│                                                                                 │
│  ┌────────────────────┐         ┌────────────────────────────────────────┐     │
│  │ CI/CD Pipeline     │────────▶│ prod/deploy/*               (read)    │     │
│  └────────────────────┘         └────────────────────────────────────────┘     │
│                                                                                 │
│  PRINCIPLE: Each IAM policy Resource field is a specific secret ARN —          │
│  not "*". A compromised web app role cannot read the Stripe key.               │
│                                                                                 │
└─────────────────────────────────────────────────────────────────────────────────┘
```

---

## Project Structure

```
aws-secrets-management/
├── .gitignore                         # Excludes tfstate, .env, tfvars, lambda zips
├── README.md
│
├── examples/
│   ├── insecure/
│   │   ├── hardcoded-creds.py         # Anti-pattern 1: credentials in source code
│   │   └── env-file-example.py        # Anti-pattern 2: .env files and env vars
│   └── secure/
│       ├── secrets-manager-client.py  # Production boto3 client with lru_cache
│       └── rotation-lambda.py         # 4-step rotation with real psycopg2 RDS logic
│
├── terraform/
│   ├── backend.tf                     # S3 remote state + DynamoDB locking
│   ├── provider.tf                    # AWS, archive, random, null providers
│   ├── variables.tf                   # All input variables with descriptions
│   ├── terraform.tfvars.example       # Copy to terraform.tfvars and fill in
│   ├── kms.tf                         # CMK for Secrets Manager + CMK for RDS storage
│   ├── networking.tf                  # VPC, private subnets, SGs, 3 VPC endpoints
│   ├── rds.tf                         # PostgreSQL RDS instance (private, encrypted)
│   ├── secrets.tf                     # Secret containers + initial seeded versions
│   ├── iam.tf                         # Least-privilege roles for web app + Lambda
│   └── rotation.tf                    # Lambda build (pip install), zip, deploy, schedule
│
└── docs/
    ├── migration-guide.md             # 6-step playbook: hardcoded → Secrets Manager
    ├── rotation-setup.md              # How rotation works, manual trigger, troubleshoot
    └── incident-response.md           # Breach response: rotate → audit → contain → harden
```

---

## Prerequisites

- AWS account (admin or power-user access)
- AWS CLI configured (`aws configure`)
- Terraform >= 1.5
- Python 3.9+ and `pip3`
- Git

**Backend infrastructure (must exist before `terraform init`):**

| Resource | Name | Purpose |
|---|---|---|
| S3 bucket | `your-bucket-name` (set in `backend.tf`) | Stores `terraform.tfstate` |
| DynamoDB table | `your-lock-table` (set in `backend.tf`) | State locking (hash key: `LockID`) |

---

## How to Deploy

### Step 1 — Clone and configure

```bash
git clone https://github.com/YOUR_GITHUB_USERNAME/aws-secrets-management.git  # CHANGE: your GitHub username
cd aws-secrets-management/terraform
cp terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars — all values have defaults except none required
```

### Step 2 — Deploy

```bash
terraform init    # connects to S3 backend, downloads providers
terraform plan -var-file=terraform.tfvars -out=tfplan
terraform apply tfplan
```

Terraform provisions 29 resources. RDS takes the longest (~5–8 minutes).

### Step 3 — Verify the deployment

```bash
# Confirm the seeded secret contains real RDS connection details
aws secretsmanager get-secret-value \
  --secret-id prod/database/credentials \
  --query SecretString --output text \
  --region us-east-1 | python3 -m json.tool

# Test least-privilege: assume the web app role
CREDS=$(aws sts assume-role \
  --role-arn arn:aws:iam::$(aws sts get-caller-identity --query Account --output text):role/prod-web-app-role \
  --role-session-name test-session --query Credentials --output json)

export AWS_ACCESS_KEY_ID=$(echo $CREDS | python3 -c "import sys,json; print(json.load(sys.stdin)['AccessKeyId'])")
export AWS_SECRET_ACCESS_KEY=$(echo $CREDS | python3 -c "import sys,json; print(json.load(sys.stdin)['SecretAccessKey'])")
export AWS_SESSION_TOKEN=$(echo $CREDS | python3 -c "import sys,json; print(json.load(sys.stdin)['SessionToken'])")

# Should SUCCEED (role has permission)
aws secretsmanager get-secret-value --secret-id prod/database/credentials --region us-east-1

# Should FAIL with AccessDeniedException (least privilege working correctly)
aws secretsmanager get-secret-value --secret-id prod/api/stripe --region us-east-1

unset AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY AWS_SESSION_TOKEN
```

### Step 4 — Trigger and verify rotation

```bash
# Clear any stuck AWSPENDING version first (only needed if a previous rotation failed)
PENDING_ID=$(aws secretsmanager describe-secret \
  --secret-id prod/database/credentials --region us-east-1 \
  --query 'VersionIdsToStages' --output json | \
  python3 -c "import sys,json; [print(v) for v,s in json.load(sys.stdin).items() if 'AWSPENDING' in s]")
[ -n "$PENDING_ID" ] && \
  aws secretsmanager update-secret-version-stage \
    --secret-id prod/database/credentials \
    --version-stage AWSPENDING \
    --remove-from-version-id "$PENDING_ID" \
    --region us-east-1

# Trigger rotation
aws secretsmanager rotate-secret \
  --secret-id prod/database/credentials \
  --region us-east-1

# Stream Lambda logs — expect 4 success lines
aws logs tail /aws/lambda/prod-secret-rotation --follow --region us-east-1
```

Expected log output:
```
createSecret: Created AWSPENDING version.
setSecret: Password updated in database for user app_user
testSecret: New credentials verified successfully.
finishSecret: Rotation complete.
```

### Step 5 — Verify the audit trail

```bash
aws cloudtrail lookup-events \
  --lookup-attributes AttributeKey=EventName,AttributeValue=GetSecretValue \
  --start-time $(date -u -v-1H '+%Y-%m-%dT%H:%M:%SZ') \
  --region us-east-1 \
  --query 'Events[*].{Time:EventTime,User:Username}' \
  --output table
```

---

## Before & After: Code Comparison

**Before — `examples/insecure/hardcoded-creds.py`**
```python
# ANTI-PATTERN: credentials committed to git history forever
DB_HOST = "prod-db.example.com"
DB_USER = "admin"
DB_PASS = "SuperSecretPassword123!"

conn = psycopg2.connect(host=DB_HOST, user=DB_USER, password=DB_PASS)
# No rotation. No audit trail. One leaked repo = full database access.
```

**After — `examples/secure/secrets-manager-client.py`**
```python
import os, boto3, json, psycopg2
from functools import lru_cache

@lru_cache(maxsize=1)
def get_db_credentials(secret_name="prod/database/credentials"):
    client = boto3.client("secretsmanager", region_name=os.environ["AWS_REGION"])
    return json.loads(client.get_secret_value(SecretId=secret_name)["SecretString"])

conn = psycopg2.connect(**{k: get_db_credentials()[k]
                           for k in ("host","port","username","password","dbname")})
# No secrets in code. IAM role grants access. Every call audited via CloudTrail.
```

---

## Key Technical Decisions

| Decision | Why |
|---|---|
| Two separate KMS keys (secrets + RDS) | Each key has its own policy and rotation schedule — RDS access doesn't imply Secrets Manager access |
| VPC interface endpoints instead of NAT gateway | Lambda stays fully private; no internet egress needed; aligned with least-privilege networking |
| `psycopg2-binary` bundled in Lambda zip | Klayers `psycopg` layer requires system `libpq` which Lambda doesn't provide; bundling the binary avoids any OS dependency |
| `pip3 --platform manylinux2014_x86_64` | Downloads the Linux x86_64 wheel on macOS without Docker, producing the correct binary for Lambda's Amazon Linux runtime |
| `lifecycle { ignore_changes = [secret_string] }` | Prevents Terraform from overwriting the rotated password on subsequent `apply` runs |
| `aws_caller_identity` in web app trust policy | Allows IAM users in the account to assume the role for CLI testing, while EC2 is the production principal |

---

## Teardown

```bash
cd terraform
terraform destroy -var-file=terraform.tfvars
```

> **Note:** The S3 bucket and DynamoDB table (set in `backend.tf`) are not managed by this Terraform config — they must be deleted manually if no longer needed.

---

## Further Reading

- [AWS Secrets Manager Best Practices](https://docs.aws.amazon.com/secretsmanager/latest/userguide/best-practices.html)
- [Rotation function templates (AWS)](https://docs.aws.amazon.com/secretsmanager/latest/userguide/reference_available-rotation-templates.html)
- [OWASP Secrets Management Cheat Sheet](https://cheatsheetseries.owasp.org/cheatsheets/Secrets_Management_Cheat_Sheet.html)
- [AWS KMS Key Rotation](https://docs.aws.amazon.com/kms/latest/developerguide/rotate-keys.html)
- [GitHub OIDC with AWS](https://docs.github.com/en/actions/security-for-github-actions/security-hardening-your-deployments/configuring-openid-connect-in-amazon-web-services)
