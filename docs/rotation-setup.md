# Secret Rotation Setup

## How rotation works in this project

Secrets Manager invokes the rotation Lambda four times per rotation event, once per step:

| Step | Lambda function | What happens |
|---|---|---|
| `createSecret` | `create_secret` | Reads AWSCURRENT, generates new 32-char password, stores as AWSPENDING |
| `setSecret` | `set_secret` | Connects to RDS with AWSCURRENT creds, runs `ALTER USER ... WITH PASSWORD` |
| `testSecret` | `test_secret` | Opens a connection with AWSPENDING creds, runs `SELECT 1` to verify |
| `finishSecret` | `finish_secret` | Promotes AWSPENDING → AWSCURRENT; old version becomes AWSPREVIOUS |

During the `setSecret`/`testSecret` overlap window, the RDS instance accepts **both** the old and new passwords so in-flight app connections are not dropped.

## Schedule

Automatic rotation is set to every **30 days** via `aws_secretsmanager_secret_rotation.db_rotation` in `terraform/rotation.tf`.

## Trigger rotation manually (testing / emergency)

```bash
aws secretsmanager rotate-secret \
  --secret-id prod/database/credentials \
  --region us-east-1
```

## Watch rotation in real time (CloudWatch Logs)

```bash
# Stream the Lambda logs — run this before triggering rotation
aws logs tail /aws/lambda/prod-secret-rotation \
  --follow \
  --region us-east-1
```

Expected log sequence for a successful rotation:
```
createSecret: Created AWSPENDING version.
setSecret: Password updated in database for user app_user
testSecret: New credentials verified successfully.
finishSecret: Rotation complete.
```

## Check current secret version stages

```bash
aws secretsmanager describe-secret \
  --secret-id prod/database/credentials \
  --query "VersionIdsToStages" \
  --region us-east-1
```

You should see one version labelled `AWSCURRENT` and, during active rotation, one labelled `AWSPENDING`.

## psycopg2 Lambda Layer

The rotation function depends on `psycopg2` which is not bundled in the AWS Python 3.11 runtime.
The layer ARN is set in `terraform/terraform.tfvars` via the `psycopg2_layer_arn` variable.

Get the latest prebuilt ARN for your region from:
https://github.com/keithrozario/Klayers/tree/master/deployments/python3.11

## Troubleshooting a failed rotation

1. Check the Lambda logs (command above) for the step that failed.
2. Common causes:
   - **Lambda cannot reach RDS** — verify VPC endpoints are `available` and the RDS security group allows port 5432 from the Lambda security group.
   - **`testSecret` fails** — RDS did not accept the new password; check whether `setSecret` actually ran the `ALTER USER` successfully.
   - **KMS access denied** — verify the rotation Lambda IAM role has `kms:Decrypt` and `kms:GenerateDataKey` on the secrets KMS key.
3. Secrets Manager will **not** promote AWSPENDING to AWSCURRENT if any step raises an exception, so the existing password stays valid and your app is not affected.
