import os
import sys
from datetime import datetime

# Render (and most hosting platforms) capture stdout in a way that fully
# buffers print() instead of flushing it line-by-line, so log lines can sit
# in memory for a long time before showing up in the dashboard — making it
# look like nothing happened when it actually did. Force every print() to
# flush immediately so log timestamps are trustworthy.
sys.stdout.reconfigure(line_buffering=True)

from flask import Flask, jsonify, request
from flask_cors import CORS
import yfinance as yf
import requests
import time

from dotenv import load_dotenv
load_dotenv()

from flask_apscheduler import APScheduler
from sqlalchemy import inspect, text
from notifications import send_alert_email

from models import db, Alert, UserSettings
from scheduler import poll_alerts
from auth import verify_google_token, verify_apple_token, issue_session_token, require_auth

app = Flask(__name__)
CORS(app)

sports_cache = {}
CACHE_TTL = 150  # cache results for 5 minutes

# --- Database config ---
app.config["SQLALCHEMY_DATABASE_URI"] = os.environ.get(
    "DATABASE_URL",
    "sqlite:///lineminder.db"
)
app.config["SQLALCHEMY_TRACK_MODIFICATIONS"] = False

# Supabase's connection pooler silently closes a connection that's sat
# idle too long. SQLAlchemy's default pool doesn't know that and hands
# the now-dead connection straight back out on the next request, which is
# what was surfacing as
#   sqlalchemy.exc.OperationalError: (psycopg2.OperationalError)
#   SSL SYSCALL error: EOF detected
# pool_pre_ping makes it run a cheap "is this connection actually still
# alive?" check before reusing one, transparently reconnecting if not.
# pool_recycle proactively retires a connection after 5 minutes regardless
# (comfortably under Supabase's own idle-close window), so we replace
# connections on our own schedule instead of finding out the hard way.
# This matters more now than it used to -- keeping the backend alive 24/7
# (to dodge Render's free-tier spin-down) means the worker process, and
# the connections it opened, now live far longer uninterrupted than they
# did when Render was restarting the process on every wake-up.
app.config["SQLALCHEMY_ENGINE_OPTIONS"] = {
    "pool_pre_ping": True,
    "pool_recycle": 300,
}

db.init_app(app)

with app.app_context():
    db.create_all()

    # db.create_all() only creates tables that don't exist yet — it won't add
    # new columns to a table that's already there (e.g. on the Render Postgres
    # database). This adds any columns the models define but the live table
    # is missing, so existing deployments pick up schema changes like
    # Alert.live_value without a manual migration step.
    inspector = inspect(db.engine)
    existing_columns = {col["name"] for col in inspector.get_columns("alerts")}
    model_columns = {col.name: col for col in Alert.__table__.columns}
    missing = model_columns.keys() - existing_columns
    if missing:
        with db.engine.connect() as conn:
            for name in missing:
                col_type = model_columns[name].type.compile(dialect=db.engine.dialect)
                conn.execute(text(f"ALTER TABLE alerts ADD COLUMN {name} {col_type}"))
            conn.commit()
        print(f"[migrate] Added missing alerts column(s): {', '.join(sorted(missing))}")

# --- Config ---
SHARP_API_KEY = os.environ.get("SHARP_API_KEY", "")
SHARP_API_BASE = "https://api.sharpapi.io/api/v1"

# Map from our internal sport keys to SharpAPI league IDs
SPORT_TO_SHARP = {
    "basketball_nba": "nba",
    "americanfootball_nfl": "nfl",
    "americanfootball_cfl": "cfl",
    "soccer_epl": "england_-_premier_league",
    "icehockey_nhl": "nhl",
    "baseball_mlb": "mlb",
    "soccer_uefa_champs_league": "uefa_-_champions_league",
    "basketball_wnba": "wnba",
    "soccer_fifa_world_cup": "fifa_-_world_cup",
    "soccer_mls": "usa_-_major_league_soccer",
}


