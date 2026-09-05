import os
import time
from functools import wraps

import jwt
from flask import request, jsonify
from google.oauth2 import id_token as google_id_token
from google.auth.transport import requests as google_requests

# The Google Cloud "OAuth Client ID" for this app. Used to check that a
# Google credential was actually issued for LineTracker (and not some
# other app pretending to be us).
GOOGLE_CLIENT_ID = os.environ.get("GOOGLE_CLIENT_ID")

# Our OWN signing secret for LineTracker's session tokens — separate from
# Google entirely. A random, private string; set it in the environment
# and never commit it. If this leaks, anyone could forge a session for
# any email, so treat it like a password.
JWT_SECRET = os.environ.get("JWT_SECRET")

SESSION_DAYS = 30


def verify_google_token(credential):
    """Verify a Google ID token (the `credential` string handed back by
    Google's "Sign in with Google" button) and return the verified,
    lowercased email — or None if it's invalid, expired, or was issued
    for a different app than this one.

    This is the step that actually proves "this really is that Google
    account," not just "someone typed this email into a box."
    """
    if not credential or not GOOGLE_CLIENT_ID:
        return None
    try:
        info = google_id_token.verify_oauth2_token(
            credential, google_requests.Request(), GOOGLE_CLIENT_ID
        )
    except Exception as e:
        print(f"[auth] Google token verification failed: {e}")
        return None

    if not info.get("email_verified", False):
        print("[auth] Google account email is not verified, rejecting")
        return None

    email = (info.get("email") or "").strip().lower()
    return email or None


def issue_session_token(email):
    """Create LineTracker's own signed session token for an already-
    verified email. Google's own ID token is short-lived (~1 hour), so we
    don't want the frontend to have to re-run the Google sign-in flow
    constantly — this token is what the frontend actually holds onto and
    sends with every request afterward.
    """
    payload = {
        "email": email,
        "iat": int(time.time()),
        "exp": int(time.time()) + SESSION_DAYS * 86400,
    }
    return jwt.encode(payload, JWT_SECRET, algorithm="HS256")


def require_auth(fn):
    """Route decorator: reject the request with 401 unless it carries a
    valid `Authorization: Bearer <token>` header issued by
    issue_session_token(). On success, sets request.user_email to the
    verified email so the route never has to trust anything the client
    sent about who it is.
    """

    @wraps(fn)
    def wrapper(*args, **kwargs):
        auth_header = request.headers.get("Authorization", "")
        if not auth_header.startswith("Bearer "):
            return jsonify({"error": "Missing or invalid Authorization header"}), 401

        token = auth_header[len("Bearer "):].strip()
        try:
            payload = jwt.decode(token, JWT_SECRET, algorithms=["HS256"])
        except jwt.ExpiredSignatureError:
            return jsonify({"error": "Session expired, please sign in again"}), 401
        except jwt.InvalidTokenError:
            return jsonify({"error": "Invalid session token"}), 401

        request.user_email = payload["email"]
        return fn(*args, **kwargs)

    return wrapper
