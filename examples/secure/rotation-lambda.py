import boto3
import json
import logging
import string
import secrets

import psycopg2
from psycopg2 import sql

logger = logging.getLogger()
logger.setLevel(logging.INFO)

CONNECT_TIMEOUT_SECONDS = 5


def lambda_handler(event, context):
    """AWS Secrets Manager rotation Lambda - 4-step pattern."""
    arn = event["SecretId"]
    token = event["ClientRequestToken"]
    step = event["Step"]

    client = boto3.client("secretsmanager")
    metadata = client.describe_secret(SecretId=arn)

    if step == "createSecret":
        create_secret(client, arn, token)
    elif step == "setSecret":
        set_secret(client, arn, token)
    elif step == "testSecret":
        test_secret(client, arn, token)
    elif step == "finishSecret":
        finish_secret(client, arn, token, metadata)


def create_secret(client, arn, token):
    """Generate new password and store as AWSPENDING."""
    try:
        client.get_secret_value(SecretId=arn, VersionStage="AWSPENDING", VersionId=token)
        logger.info("createSecret: AWSPENDING already exists, skipping.")
        return
    except client.exceptions.ResourceNotFoundException:
        pass

    current = json.loads(
        client.get_secret_value(SecretId=arn, VersionStage="AWSCURRENT")["SecretString"]
    )
    current["password"] = generate_password()

    client.put_secret_value(
        SecretId=arn,
        ClientRequestToken=token,
        SecretString=json.dumps(current),
        VersionStages=["AWSPENDING"]
    )
    logger.info("createSecret: Created AWSPENDING version.")


def set_secret(client, arn, token):
    """Apply new password to the actual database."""
    pending = json.loads(
        client.get_secret_value(SecretId=arn, VersionStage="AWSPENDING", VersionId=token)["SecretString"]
    )
    current = json.loads(
        client.get_secret_value(SecretId=arn, VersionStage="AWSCURRENT")["SecretString"]
    )

    # Connect with the still-valid AWSCURRENT credentials and change the
    # password to the AWSPENDING value. Postgres keeps both passwords valid
    # until this ALTER completes, so in-flight connections aren't dropped.
    # NOSONAR (python:S6243): a per-invocation connection is intentional here -
    # each rotation step uses different, short-lived credentials.
    conn = psycopg2.connect(
        host=current["host"],
        port=current["port"],
        dbname=current["dbname"],
        user=current["username"],
        password=current["password"],
        connect_timeout=CONNECT_TIMEOUT_SECONDS,
    )
    try:
        conn.autocommit = True
        with conn.cursor() as cur:
            cur.execute(
                sql.SQL("ALTER USER {} WITH PASSWORD %s").format(sql.Identifier(pending["username"])),
                (pending["password"],),
            )
    finally:
        conn.close()

    logger.info(f"setSecret: Password updated in database for user {pending['username']}")


def test_secret(client, arn, token):
    """Verify the new password actually works."""
    pending = json.loads(
        client.get_secret_value(SecretId=arn, VersionStage="AWSPENDING", VersionId=token)["SecretString"]
    )

    # NOSONAR (python:S6243): per-invocation connection is intentional, see set_secret.
    conn = psycopg2.connect(
        host=pending["host"],
        port=pending["port"],
        dbname=pending["dbname"],
        user=pending["username"],
        password=pending["password"],
        connect_timeout=CONNECT_TIMEOUT_SECONDS,
    )
    try:
        with conn.cursor() as cur:
            cur.execute("SELECT 1")
            cur.fetchone()
    finally:
        conn.close()

    logger.info("testSecret: New credentials verified successfully.")


def finish_secret(client, arn, token, metadata):
    """Promote AWSPENDING to AWSCURRENT."""
    current_version = next(
        v for v, stages in metadata["VersionIdsToStages"].items()
        if "AWSCURRENT" in stages
    )
    client.update_secret_version_stage(
        SecretId=arn,
        VersionStage="AWSCURRENT",
        MoveToVersionId=token,
        RemoveFromVersionId=current_version
    )
    logger.info("finishSecret: Rotation complete.")


def generate_password(length=32):
    alphabet = string.ascii_letters + string.digits + "!@#$%^&*()"
    return "".join(secrets.choice(alphabet) for _ in range(length))