@app.route("/")
def home():
    return jsonify({"status": "ok", "message": "LineTracker backend is running"})


# --- Stock route ---
@app.route("/stocks/price", methods=["GET"])
def get_stock_price():
    ticker = request.args.get("ticker")

    # Check if a valid ticker has been given
    if not ticker:
        return jsonify({"error": "Missing required query param: ticker"}), 400

    # Request Yahoo Finance for the latest info on the stock
    try:
        stock = yf.Ticker(ticker.upper())

        try:
            info = stock.fast_info
            price = info.get("lastPrice")
        except Exception:
            # fast_info failed, fall back to history
            hist = stock.history(period="1d")
            if hist.empty:
                return jsonify({"error": f"No price data found for ticker '{ticker}'"}), 404
            price = round(hist["Close"].iloc[-1], 2)
            return jsonify({
                "ticker": ticker.upper(),
                "price": price,
                "currency": "USD",
                "previous_close": None,
            })
        if price is None:
            return jsonify({"error": f"No price data found for ticker '{ticker}'"}), 404

        return jsonify({
            "ticker": ticker.upper(),
            "price": round(price, 2),
            "currency": info.get("currency", "USD"),
            "previous_close": round(info.get("previousClose", 0), 2) if info.get("previousClose") else None,
        })

    except Exception as e:
        return jsonify({"error": f"Failed to fetch stock data: {str(e)}"}), 500


# --- Odds route ---
def _team_name_matches(a, b):
    """Case/whitespace-insensitive, abbreviation-tolerant team name match
    (same approach as _outcome_matches in scheduler.py) — "New York
    Rangers" and "NY Rangers" should count as the same team even though
    they're different strings."""
    a = (a or "").strip().casefold()
    b = (b or "").strip().casefold()
    if not a or not b:
        return False
    if a == b:
        return True
    a_last = a.split()[-1] if a.split() else a
    b_last = b.split()[-1] if b.split() else b
    return a.endswith(b_last) or b.endswith(a_last)


def _same_real_game(ev1, ev2):
    """True if two DIFFERENT event_ids actually refer to the same
    real-world game. Confirmed case: SharpAPI generated two event_ids for
    one Bruins @ Rangers game — "nhl_bruins_rangers_..." and
    "nhl_bruins_nyrangers_..." — because their own ID generation baked in
    an inconsistent abbreviation for the Rangers. Matching event_id alone
    can't catch that, since the IDs themselves are genuinely different.

    Two signals together are what make this trustworthy: matching team
    names AND a start time within an hour of each other. Either signal
    alone has a plausible failure mode (team names can be formatted
    differently for the same game; two real games can share a start
    hour), but two real, distinct games between the same two teams
    essentially never happen within an hour of each other.
    """
    if not _team_name_matches(ev1["home_team"], ev2["home_team"]):
        return False
    if not _team_name_matches(ev1["away_team"], ev2["away_team"]):
        return False

    t1, t2 = ev1.get("commence_time"), ev2.get("commence_time")
    if not t1 or not t2:
        return False
    try:
        dt1 = datetime.fromisoformat(t1.replace("Z", "+00:00"))
        dt2 = datetime.fromisoformat(t2.replace("Z", "+00:00"))
    except (ValueError, AttributeError):
        return False

    return abs((dt1 - dt2).total_seconds()) <= 3600


