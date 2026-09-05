import { useEffect, useState } from "react";
import { Link } from "react-router-dom";
import { getAlerts, deleteAlert } from "../api";
import "./Dashboard.css";

const BOOKMAKER_DOMAINS = {
  "Draftkings": "draftkings.com",
  "FanDuel": "fanduelracing.com",
  "BetMGM": "betmgm.com",
  "BetRivers": "betrivers.com",
  "Bovada": "bovada.lv",
  "MyBookie.ag": "mybookie.ag",
  "BetOnline.ag": "betonline.ag",
  "LowVig.ag": "lowvig.ag",
  "BetUS": "betus.com.pa",
  "Caesars": "caesars.com",
  "PointsBet": "pointsbet.com",
  "Unibet": "unibet.com",
  "bet365": "bet365.com",
  "William Hill": "williamhill.com",
  "Betway": "betway.com",
  "Hard Rock Bet": "hardrock.com",
};

function formatOdds(price) {
  if (price === null || price === undefined) return "—";
  return price > 0 ? `+${price}` : `${price}`;
}

function formatValue(alert) {
  if (alert.alert_type === "Stock 🌱") {
    return alert.current_value !== null && alert.current_value !== undefined
      ? `$${parseFloat(alert.current_value).toFixed(2)}`
      : "—";
  }
  return formatOdds(alert.current_value);
}

function formatLiveValue(alert) {
  if (alert.alert_type === "Stock 🌱") {
    return alert.live_value !== null && alert.live_value !== undefined
      ? `$${parseFloat(alert.live_value).toFixed(2)}`
      : "—";
  }
  return formatOdds(alert.live_value);
}

function formatTarget(alert) {
  if (alert.alert_type === "Stock 🌱") return `$${parseFloat(alert.target_value).toFixed(2)}`;
  return formatOdds(alert.target_value);
}

function alertTitle(alert) {
  if (alert.alert_type === "Stock 🌱") return alert.ticker;
  return alert.outcome_name || `${alert.home_team} vs ${alert.away_team}`;
}

function alertSubtitle(alert) {
  if (alert.alert_type === "Stock 🌱") return alert.company_name;
  if (!alert.home_team || !alert.away_team) return "Bet";
  const opponent = alert.outcome_name === alert.home_team ? alert.away_team : alert.home_team;
  const opponentLogo = alert.outcome_name === alert.home_team ? alert.away_logo : alert.home_logo;
  return (
    <>
      vs{" "}
      {opponentLogo && (
        <img
          src={opponentLogo}
          alt={opponent}
          className="subtitle-team-logo"
          onError={(e) => { e.target.style.display = "none"; }}
        />
      )}
      {opponent}
    </>
  );
}

function isSameCalendarDay(a, b) {
  return (
    a.getFullYear() === b.getFullYear() &&
    a.getMonth() === b.getMonth() &&
    a.getDate() === b.getDate()
  );
}

function alertDateLine(alert) {
  const createdAt = alert.created_at ? new Date(alert.created_at + "Z") : null;
  const createdDateStr = createdAt
    ? createdAt.toLocaleDateString(undefined, { month: "short", day: "numeric" })
    : null;
  const createdTimeStr = createdAt
    ? createdAt.toLocaleTimeString(undefined, { hour: "numeric", minute: "2-digit" })
    : null;

  if (alert.alert_type === "Stock 🌱") {
    if (!createdAt) return null;
    return `${createdDateStr}, Created @ ${createdTimeStr}`;
  }

  // Bet alert
  if (!alert.commence_time) {
    return createdAt ? `${createdDateStr}, Created @ ${createdTimeStr}` : null;
  }
  if (!createdAt) return null;

  const commenceDate = new Date(alert.commence_time);
  const now = new Date();
  const gameStarted = commenceDate <= now;

  if (gameStarted) {
    return `${createdDateStr}, Created @ ${createdTimeStr}`;
  }

  const startTimeStr = commenceDate.toLocaleTimeString(undefined, { hour: "numeric", minute: "2-digit" });

  if (isSameCalendarDay(commenceDate, now)) {
    return `${createdDateStr}, Starts @ ${startTimeStr}`;
  }

  const gameDateStr = commenceDate.toLocaleDateString(undefined, { month: "short", day: "numeric" });
  return `${createdDateStr}, Scheduled for ${gameDateStr}`;
}

