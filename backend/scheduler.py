import yfinance 
import requests
import time
from datetime import datetime, timezone

SHARP_API_BASE = "https://api.sharpapi.io/api/v1"


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

MARKET_TO_SHARP = {
    "h2h": "moneyline",
    "spreads": "spread",
    "totals": "total",
}

def get_bet_odds(sharp_api_key, sport, event_id, market, outcome_name, bookmaker):
    """Fetch current odds for a specific outcome from SharpAPI."""
    league = SPORT_TO_SHARP.get(sport)
    sharp_market = MARKET_TO_SHARP.get(market, "moneyline")

    if not league:
        print(f"[poll] Unsupported sport: {sport}")
        return None

    headers = {"X-API-Key": sharp_api_key}
    offset = 0
    limit = 50

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

            for row in rows:
                if row.get("event_id") != event_id:
                    continue
                sportsbook_label = (row.get("sportsbook_ref") or {}).get("label") or row.get("sportsbook", "").title()
                if sportsbook_label != bookmaker:
                    continue
                if row.get("selection") == outcome_name:
                    return row.get("odds_american")

            pagination = data.get("pagination", {})
            if not pagination.get("has_more"):
                break
            offset += limit

        return None

    except requests.exceptions.RequestException as e:
        print(f"[poll] Error fetching SharpAPI odds for event {event_id}: {e}")
        return None

def get_stock_price(ticker): 

    """Return current price for a stock ticker. Return None on failure."""
    try: 
        stock = yfinance.Ticker(ticker.upper())
        info = stock.fast_info
        price = info.get("lastPrice")
        if price is None: 
            return price
        else: 
            return round(price, 2)

    except Exception as e: 
        print(f"[poll] Error fetching stock price for {ticker}: {e}")
        return None


def check_threshold(current_value, target_value, direction):
    """Return whether the alert condition has been met."""

    if current_value is None: 
        return False
    if direction == "above":
        return current_value >= target_value
    elif direction == "below":
        return current_value <= target_value
    return False


def poll_alerts(app, db, Alert, sharp_api_key, send_email_func=None):
    """
    Checks all untriggered alerts against live data.
    Call this on a schedule (e.g. every 5 minutes via APScheduler).
    """
    with app.app_context():
        alerts = Alert.query.filter_by(triggered=False).all()
        print(f"[poll] Checking {len(alerts)} active alert(s) at {datetime.utcnow().isoformat()}")

        for alert in alerts:
            current_value = None

            if alert.alert_type == "Stock 🌱":
                current_value = get_stock_price(alert.ticker)

            elif alert.alert_type == "Bet 🎟️":
                current_value = get_bet_odds(
                    sharp_api_key,
                    alert.sport,
                    alert.event_id,
                    alert.market,
                    alert.outcome_name,
                    alert.bookmaker,
                )
                time.sleep(6)

            if current_value is None:
                print(f"[poll] Could not fetch current value for alert {alert.id}, skipping")
                continue

            alert.live_value = current_value

            # Deleting alerts for old games
            if alert.alert_type == "bet" and alert.commence_time:
                    commence = datetime.fromisoformat(alert.commence_time.replace("Z", "+00:00"))
                    hours_since_start = (datetime.now(timezone.utc) - commence).total_seconds() / 3600
                    if hours_since_start > 5:
                        print(f"[poll] Alert {alert.id} game likely over, deleting")
                        db.session.delete(alert)
                        continue

            hit = check_threshold(current_value, alert.target_value, alert.direction)

            if hit:
                print(f"[poll] Alert {alert.id} TRIGGERED — {current_value} {alert.ticker} {alert.direction} {alert.target_value}")

                # Only mark the alert triggered (which removes it from the
                # dashboard) once the email has actually gone out. If the send
                # fails, leave it active — it'll retry on the next poll cycle
                # instead of silently vanishing with no notification sent.
                email_sent = True
                if send_email_func:
                    email_sent = send_email_func(alert)
                    if not email_sent:
                        print(f"[poll] Alert {alert.id} email failed to send — leaving alert active to retry next cycle")

                if email_sent:
                    alert.triggered = True
                    alert.triggered_at = datetime.utcnow()
            else:
                print(f"[poll] Alert {alert.id} not yet hit — current: {current_value}, target: {alert.target_value}")

        db.session.commit()