@app.route("/odds", methods=["GET"])
def get_odds():

    sport = request.args.get("sport", "baseball_mlb")
    market = request.args.get("market", "h2h")

    cache_key = f"{sport}_{market}"
    now = time.time()
    if cache_key in sports_cache:
        cached_time, cached_data = sports_cache[cache_key]
        if now - cached_time < CACHE_TTL:
            return jsonify(cached_data)

    league = SPORT_TO_SHARP.get(sport)
    if not league:
        return jsonify({"error": f"Unsupported sport: {sport}"}), 400

    # Map our market keys to SharpAPI market types
    market_map = {
        "h2h": "moneyline",
        "spreads": "spread",
        "totals": "total",
    }
    sharp_market = market_map.get(market, "moneyline")

    if not SHARP_API_KEY:
        return jsonify({"error": "SHARP_API_KEY is not set"}), 500

    headers = {"X-API-Key": SHARP_API_KEY}
    all_rows = []
    offset = 0
    limit = 50

    # Paginate through all results
    try:
        while True:
            url = f"{SHARP_API_BASE}/odds"
            params = {
                "league": league,
                "market_type": sharp_market,
                "is_main_line": "true",
                "limit": limit,
                "offset": offset,
            }
            response = requests.get(url, headers=headers, params=params, timeout=10)
            response.raise_for_status()
            data = response.json()
            rows = data.get("data", [])
            all_rows.extend(rows)

            pagination = data.get("pagination", {})
            if not pagination.get("has_more"):
                break
            offset += limit
            time.sleep(0.5)

    except requests.exceptions.RequestException as e:
        return jsonify({"error": f"Failed to fetch odds: {str(e)}"}), 500

    # Group flat rows into events → bookmakers → markets → outcomes
    events_map = {}

    # Builds events_map
    for row in all_rows:

        event_id = row.get("event_id")

        if not event_id:
            continue

        # Group by SharpAPI's own event_id, not a team-name/date string — two
        # different bookmakers can format home_team/away_team slightly
        # differently for the exact same game (abbreviation vs full name,
        # different casing, etc.), which was splitting one real game into
        # two duplicate cards. event_id is the canonical identifier and is
        # already what every other part of this app (scheduler.py) uses to
        # match odds back to a specific game.
        event_key = event_id

        if event_key not in events_map:
            home_name = (row.get("home") or {}).get("name") or row.get("home_team", "")
            away_name = (row.get("away") or {}).get("name") or row.get("away_team", "")
            home_logo = (row.get("home") or {}).get("logo", "")
            away_logo = (row.get("away") or {}).get("logo", "")
            events_map[event_key] = {
                "id": event_id,
                "sport": sport,
                "commence_time": row.get("event_start_time"),
                "home_team": home_name,
                "away_team": away_name,
                "home_logo": home_logo,
                "away_logo": away_logo,
                "bookmakers": {},
                }

        # Update with full names if we get a FanDuel row (which has home/away objects)
        if row.get("home") and not events_map[event_key]["home_team"].count(" ") > 1:
            events_map[event_key]["home_team"] = row["home"]["name"]
        if row.get("away") and not events_map[event_key]["away_team"].count(" ") > 1:
            events_map[event_key]["away_team"] = row["away"]["name"]

        # Use full name from home/away objects if available, otherwise use home_team field
        if not events_map[event_key]["home_team"] and row.get("home"):
            events_map[event_key]["home_team"] = row["home"]["name"]
        if not events_map[event_key]["away_team"] and row.get("away"):
            events_map[event_key]["away_team"] = row["away"]["name"]

        sportsbook_key = row.get("sportsbook")
        sportsbook_label = (row.get("sportsbook_ref") or {}).get("label") or sportsbook_key.title()

        if sportsbook_key not in events_map[event_key]["bookmakers"]:
            events_map[event_key]["bookmakers"][sportsbook_key] = {
                "title": sportsbook_label,
                "markets": {
                    market: {"key": market, "outcomes": []}
                },
            }

        if market not in events_map[event_key]["bookmakers"][sportsbook_key]["markets"]:
            events_map[event_key]["bookmakers"][sportsbook_key]["markets"][market] = {
                "key": market,
                "outcomes": [],
            }

        # Use full name from home/away objects if selection matches abbreviated name
        selection = row.get("selection", "")
        home_obj = row.get("home") or {}
        away_obj = row.get("away") or {}
        if home_obj.get("name") and selection == row.get("home_team"):
            selection = home_obj["name"]
        elif away_obj.get("name") and selection == row.get("away_team"):
            selection = away_obj["name"]

        selection_type = row.get("selection_type", "")
        if selection_type == "home":
            logo = (row.get("home") or {}).get("logo", "")
        elif selection_type == "away":
            logo = (row.get("away") or {}).get("logo", "")
        else:
            logo = ""

        if "Montreal" in (row.get("home_team") or "") or "Montreal" in (row.get("selection") or ""):
            print(f"[debug] Montreal row: selection={row.get('selection')}, selection_type={row.get('selection_type')}, home_team={row.get('home_team')}, away_team={row.get('away_team')}, logo={logo}")

        events_map[event_key]["bookmakers"][sportsbook_key]["markets"][market]["outcomes"].append({
            "name": selection,
            "price": row.get("odds_american"),
            "logo": logo
        })

    # Merge near-duplicate events — same real game listed under two
    # different event_ids (see _same_real_game for why event_id alone
    # isn't reliable enough to catch this). Merge rather than drop one
    # outright, so odds/bookmakers attached to either id are kept.
    event_ids = list(events_map.keys())
    dropped_ids = set()
    for i, id1 in enumerate(event_ids):
        if id1 in dropped_ids:
            continue
        for id2 in event_ids[i + 1:]:
            if id2 in dropped_ids:
                continue
            if not _same_real_game(events_map[id1], events_map[id2]):
                continue
            print(f"[odds] Merging duplicate event listing: {id2!r} into {id1!r} "
                  f"({events_map[id1]['home_team']} vs {events_map[id1]['away_team']})")
            for bm_key, bm_val in events_map[id2]["bookmakers"].items():
                if bm_key not in events_map[id1]["bookmakers"]:
                    events_map[id1]["bookmakers"][bm_key] = bm_val
                    continue
                for mkt_key, mkt_val in bm_val["markets"].items():
                    dest_markets = events_map[id1]["bookmakers"][bm_key]["markets"]
                    if mkt_key not in dest_markets:
                        dest_markets[mkt_key] = mkt_val
                    else:
                        dest_markets[mkt_key]["outcomes"].extend(mkt_val["outcomes"])
            del events_map[id2]
            dropped_ids.add(id2)

    # After the for loop that builds events_map, add this:
    for event in events_map.values():
        home_full = event["home_team"]
        away_full = event["away_team"]
        for bm in event["bookmakers"].values():
            for mkt in bm["markets"].values():
                for outcome in mkt["outcomes"]:
                    name = outcome["name"]
                    # If abbreviated, replace with full name
                    if home_full and name != home_full and home_full.endswith(name.split()[-1]):
                        outcome["name"] = home_full
                    elif away_full and name != away_full and away_full.endswith(name.split()[-1]):
                        outcome["name"] = away_full

    for ev in events_map.values():
        for bm in ev["bookmakers"].values():
            for mkt in bm["markets"].values():
                seen = set()
                unique_outcomes = []
                for outcome in mkt["outcomes"]:
                    if outcome["name"] not in seen:
                        seen.add(outcome["name"])
                        unique_outcomes.append(outcome)
                mkt["outcomes"] = unique_outcomes

                        
    # Convert to list format matching existing frontend expectations
    events = []
    for event in events_map.values():
        bookmakers = []
        for bm in event["bookmakers"].values():
            bookmakers.append({
                "title": bm["title"],
                "markets": list(bm["markets"].values()),
            })
        events.append({
            "id": event["id"],
            "sport": event["sport"],
            "commence_time": event["commence_time"],
            "home_team": event["home_team"],
            "away_team": event["away_team"],
            "home_logo": event.get("home_logo", ""),
            "away_logo": event.get("away_logo", ""),
            "bookmakers": bookmakers,
        })

    result = {"sport": sport, "market": market, "events": events}
    sports_cache[cache_key] = (now, result)
    return jsonify(result)


