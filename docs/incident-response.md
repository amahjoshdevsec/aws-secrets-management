# Incident Response — Secret Leak Playbook

Use this guide if a secret managed by this project is exposed (committed to git, leaked in logs, shared externally, etc.).

## Severity levels

| Signal | Severity |
|---|---|
| Secret committed to a private repo, caught immediately | Medium |
| Secret committed to a public repo or shared externally | High |
| Evidence of unauthorised access in CloudTrail | Critical |

---

## Immediate response (first 5 minutes)

### 1 — Rotate the secret immediately

```bash
aws secretsmanager rotate-secret \
  --secret-id prod/database/credentials \
  --region us-east-1
```

This triggers the Lambda rotation flow (create → set → test → finish) and invalidates the old password. Do this before investigating — contain the exposure first.

### 2 — Verify rotation completed

```bash
aws logs tail /aws/lambda/prod-secret-rotation \
  --since 5m \
  --region us-east-1
```

Look for `finishSecret: Rotation complete.` If rotation fails, rotate the RDS master password directly via the AWS console and update the secret manually:

```bash
aws secretsmanager put-secret-value \
  --secret-id prod/database/credentials \
  --secret-string '{"username":"app_user","password":"<new-password>","host":"...","port":5432,"dbname":"appdb"}' \
  --region us-east-1
```

---

## Investigation (first 30 minutes)

### 3 — Query CloudTrail for all access to the leaked secret

```bash
# All GetSecretValue calls in the last 24 hours
aws cloudtrail lookup-events \
  --lookup-attributes AttributeKey=EventName,AttributeValue=GetSecretValue \
  --start-time $(date -u -v-24H '+%Y-%m-%dT%H:%M:%SZ') \
  --region us-east-1 \
  --query 'Events[*].{Time:EventTime,User:Username,IP:CloudTrailEvent}' \
  --output table
```

```bash
# Full detail on a specific event (paste the event ID from above)
aws cloudtrail lookup-events \
  --lookup-attributes AttributeKey=EventId,AttributeValue=<event-id> \
  --region us-east-1 \
  --output json | jq '.'
```

Key things to look for:
- `sourceIPAddress` — was the access from an expected IP range / VPC?
- `userIdentity.arn` — which IAM role/user made the call?
- `errorCode` — `AccessDenied` entries indicate probing attempts

### 4 — Check RDS audit logs for unauthorised queries

In the AWS console: **RDS → your instance → Logs & events → PostgreSQL logs**

Look for connections from unexpected hosts, unusual query patterns, or bulk data reads.

### 5 — Identify blast radius

Because the IAM policy in `terraform/iam.tf` scopes `GetSecretValue` to a **single secret ARN**, a compromised `prod-web-app-role` can only access `prod/database/credentials` — not the Stripe key, not other secrets in the account.

Confirm this by checking what the role can access:
```bash
aws iam simulate-principal-policy \
  --policy-source-arn arn:aws:iam::<ACCOUNT_ID>:role/prod-web-app-role \
  --action-names secretsmanager:GetSecretValue \
  --resource-arns "*" \
  --region us-east-1
```

---

## Containment (within 1 hour)

### 6 — Revoke all active sessions using the leaked credential

```bash
# Attach an explicit deny policy to the role to cut off all active sessions
aws iam put-role-policy \
  --role-name prod-web-app-role \
  --policy-name EmergencyDeny \
  --policy-document '{
    "Version":"2012-10-17",
    "Statement":[{"Effect":"Deny","Action":"*","Resource":"*"}]
  }'
```

Remove the deny policy once you have verified all sessions are cleared and the new credential is in place.

### 7 — Notify the security team

Include in your notification:
- When the exposure was first possible (git commit time / log timestamp)
- Which CloudTrail events show actual access (step 3 above)
- What data the DB user can access (SELECT on which tables?)
- Whether rotation has completed

---

## Post-incident hardening

### 8 — Tighten IAM conditions

Add IP-range or VPC conditions to the web app policy so only traffic from your VPC can assume the role:

```json
{
  "Effect": "Allow",
  "Action": ["secretsmanager:GetSecretValue"],
  "Resource": "arn:aws:secretsmanager:us-east-1:<ACCOUNT>:secret:prod/database/credentials-*",
  "Condition": {
    "StringEquals": {"aws:SourceVpc": "vpc-xxxxxxxx"}
  }
}
```

### 9 — Enable CloudTrail alerting

Set up a CloudWatch metric filter to alert on any `GetSecretValue` call outside business hours or from an unexpected principal:

```bash
aws cloudwatch put-metric-alarm \
  --alarm-name "UnexpectedSecretAccess" \
  --metric-name SecretAccessCount \
  --namespace SecretsManager \
  --statistic Sum \
  --period 300 \
  --threshold 1 \
  --comparison-operator GreaterThanOrEqualToThreshold \
  --alarm-actions <sns-topic-arn>
```

### 10 — Review and shorten rotation schedule

Change `automatically_after_days` in `terraform/rotation.tf` from 30 to 7 days for a period following the incident, then run:

```bash
cd terraform
terraform apply -var-file=terraform.tfvars
```