export default function Dashboard({ userEmail }) {

  const LOGOKIT_TOKEN = import.meta.env.VITE_LOGOKIT_API_TOKEN;

  const [alerts, setAlerts] = useState([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState(null);

  async function loadAlerts() {
    console.log("loading alerts for email:", userEmail);
    try {
      setLoading(true);
      const data = await getAlerts(userEmail);
      setAlerts(data);
      setError(null);
    } catch (err) {
      setError("Could not reach the backend. Is the Flask server running?");
    } finally {
      setLoading(false);
    }
  }

  useEffect(() => {
    loadAlerts();
  }, []);

  useEffect(() => {
    if (userEmail) {
      loadAlerts();
    }
  }, [userEmail]);

  async function handleDelete(id) {
    try {
      await deleteAlert(id);
      setAlerts((prev) => prev.filter((a) => a.id !== id));
    } catch (err) {
      console.error("Failed to delete alert", err);
    }
  }

  const active = alerts.filter((a) => !a.triggered);
  const triggered = alerts.filter((a) => a.triggered);

  return (
    <div className="dashboard">
      <div className="dashboard-head">
        <h1>Your alerts</h1>
        <div className="dashboard-actions">
          <Link to="/stocks" className="btn btn-ghost">+ Stock</Link>
          <Link to="/bets" className="btn btn-primary">+ Bet</Link>
        </div>
      </div>

      {loading && <p className="dim-text">Loading alerts…</p>}

      {error && (
        <div className="error-box">
          <p>{error}</p>
        </div>
      )}

      {!loading && !error && alerts.length === 0 && (
        <div className="empty-state">
          <p className="empty-title">No alerts yet</p>
          <p className="dim-text">
            Track a stock's price or a betting line — you'll get an email the moment it crosses your target.
          </p>
        </div>
      )}

      {active.length > 0 && (
        <section className="alert-section">
          <h2 className="section-label">Active <span className="count-badge">{active.length}</span></h2>
          <div className="alert-list">
            {active.map((alert) => (
              <div className="alert-card" key={alert.id}>
                
                {alert.alert_type === "Stock 🌱" ? (
                  <img
                    src={`https://img.logokit.com/ticker/${alert.ticker}?token=${LOGOKIT_TOKEN}`}
                    alt={alert.ticker}
                    className="alert-team-logo"
                    onError={(e) => { e.target.style.display = "none"; }}
                  />
                ) : (() => {
                  const logo = alert.outcome_name === alert.home_team ? alert.home_logo : alert.away_logo;
                  return logo ? (
                    <img
                      src={logo}
                      alt={alert.outcome_name}
                      className="alert-team-logo"
                      onError={(e) => { e.target.style.display = "none"; }}
                    />
                  ) : null;
                })()}

                <div className="alert-card-main">
                  <div style={{ display: "flex", alignItems: "center", gap: "8px", marginBottom: "4px" }}>
                    <div className="alert-card-type">{alert.alert_type}</div>
                    {alert.alert_type === "Stock 🌱" && (
                      <span className="live-badge">
                        <span className="live-dot" />
                        {formatLiveValue(alert)}
                      </span>
                    )}
                    {alert.alert_type !== "Stock 🌱" && alert.bookmaker && (
                      <span className="bookmaker-badge">
                        {BOOKMAKER_DOMAINS[alert.bookmaker] && (
                          <img
                            src={`https://img.logokit.com/${BOOKMAKER_DOMAINS[alert.bookmaker]}?token=${LOGOKIT_TOKEN}`}
                            alt={alert.bookmaker}
                            className="bookmaker-badge-logo"
                            onError={(e) => { e.target.style.display = "none"; }}
                          />
                        )}
                        {alert.bookmaker}
                      </span>
                    )}
                  </div>
                  <p className="alert-card-title">{alertTitle(alert)}</p>
                  <p className="alert-card-subtitle">{alertSubtitle(alert)}</p>
                  {alertDateLine(alert) && (
                    <span className="alert-date">{alertDateLine(alert)}</span>
                  )}
                </div>

                <div className="alert-card-values">
                  <div className="pill-group">
                    <span className="pill-label">Set at</span>
                    <span className="pill neutral">{formatValue(alert)}</span>
                  </div>
                  <span className={`arrow ${alert.direction === "above" ? "arrow-success" : "arrow-danger"}`}>→</span>
                  <div className="pill-group">
                    <span className="pill-label">Target</span>
                    <span className={`pill ${alert.direction === "above" ? "pill-success" : "pill-danger"}`}>
                      {formatTarget(alert)}
                    </span>
                  </div>
                </div>

                <button className="icon-btn" onClick={() => handleDelete(alert.id)} aria-label="Delete alert">
                  ✕
                </button>
              </div>
            ))}
          </div>
        </section>
      )}

    </div>
  );
}