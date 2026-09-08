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


def fetch_league_market_rows(sharp_api_key, sport, market):
    """Fetch EVERY SharpAPI row for a given (sport, market) pair, across
    all pages, in one shared trip.

    This replaces the old per-alert get_bet_odds(), which re-fetched
    this exact same league+market data from scratch for every single
    alert that happened to share it — ten different people all watching
    the same Lakers moneyline used to mean ten separate identical
    fetches. Every alert tracking this sport+market now gets checked
    against this one shared result via extract_odds() below, so the
    number of SharpAPI calls scales with how many distinct games are
    being tracked, not how many alerts or users exist.

    Returns None on a hard failure (network error, bad response) so
    callers can tell "couldn't ask SharpAPI" apart from a legitimate
    empty [] (asked, nothing came back).
    """
    league = SPORT_TO_SHARP.get(sport)
    sharp_market = MARKET_TO_SHARP.get(market, "moneyline")

    if not league:
        print(f"[poll] Unsupported sport: {sport}")
        return None

    headers = {"X-API-Key": sharp_api_key}
    offset = 0
    limit = 50
    rows = []

    try:
        page = 0
        while True:
            if page > 0:
                # Stay under SharpAPI's free-tier ~12 requests/minute cap
                # between pages of this SAME league+market fetch.
                time.sleep(6)
            page += 1

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
            rows.extend(data.get("data", []))

            pagination = data.get("pagination", {})
            if not pagination.get("has_more"):
                break
            offset += limit

        return rows

    except requests.exceptions.RequestException as e:
        print(f"[poll] Error fetching SharpAPI odds for league={league!r} market={sharp_market!r}: {e}")
        return None


def extract_odds(rows, event_id, outcome_name, bookmaker):
    """Find one alert's odds inside a rows list already fetched by
    fetch_league_market_rows(). Same matching logic get_bet_odds() used
    to do inline, now reusable against a shared fetch instead of
    triggering a fresh network call per alert.

    Tracked so a "not found" result can say exactly where the lookup
    broke down instead of a dead-end "could not fetch" — was the event
    missing entirely, was it there but under a different bookmaker, or
    was the bookmaker right but the outcome name didn't match?
    """
    found_event = False
    found_bookmaker = False

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

    if not found_event:
        print(f"[poll] SharpAPI has no odds for event_id={event_id!r} "
              f"({len(rows)} other row(s) checked) — the pre-game line "
              f"may be gone (game started/finished) or this event_id no longer matches SharpAPI's listing")
    elif not found_bookmaker:
        print(f"[poll] Found event_id={event_id!r} but no row for bookmaker={bookmaker!r} — that "
              f"sportsbook may not be listing this game, or its label doesn't match what was stored")
    else:
        print(f"[poll] Found event_id={event_id!r} and bookmaker={bookmaker!r} but no row matched "
              f"outcome_name={outcome_name!r} — likely a naming/format mismatch")
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


def poll_alerts(app, db, Alert, sharp_api_key, send_email_func=None, UserSettings=None):
    """
    Checks all untriggered alerts against live data.
    Call this on a schedule (e.g. every 5 minutes via APScheduler).

    Fetches data in BATCHES, not per-alert: every bet alert sharing the
    same (sport, market) — e.g. ten different people all watching the
    same Lakers moneyline — is checked against one shared SharpAPI fetch
    instead of each alert triggering its own separate call for the exact
    same underlying data. Same idea for stock alerts sharing a ticker
    and yfinance. Actual network calls now scale with how many distinct
    games/stocks are being tracked, not how many alerts or users exist.

    UserSettings (optional) is the per-account preferences model — if
    given, a triggered alert whose owner has turned email off skips the
    actual send but still gets marked triggered, same as if the email
    had gone out. Passing None (or a user with no settings row yet)
    means "send it," matching behavior from before this setting existed.
    """
    with app.app_context():
        alerts = Alert.query.filter_by(triggered=False).all()
        print(f"[poll] Checking {len(alerts)} active alert(s) at {datetime.utcnow().isoformat()}")

        # Delete bet alerts for games that started 5+ hours ago *before*
        # attempting any fetch. This used to run after the fetch (and used
        # a lowercase "bet" that never matched the real "Bet 🎟️" value,
        # so it never ran at all) — an alert whose odds can never be
        # fetched (the actual stuck case) hit "continue" on the fetch
        # failure below and never reached it, so it stayed active
        # forever, failing every single poll with no way out. Pulled into
        # its own pass so the alerts left over can be grouped for
        # batching next.
        live_alerts = []
        for alert in alerts:
            if alert.alert_type == "Bet 🎟️" and alert.commence_time:
                commence = datetime.fromisoformat(alert.commence_time.replace("Z", "+00:00"))
                hours_since_start = (datetime.now(timezone.utc) - commence).total_seconds() / 3600
                if hours_since_start > 5:
                    print(f"[poll] Alert {alert.id} game likely over, deleting")
                    db.session.delete(alert)
                    continue
            live_alerts.append(alert)

        # --- Batch fetch: once per unique (sport, market) for bets, once
        # per unique ticker for stocks — see this function's docstring.
        bet_keys = sorted({
            (a.sport, a.market) for a in live_alerts if a.alert_type == "Bet 🎟️"
        })
        odds_by_key = {}
        for i, (sport, market) in enumerate(bet_keys):
            if i > 0:
                # Stay under SharpAPI's free-tier ~12 requests/minute cap
                # between different sport+market groups.
                time.sleep(6)
            odds_by_key[(sport, market)] = fetch_league_market_rows(sharp_api_key, sport, market)

        tickers = sorted({
            a.ticker for a in live_alerts if a.alert_type == "Stock 🌱" and a.ticker
        })
        price_by_ticker = {ticker: get_stock_price(ticker) for ticker in tickers}

        # --- Check every alert against its already-fetched snapshot — no
        # network calls happen in this loop at all anymore.
        for alert in live_alerts:
            current_value = None

            if alert.alert_type == "Stock 🌱":
                current_value = price_by_ticker.get(alert.ticker)

            elif alert.alert_type == "Bet 🎟️":
                rows = odds_by_key.get((alert.sport, alert.market))
                if rows is not None:
                    current_value = extract_odds(rows, alert.event_id, alert.outcome_name, alert.bookmaker)

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
                # dashboard — once the email has actually gone out (or was
                # deliberately skipped because the user turned it off — see
                # wants_email below). If the send fails, roll the timestamp
                # back and leave the alert active so it retries on the next
                # poll cycle instead of silently vanishing with no
                # notification sent.
                alert.triggered_at = datetime.utcnow()

                wants_email = True
                if UserSettings is not None:
                    settings = UserSettings.query.filter_by(user_email=alert.user_email).first()
                    if settings is not None:
                        wants_email = settings.notify_email

                email_sent = True
                if not wants_email:
                    print(f"[poll] Alert {alert.id} triggered but user has email notifications off — skipping send")
                elif send_email_func:
                    email_sent = send_email_func(alert)
                    if not email_sent:
                        print(f"[poll] Alert {alert.id} email failed to send — leaving alert active to retry next cycle")
                        alert.triggered_at = None

                if email_sent:
                    alert.triggered = True
            else:
                print(f"[poll] Alert {alert.id} not yet hit — current: {current_value}, target: {alert.target_value}")

        db.session.commit()