# --- Auth routes ---

@app.route("/auth/google", methods=["POST"])
def google_login():
    """Exchange a Google "Sign in with Google" credential for our own
    LineTracker session token. The frontend sends the raw credential it
    got from Google; we verify it really came from Google and really is
    for THIS app, then hand back a token the frontend uses for every
    request after this."""
    data = request.get_json() or {}
    credential = data.get("credential")
    if not credential:
        return jsonify({"error": "Missing credential"}), 400

    email = verify_google_token(credential)
    if not email:
        return jsonify({"error": "Invalid Google credential"}), 401

    token = issue_session_token(email)
    return jsonify({"token": token, "email": email})


@app.route("/auth/apple", methods=["POST"])
def apple_login():
    """Same job as google_login() above, for Sign in with Apple: the iOS
    app hands us the raw identity token ASAuthorizationAppleIDCredential
    gave it, we verify it really came from Apple and really is for THIS
    app, then hand back the exact same kind of LineTracker session token
    either sign-in method produces — everything downstream (require_auth,
    alerts, settings) doesn't know or care which provider a user signed
    in with."""
    data = request.get_json() or {}
    identity_token = data.get("identity_token")
    if not identity_token:
        return jsonify({"error": "Missing identity_token"}), 400

    email = verify_apple_token(identity_token)
    if not email:
        return jsonify({"error": "Invalid Apple credential"}), 401

    token = issue_session_token(email)
    return jsonify({"token": token, "email": email})


