import os
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

from models import db, Alert
from scheduler import poll_alerts

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

        event_date = (row.get("event_start_time") or "")[:10]
        event_key = f"{row.get('home_team')}_{row.get('away_team')}_{event_date}"

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


# --- Alert CRUD routes ---

@app.route("/alerts", methods=["POST"])
def create_alert():
    data = request.get_json()

    if not data:
        return jsonify({"error": "Missing JSON body"}), 400

    required = ["alert_type", "target_value", "direction", "user_email"]
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
        direction=data["direction"],
        user_email=data["user_email"],
        commence_time=data.get("commence_time")
    )

    db.session.add(alert)
    db.session.commit()

    return jsonify(alert.to_dict()), 201


@app.route("/alerts", methods=["GET"])
def list_alerts():
    email = request.args.get("email")
    if email:
        alerts = Alert.query.filter_by(user_email=email, triggered=False).order_by(Alert.created_at.desc()).all()
    else:
        alerts = Alert.query.filter_by(triggered=False).order_by(Alert.created_at.desc()).all()
    return jsonify([a.to_dict() for a in alerts])


@app.route("/alerts/<int:alert_id>", methods=["GET"])
def get_alert(alert_id):
    alert = Alert.query.get(alert_id)
    if not alert:
        return jsonify({"error": "Alert not found"}), 404
    return jsonify(alert.to_dict())


@app.route("/alerts/<int:alert_id>", methods=["DELETE"])
def delete_alert(alert_id):
    alert = Alert.query.get(alert_id)
    if not alert:
        return jsonify({"error": "Alert not found"}), 404

    db.session.delete(alert)
    db.session.commit()

    return jsonify({"message": f"Alert {alert_id} deleted"})

# UptimeRobot wakes the server up every 5 minutes
@app.route("/ping", methods=["GET"])
def ping():
    return jsonify({"status": "alive"})

# --- Manual trigger route (for testing the poller on demand) ---
@app.route("/poll-now", methods=["POST"])
def poll_now():
    poll_alerts(app, db, Alert, SHARP_API_KEY, send_email_func=send_alert_email)
    return jsonify({"message": "Polling run complete — check terminal logs"})


# --- Scheduler setup ---
class SchedulerConfig:
    SCHEDULER_API_ENABLED = False


app.config.from_object(SchedulerConfig())
scheduler = APScheduler()
scheduler.init_app(app)


@scheduler.task("interval", id="poll_alerts_job", minutes=1)
def scheduled_poll():
    poll_alerts(app, db, Alert, SHARP_API_KEY, send_email_func=send_alert_email)


scheduler.start()


if __name__ == "__main__":
    app.run(host="0.0.0.0", port=int(os.environ.get("PORT", 5000)), use_reloader=False)