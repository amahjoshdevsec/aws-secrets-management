# examples/insecure/hardcoded-creds.py
# ANTI-PATTERN: NEVER DO THIS IN PRODUCTION

import psycopg2

# Hardcoded credentials - will end up in git history forever
DB_HOST = "prod-db.example.com"
DB_USER = "admin"
DB_PASS = "SuperSecretPassword123!"
API_KEY  = "sk-live-abc123def456"

conn = psycopg2.connect(host=DB_HOST, user=DB_USER, password=DB_PASS)

# Problems:
# - Credentials are committed to source control and live in git history forever,
#   even if removed in a later commit
# - No rotation: changing the password means a code change + redeploy
# - No audit trail: anyone with repo access has the credentials, with no record
#   of who used them or when
# - Leaked credentials (e.g. via a public repo, screen share, or laptop theft)
#   grant immediate, unrestricted access until manually revoked