# --- Alert CRUD routes ---

@app.route("/alerts", methods=["POST"])
@require_auth
def create_alert():
    data = request.get_json()

    if not data:
        return jsonify({"error": "Missing JSON body"}), 400

    required = ["alert_type", "target_value", "direction"]
    missing = [f for f in required if f not in data]
    if missing:
        return jsonify({"error": f"Missing required fields: {', '.join(missing)}"}), 400

    if data["alert_type"] not in ("Stock 🌱", "Bet 🎟️"):
        return jsonify({"error": "alert_type must be 'stock' or 'bet'"}), 400

    if data["direction"] not in ("above", "below"):
        return jsonify({"error": "direction must be 'above' or 'below'"}), 400

    alert = Alert(
        alert_type=data["alert_type"],
        ticker=data.get("ticker"),
        company_name=data.get("company_name"),
        sport=data.get("sport"),
        event_id=data.get("event_id"),
        home_team=data.get("home_team"),
        away_team=data.get("away_team"),
        home_logo=data.get("home_logo"),
        away_logo=data.get("away_logo"),
        market=data.get("market"),
        outcome_name=data.get("outcome_name"),
        bookmaker=data.get("bookmaker"),
        target_value=data["target_value"],
        current_value=data.get("current_value"),
        # Seed live_value with the same starting price so the dashboard's
        # live badge shows something immediately instead of "—" while it
        # waits for the first poll cycle (up to 60s later) to update it.
        live_value=data.get("current_value"),
        direction=data["direction"],
        user_email=request.user_email,
        commence_time=data.get("commence_time")
    )

    db.session.add(alert)
    db.session.commit()

    return jsonify(alert.to_dict()), 201


@app.route("/alerts", methods=["GET"])
@require_auth
def list_alerts():
    # status=active (default): the still-waiting alerts, same as always.
    # status=triggered: the bell icon's feed -- alerts that have already
    # fired, newest first, capped at 20 so it stays "recent" instead of
    # becoming a full history.
    status = request.args.get("status", "active")
    base = Alert.query.filter(db.func.lower(Alert.user_email) == request.user_email)

    if status == "triggered":
        alerts = (
            base.filter(Alert.triggered == True)
            .order_by(Alert.triggered_at.desc())
            .limit(20)
            .all()
        )
    else:
        alerts = (
            base.filter(Alert.triggered == False)
            .order_by(Alert.created_at.desc())
            .all()
        )
    return jsonify([a.to_dict() for a in alerts])


@app.route("/alerts/<int:alert_id>", methods=["GET"])
@require_auth
def get_alert(alert_id):
    alert = Alert.query.get(alert_id)
    if not alert:
        return jsonify({"error": "Alert not found"}), 404
    if (alert.user_email or "").strip().lower() != request.user_email:
        return jsonify({"error": "Not your alert"}), 403
    return jsonify(alert.to_dict())


