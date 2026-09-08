from flask_sqlalchemy import SQLAlchemy
from datetime import datetime

db = SQLAlchemy()

# Defining the "alerts" table
class Alert(db.Model):
    __tablename__ = "alerts"

    id = db.Column(db.Integer, primary_key=True)

    commence_time = db.Column(db.String(50), nullable=True)

    # "stock" or "bet"
    alert_type = db.Column(db.String(10), nullable=False)

    # STOCK fields (ticker)
    ticker = db.Column(db.String(10), nullable=True)
    company_name = db.Column(db.String(200), nullable=True)

    # BET fields
    sport = db.Column(db.String(50), nullable=True)
    event_id = db.Column(db.String(100), nullable=True)
    home_team = db.Column(db.String(100), nullable=True)
    away_team = db.Column(db.String(100), nullable=True)
    market = db.Column(db.String(20), nullable=True)   # h2h, spreads, totals
    outcome_name = db.Column(db.String(100), nullable=True)  # which team/side
    bookmaker = db.Column(db.String(50), nullable=True)
    home_logo = db.Column(db.String(300), nullable=True)
    away_logo = db.Column(db.String(300), nullable=True)

    # Shared fields
    target_value = db.Column(db.Float, nullable=False)
    current_value = db.Column(db.Float, nullable=True)  # frozen: price/odds at the time the alert was created ("Set at")
    live_value = db.Column(db.Float, nullable=True)  # live: updated every poll cycle by the scheduler
    direction = db.Column(db.String(10), nullable=False)  # "above" or "below"

    # Time stamps for when the email noti was sent
    triggered = db.Column(db.Boolean, default=False)
    created_at = db.Column(db.DateTime, default=datetime.utcnow)
    triggered_at = db.Column(db.DateTime, nullable=True)

    # Email to send the noti to
    user_email = db.Column(db.String(120), nullable=False)

    # Converts instance of Alert class to a python dict
    def to_dict(self):
        return {
            "id": self.id,
            "alert_type": self.alert_type,
            "company_name": self.company_name,
            "ticker": self.ticker,
            "sport": self.sport,
            "event_id": self.event_id,
            "home_team": self.home_team,
            "away_team": self.away_team,
            "home_logo": self.home_logo,
            "away_logo": self.away_logo,
            "market": self.market,
            "outcome_name": self.outcome_name,
            "bookmaker": self.bookmaker,
            "target_value": self.target_value,
            "current_value": self.current_value,
            "live_value": self.live_value,
            "direction": self.direction,
            "triggered": self.triggered,
            "created_at": self.created_at.isoformat() if self.created_at else None,
            "triggered_at": self.triggered_at.isoformat() if self.triggered_at else None,
            "user_email": self.user_email,
            "commence_time": self.commence_time
        }

# Per-account preferences — the first piece of "this is a real account,
# not just a string on each alert" state in this app. One row per email,
# created lazily the first time someone actually changes a setting (see
# app.py's /settings routes) rather than at signup, since Google OAuth
# never creates a row of its own for a new user today.
class UserSettings(db.Model):
    __tablename__ = "user_settings"

    id = db.Column(db.Integer, primary_key=True)
    user_email = db.Column(db.String(120), unique=True, nullable=False)

    # Whether alert-trigger emails should actually be sent. Defaults to
    # True everywhere a row doesn't exist yet (see get_settings/
    # update_settings in app.py and the lookup in scheduler.py's
    # poll_alerts) so a user who's never touched this setting keeps
    # getting emails exactly as before this existed.
    notify_email = db.Column(db.Boolean, default=True, nullable=False)

    def to_dict(self):
        return {
            "user_email": self.user_email,
            "notify_email": self.notify_email,
        }
