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

def _outcome_matches(selection, outcome_name):
    """True if SharpAPI's raw 'selection' field refers to the same team/
    selection as the alert's stored outcome_name, even if one is
    abbreviated and the other is the full name (e.g. "Pistons" vs
    "Detroit Pistons"). app.py's /odds route already expands abbreviated
    selections to full team names before a user picks one and it gets
    saved as outcome_name — but SharpAPI's raw odds feed (what polling
    reads here) isn't guaranteed to use the full name on every row, so an
    exact string match would silently and permanently never fire."""
    sel = (selection or "").strip().casefold()
    name = (outcome_name or "").strip().casefold()
    if not sel or not name:
        return False
    if sel == name:
        return True
    sel_last_word = sel.split()[-1] if sel.split() else sel
    name_last_word = name.split()[-1] if name.split() else name
    return name.endswith(sel_last_word) or sel.endswith(name_last_word)


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

    # Tracked so a "not found" result can say exactly where the lookup broke
    # down instead of a dead-end "could not fetch" — was the event missing
    # entirely, was it there but under a different bookmaker, or was the
    # bookmaker right but the outcome name didn't match?
    found_event = False
    found_bookmaker = False
    total_rows_seen = 0

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
            total_rows_seen += len(rows)

            for row in rows:
                if row.get("event_id") != event_id:
                    continue
                found_event = True
                sportsbook_label = (row.get("sportsbook_ref") or {}).get("label") or row.get("sportsbook", "").title()
                # Case/whitespace-insensitive: the event-search endpoint and this
                # odds endpoint can format the same sportsbook/team differently
                # (e.g. "Draftkings" vs "DraftKings"), which an exact string
                # match would treat as a permanent, silent non-match.
                if sportsbook_label.strip().casefold() != (bookmaker or "").strip().casefold():
                    continue
                found_bookmaker = True
                if _outcome_matches(row.get("selection"), outcome_name):
                    return row.get("odds_american")

            pagination = data.get("pagination", {})
            if not pagination.get("has_more"):
                break
            offset += limit

        if not found_event:
            print(f"[poll] SharpAPI has no odds for event_id={event_id!r} in league={league!r} "
                  f"market={sharp_market!r} ({total_rows_seen} other row(s) checked) — the pre-game line "
                  f"may be gone (game started/finished) or this event_id no longer matches SharpAPI's listing")
        elif not found_bookmaker:
            print(f"[poll] Found event_id={event_id!r} but no row for bookmaker={bookmaker!r} — that "
                  f"sportsbook may not be listing this game, or its label doesn't match what was stored")
        else:
            print(f"[poll] Found event_id={event_id!r} and bookmaker={bookmaker!r} but no row matched "
                  f"outcome_name={outcome_name!r} — likely a naming/format mismatch")
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
            # Delete bet alerts for games that started 5+ hours ago *before*
            # attempting a fetch. This used to run after the fetch (and used
            # a lowercase "bet" that never matched the real "Bet 🎟️" value,
            # so it never ran at all) — an alert whose odds can never be
            # fetched (the actual stuck case) hit "continue" on the fetch
            # failure below and never reached it, so it stayed active
            # forever, failing every single poll with no way out.
            if alert.alert_type == "Bet 🎟️" and alert.commence_time:
                commence = datetime.fromisoformat(alert.commence_time.replace("Z", "+00:00"))
                hours_since_start = (datetime.now(timezone.utc) - commence).total_seconds() / 3600
                if hours_since_start > 5:
                    print(f"[poll] Alert {alert.id} game likely over, deleting")
                    db.session.delete(alert)
                    continue

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

            hit = check_threshold(current_value, alert.target_value, alert.direction)

            if hit:
                print(f"[poll] Alert {alert.id} TRIGGERED — {current_value} {alert.ticker} {alert.direction} {alert.target_value}")

                # Stamp the trigger time BEFORE sending so the email itself
                # (built inside send_email_func, which reads alert.triggered_at)
                # actually has a timestamp to show instead of blank/"—". Only
                # kept — and only marked triggered, which removes it from the
                # dashboard — once the email has actually gone out. If the
                # send fails, roll the timestamp back and leave the alert
                # active so it retries on the next poll cycle instead of
                # silently vanishing with no notification sent.
                alert.triggered_at = datetime.utcnow()

                email_sent = True
                if send_email_func:
                    email_sent = send_email_func(alert)
                    if not email_sent:
                        print(f"[poll] Alert {alert.id} email failed to send — leaving alert active to retry next cycle")
                        alert.triggered_at = None

                if email_sent:
                    alert.triggered = True
            else:
                print(f"[poll] Alert {alert.id} not yet hit — current: {current_value}, target: {alert.target_value}")

        db.session.commit()