@app.route("/alerts/<int:alert_id>", methods=["DELETE"])
@require_auth
def delete_alert(alert_id):
    alert = Alert.query.get(alert_id)
    if not alert:
        return jsonify({"error": "Alert not found"}), 404
    if (alert.user_email or "").strip().lower() != request.user_email:
        return jsonify({"error": "Not your alert"}), 403

    db.session.delete(alert)
    db.session.commit()

    return jsonify({"message": f"Alert {alert_id} deleted"})

# UptimeRobot wakes the server up every 5 minutes
# --- Settings routes ---
# Lazily-created UserSettings row: a user who's never touched their
# settings has none, and that's treated as "everything default" (email
# notifications on) rather than requiring a row to exist for every
# account up front.
@app.route("/settings", methods=["GET"])
@require_auth
def get_settings():
    settings = UserSettings.query.filter_by(user_email=request.user_email).first()
    if not settings:
        return jsonify({"user_email": request.user_email, "notify_email": True})
    return jsonify(settings.to_dict())


@app.route("/settings", methods=["PUT"])
@require_auth
def update_settings():
    data = request.get_json() or {}
    if "notify_email" not in data:
        return jsonify({"error": "Missing required field: notify_email"}), 400

    settings = UserSettings.query.filter_by(user_email=request.user_email).first()
    if not settings:
        settings = UserSettings(user_email=request.user_email)
        db.session.add(settings)

    settings.notify_email = bool(data["notify_email"])
    db.session.commit()

    return jsonify(settings.to_dict())


@app.route("/account", methods=["DELETE"])
@require_auth
def delete_account():
    """Apple requires apps that support signing in to also support
    deleting the account from inside the app (App Store Review Guideline
    5.1.1(v)) -- not just signing out. There's no separate "users" table
    to drop a row from here (an account is just whatever email Google/
    Apple verified, re-derived fresh on every sign-in), so "delete the
    account" means erasing every trace of that email from LineTracker's
    own data: every alert it owns, and its notification-preferences row.
    The client signs the device out right after this succeeds.
    """
    email = request.user_email
    Alert.query.filter(db.func.lower(Alert.user_email) == email).delete(synchronize_session=False)
    UserSettings.query.filter_by(user_email=email).delete(synchronize_session=False)
    db.session.commit()
    return jsonify({"message": "Account deleted"})


@app.route("/ping", methods=["GET"])
def ping():
    return jsonify({"status": "alive"})

# --- Manual trigger route (for testing the poller on demand) ---
@app.route("/poll-now", methods=["POST"])
def poll_now():
    poll_alerts(app, db, Alert, SHARP_API_KEY, send_email_func=send_alert_email, UserSettings=UserSettings)
    return jsonify({"message": "Polling run complete — check terminal logs"})


# --- Scheduler setup ---
# This starts the moment app.py is imported, so it starts once per
# process that imports it. The Procfile deliberately runs Gunicorn with
# --workers 1 to keep it at exactly one copy — going to more than one
# worker without first moving this into its own separate process would
# mean each worker running its own independent copy of this clock, i.e.
# duplicate SharpAPI/yfinance calls and duplicate trigger emails every
# minute. Don't raise the worker count in Procfile without splitting
# this out first (a Render background worker, run separately from the
# web service).
class SchedulerConfig:
    SCHEDULER_API_ENABLED = False


app.config.from_object(SchedulerConfig())
scheduler = APScheduler()
scheduler.init_app(app)


@scheduler.task("interval", id="poll_alerts_job", minutes=1)
def scheduled_poll():
    poll_alerts(app, db, Alert, SHARP_API_KEY, send_email_func=send_alert_email, UserSettings=UserSettings)


scheduler.start()


if __name__ == "__main__":
    app.run(host="0.0.0.0", port=int(os.environ.get("PORT", 5000)), use_reloader=False)