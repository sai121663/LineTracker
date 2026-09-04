import { useState, useEffect } from "react";
import { useNavigate } from "react-router-dom";
import { getOdds, createAlert } from "../api";
import "./BetSearch.css";

const LOGOKIT_TOKEN = import.meta.env.VITE_LOGOKIT_API_TOKEN;

const ALL_SPORTS = [
  { key: "basketball_nba", label: "NBA 🏀" },
  { key: "americanfootball_nfl", label: "NFL 🏈" },
  { key: "icehockey_nhl", label: "NHL 🏒" },
  { key: "baseball_mlb", label: "MLB ⚾" },
  { key: "soccer_mls", label: "MLS ⚽" },
];

const MARKETS = [
  { key: "h2h", label: "Moneyline 🏆", desc: "Pick the winner" },
  { key: "spreads", label: "Spread 🎯", desc: "Win by a margin" },
  { key: "totals", label: "Over / Under ⚖️", desc: "Total points scored" },
];

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

function addPoints(odds, points) {
  if (points >= 0) {
    // Going up (more positive/underdog direction)
    if (odds >= 100) return odds + points;
    // odds is negative, going up
    const toEdge = -odds - 100; // distance from current to -100
    if (points <= toEdge) return odds + points;
    const remaining = points - toEdge;
    return 100 + remaining; // jump gap
  } else {
    // Going down (more negative/favorite direction)
    const absPoints = Math.abs(points);
    if (odds <= -100) return odds - absPoints;
    // odds is positive, going down
    const toEdge = odds - 100; // distance from current to +100
    if (absPoints <= toEdge) return odds - absPoints;
    const remaining = absPoints - toEdge;
    return -100 - remaining; // jump gap
  }
}


export default function BetSearch({ userEmail }) {
  const normalize = (str) => str.normalize("NFD").replace(/[\u0300-\u036f]/g, "");

  const navigate = useNavigate();

  const [email, setEmail] = useState(userEmail || "");

  const [step, setStep] = useState(0);
  const [sport, setSport] = useState(null);
  const [events, setEvents] = useState([]);
  const [loadingEvents, setLoadingEvents] = useState(false);
  const [loadError, setLoadError] = useState(null);

  const [event, setEvent] = useState(null);
  const [market, setMarket] = useState(null);
  const [outcome, setOutcome] = useState(null);
  const [bookmaker, setBookmaker] = useState(null);
  const [opponent, setOpponent] = useState(null);

  const [direction, setDirection] = useState("above");
  const [targetValue, setTargetValue] = useState("");
  const [saving, setSaving] = useState(false);
  const [saveError, setSaveError] = useState(null);

  const [activeSports, setActiveSports] = useState([]);
  const [loadingSports, setLoadingSports] = useState(true);

  const [oddsInput, setOddsInput] = useState("");

  const [minOdds, setMinOdds] = useState(null);
  const [maxOdds, setMaxOdds] = useState(null);

  useEffect(() => {
    async function fetchActiveSports() {
      const results = [];
      await Promise.all(
        ALL_SPORTS.map(async (sport) => {
          try {
            const data = await getOdds(sport.key, "h2h");
            if (data.events && data.events.length > 0) {
              results.push({ ...sport, eventCount: data.events.length });
            }
          } catch {
            // skip
          }
        })
      );
      results.sort((a, b) => b.eventCount - a.eventCount);
      setActiveSports(results);
      setLoadingSports(false);
    }
    fetchActiveSports();
  }, []);


  async function selectSport(s) {
    setSport(s);
    setLoadingEvents(true);
    setStep(1);
    setLoadError(null);
    try {
      const data = await getOdds(s.key, "h2h");
      setEvents(data.events || []);
    } catch (err) {
      setLoadError("Could not load games for this sport. Try another.");
    } finally {
      setLoadingEvents(false);
    }
  }

  function selectEvent(e) {
    setEvent(e);
    setMarket({ key: "h2h", label: "Moneyline", desc: "Pick the winner" });
    setStep(2);
  }

  function selectMarket(m) {
    setMarket(m);
    setStep(3);
  }

  function selectOutcome(outcomeName, price, bookmakerTitle, logo) {
    const normalize = (str) => str ? str.normalize("NFD").replace(/[\u0300-\u036f]/g, "") : "";
    const resolvedLogo = normalize(outcomeName) === normalize(event.home_team) ? event.home_logo : event.away_logo;
    const opp = normalize(outcomeName) === normalize(event.home_team) ? event.away_team : event.home_team;
    setOutcome({ name: outcomeName, price, logo: resolvedLogo });
    setBookmaker(bookmakerTitle);
    setTargetValue(price);
    setOddsInput(String(price));
    setDirection("above");

    setOpponent(opp);

    const min = addPoints(price, -2000);
    const max = addPoints(price, +2000);
    setMinOdds(min);
    setMaxOdds(max);
    setStep(3);
  }

  function goBack() {
    if (step === 2) {
      setStep(1);
      setEvent(null);
      setMarket(null);
    } else if (step === 3) {
      setStep(2);
      setOutcome(null);
      setBookmaker(null);
      setTargetValue("");
      setOddsInput("");
      setMinOdds(null);
      setMaxOdds(null);
      setOpponent(null);
    } else {
      setStep((s) => Math.max(0, s - 1));
    }
  }

  async function handleSaveAlert(e) {
    e.preventDefault();
    if (!event || !market || !outcome || !targetValue || !userEmail) return;

    setSaving(true);
    setSaveError(null);

    try {
      await createAlert({
        alert_type: "Bet 🎟️",
        sport: sport.key,
        event_id: event.id,
        home_team: event.home_team,
        away_team: event.away_team,
        home_logo: event.home_logo || "",
        away_logo: event.away_logo || "",
        market: market.key,
        outcome_name: outcome.name,
        bookmaker,
        target_value: parseFloat(targetValue),
        current_value: outcome.price,
        direction,
        user_email: userEmail,
        commence_time: event.commence_time
      });
      navigate("/");
    } catch (err) {
      setSaveError(err.response?.data?.error || "Could not save the alert. Try again.");
    } finally {
      setSaving(false);
    }
  }

  function getOutcomesForMarket() {
    if (!event || !market) return [];
    const results = [];
    for (const bm of event.bookmakers || []) {
      const mkt = (bm.markets || []).find((m) => m.key === market.key);
      if (mkt) {
        for (const o of mkt.outcomes) {
          results.push({
            name: o.name,
            point: o.point,
            price: o.price,
            bookmaker: bm.title,
          });
        }
      }
    }
    return results;
  }

  const stepLabels = ["Sport", "Game", "Team", "Alert"];

  return (
    <div className="bet-search">
      <h1>Track a betting line</h1>
      <p className="page-subtitle">Pick your bet, set a target, get an email when the odds move.</p>

      <div className="steps-indicator">
        {stepLabels.map((label, i) => (
          <div
            key={label}
            className={`step-pill ${i === step ? "active" : ""} ${i < step ? "done" : ""}`}
          >
            <span className="step-num">{i < step ? "✓" : i + 1}</span>
            {label}
          </div>
        ))}
      </div>

      {step === 0 && (
        <div className="option-grid">
          {loadingSports ? (
            <div className="sports-loading">
              <div style={{ display: "flex", alignItems: "center", gap: "12px", justifyContent: "center" }}>
                <div className="spinner" />
                LOADING...
              </div>
            </div>
          ) : activeSports.length === 0 ? (
            <p className="dim-text">No active sports found right now.</p>
          ) : (
            activeSports.map((s) => (
              <button key={s.key} className="option-card" onClick={() => selectSport(s)}>
                {s.label}
                <span className="event-count">{s.eventCount} games</span>
              </button>
            ))
          )}
        </div>
      )}

      {step === 1 && (
        <>
          {loadingEvents ? (
            <div className="sports-loading">
              <div style={{ display: "flex", alignItems: "center", gap: "12px", justifyContent: "center" }}>
                <div className="spinner" />
                LOADING...
              </div>
            </div>
          ) : (
            <>
              {loadError && <p className="field-error">{loadError}</p>}
              {!loadingEvents && events.length === 0 && !loadError && (
                <p className="dim-text">No games found for {sport.label} right now — try another sport.</p>
              )}
              <div className="option-list">
                {(() => {
                  // Group events by date
                  const grouped = {};
                  events.forEach((e) => {
                    const date = new Date(e.commence_time).toLocaleDateString(undefined, {
                      weekday: "long", month: "long", day: "numeric"
                    });
                    if (!grouped[date]) grouped[date] = [];
                    grouped[date].push(e);
                  });

                  return Object.entries(grouped).map(([date, dateEvents]) => (
                    <div key={date} className="event-group">
                      <p className="event-date-heading">{date}</p>


                      {dateEvents.map((e) => {
                        const isLive = new Date(e.commence_time) <= new Date();
                        return (
                          <button
                            key={e.id}
                            className={`event-card ${isLive ? "event-live" : "event-upcoming"}`}
                            onClick={() => selectEvent(e)}
                          >
                            <span className="event-teams">
                              <span className="team-with-logo">
                                {e.home_logo && (
                                  <img
                                    src={e.home_logo}
                                    alt={e.home_team}
                                    className="team-logo-small"
                                    onError={(e) => { e.target.style.display = "none"; }}
                                  />
                                )}
                                {e.home_team}
                              </span>
                              <span className="vs-text">vs</span>
                              <span className="team-with-logo">
                                {e.away_logo && (
                                  <img
                                    src={e.away_logo}
                                    alt={e.away_team}
                                    className="team-logo-small"
                                    onError={(ev) => { ev.target.style.display = "none"; }}
                                  />
                                )}
                                {e.away_team}
                              </span>
                            </span>
                            {isLive ? (
                              <span className="live-badge">LIVE</span>
                            ) : (
                              <span className="event-time">
                                {new Date(e.commence_time).toLocaleTimeString(undefined, {
                                  hour: "numeric", minute: "2-digit", hour12: true
                                })}
                              </span>
                            )}
                          </button>
                        );
                      })}


                    </div>
                  ));
                })()}
              </div>
              <button className="btn btn-ghost" style={{ marginTop: "16px" }} onClick={goBack}>⬅️ Back</button>
            </>
          )}
        </>
      )}


      {step === 2 && (
        <>
          <div className="option-list">
            {(() => {
              // Group outcomes by bookmaker
              const grouped = {};
              getOutcomesForMarket().forEach((o) => {
                if (!grouped[o.bookmaker]) grouped[o.bookmaker] = [];
                grouped[o.bookmaker].push(o);
              });

              return Object.entries(grouped).map(([bookmakerName, outcomes]) => (
                <div key={bookmakerName} className="bookmaker-card">

                  <div className="bookmaker-label">
                    <img
                      src={`https://img.logokit.com/${BOOKMAKER_DOMAINS[bookmakerName]}?token=${LOGOKIT_TOKEN}`}
                      alt={bookmakerName}
                      className="bookmaker-logo"
                      onError={(e) => { e.target.style.display = "none"; }}
                    />
                    <span>{bookmakerName}</span>
                  </div>

                  <div className="bookmaker-outcomes">
                    {outcomes.map((o, i) => {
                      const logo = o.name === "Draw" ? null : (o.logo || (o.name === event.home_team ? event.home_logo : event.away_logo));
                      console.log("o.name:", o.name, "home_team:", event.home_team, "match:", o.name === event.home_team);
                      return (
                        <button
                          key={i}
                          className="outcome-btn"
                          onClick={() => selectOutcome(o.name, o.price, o.bookmaker, o.logo)}
                        >
                          <span className="outcome-name">
                            {logo && (
                              <img
                                src={logo}
                                alt={o.name}
                                className="team-logo-small"
                                onError={(ev) => { ev.target.style.display = "none"; }}
                              />
                            )}
                            {o.name}{o.point !== undefined ? ` ${o.point > 0 ? "+" : ""}${o.point}` : ""}
                          </span>
                          <span className="odds-num">{formatOdds(o.price)}</span>
                        </button>
                      );
                    })}
                  </div>
                </div>
              ));
            })()}
          </div>
          
          <button className="btn btn-ghost" style={{ marginTop: "16px" }} onClick={goBack}>⬅️ Back</button>
        </>
      )}

      {step === 3 && (
        <>
          <div className="bet-result">
            <div className="bet-result-bookmaker">
              <img
                src={`https://img.logokit.com/${BOOKMAKER_DOMAINS[bookmaker]}?token=${LOGOKIT_TOKEN}`}
                alt={bookmaker}
                className="bookmaker-logo"
                onError={(e) => { e.target.style.display = "none"; }}
              />
              <span>{bookmaker}</span>
            </div>
            
            <div className="bet-result-main">
                {console.log("outcome.logo:", outcome.logo, "outcome.name:", outcome.name)}

              <p className="result-ticker" style={{ display: "flex", alignItems: "center", gap: "8px" }}>
                                
                {outcome.logo && outcome.name !== "Draw" && (
                  <img
                    src={outcome.logo}
                    alt={outcome.name}
                    className="team-logo-small"
                    style={{ width: "28px", height: "28px" }}
                    onError={(ev) => { ev.target.style.display = "none"; }}
                  />
                )}
                {outcome.name}
              </p>

              <p className="result-prev" style={{ display: "flex", alignItems: "center", gap: "6px" }}>
                {outcome.name === "Draw"
                  ? <span style={{ color: "var(--text-primary)", fontWeight: 600 }}>
                      {event.home_team}
                      <span style={{ color: "var(--text-secondary)", fontWeight: 400 }}> vs </span>
                      {event.away_team}
                    </span>
                  : <>
                      vs
                      {(() => {
                        const opponentLogo = normalize(opponent) === normalize(event.home_team) ? event.home_logo : event.away_logo;                        return opponentLogo ? (
                          <img
                            src={opponentLogo}
                            alt={opponent}
                            className="team-logo-small"
                            onError={(ev) => { ev.target.style.display = "none"; }}
                          />
                        ) : null;
                      })()}
                      <span style={{ color: "var(--text-primary)", fontWeight: 600 }}>{opponent}</span>
                    </>
                }
              </p>
            </div>
            <p className="result-price">
              {formatOdds(outcome.price)}
            </p>
          </div>

          <form className="alert-form" onSubmit={handleSaveAlert}>
            <div className="form-row">
              <div className="slider-header">
                <label className="form-label">Target odds:</label>
                <span className="slider-target-display">
                  <span className={parseFloat(targetValue) >= outcome.price ? "above-text" : "below-text"}>
                    {parseFloat(targetValue) >= outcome.price ? "▲" : "▼"}
                    {formatOdds(parseFloat(targetValue))}</span><span className={parseFloat(targetValue) >= outcome.price ? "above-text" : "below-text"} style={{ fontSize: "12px", fontWeight: 400 }}>
                  </span>
                </span>
              </div>

              <div style={{ display: "flex", alignItems: "center", gap: "10px", margin: "12px 0" }}>
                <label className="form-label" style={{ margin: 0, whiteSpace: "nowrap" }}>Or type odds:</label>
                <input
                  type="number"
                  value={oddsInput}
                  onChange={(e) => {
                    const raw = e.target.value;
                    setOddsInput(raw);
                    const val = parseInt(raw);
                    if (isNaN(val)) return;
                    if (val > -100 && val < 100) return; // invalid odds
                    if (minOdds !== null && val < minOdds) return; // below range
                    if (maxOdds !== null && val > maxOdds) return; // above range
                    setTargetValue(val);
                    setDirection(val >= outcome.price ? "above" : "below");
                  }}
                  className="text-input mono"
                  style={{ width: "120px" }}
                />
              </div>

              <div className="slider-wrapper">
                {(() => {
                  const currentOdds = outcome.price;

                  const oddsToLinear = (odds) => odds >= 100 ? odds - 200 : odds;

                  const toSlider = (odds) => {
                    const linear = oddsToLinear(odds);
                    const minLinear = oddsToLinear(minOdds);
                    const maxLinear = oddsToLinear(maxOdds);
                    return ((linear - minLinear) / (maxLinear - minLinear)) * 200;
                  };

                  const fromSlider = (raw) => {
                    const minLinear = oddsToLinear(minOdds);
                    const maxLinear = oddsToLinear(maxOdds);
                    const linear = Math.round(minLinear + (raw / 200) * (maxLinear - minLinear));
                    if (linear > -100 && linear < 100) return linear >= 0 ? 100 : -100;
                    return linear >= 100 ? linear + 200 : linear;
                  };

                  const currentPct = (toSlider(currentOdds) / 200) * 100;
                  const targetPct = (toSlider(parseFloat(targetValue)) / 200) * 100;
                  const target = parseFloat(targetValue);


                  return (
                    <div className="slider-wrapper">
                      <input
                        type="range"
                        min={0}
                        max={200}
                        step="1"
                        value={toSlider(parseFloat(targetValue))}
                        onChange={(e) => {
                          const odds = fromSlider(parseFloat(e.target.value));
                          setTargetValue(odds);
                          setOddsInput(String(odds));
                          setDirection(odds >= currentOdds ? "above" : "below");
                        }}
                        className="price-slider"
                        style={{
                          background: target >= currentOdds
                            ? `linear-gradient(to right,
                                #2A3038 0%,
                                #2A3038 ${currentPct}%,
                                #3DDC97 ${currentPct}%,
                                #3DDC97 ${targetPct}%,
                                #2A3038 ${targetPct}%,
                                #2A3038 100%)`
                            : `linear-gradient(to right,
                                #2A3038 0%,
                                #2A3038 ${targetPct}%,
                                #E0585C ${targetPct}%,
                                #E0585C ${currentPct}%,
                                #2A3038 ${currentPct}%,
                                #2A3038 100%)`
                        }}
                      />
                      <div className="slider-labels">
                        <span>{formatOdds(minOdds)}</span>
                        <span className="slider-current-marker">Current: {formatOdds(currentOdds)}</span>
                        <span>{formatOdds(maxOdds)}</span>
                      </div>
                    </div>
                  );
                })()}

              </div>
            </div>

            {saveError && <p className="field-error">{saveError}</p>}

            <button type="submit" className="btn btn-primary btn-block" disabled={saving}>
              {saving ? "Saving…" : "Set alert"}
            </button>
          </form>

          <button className="btn btn-ghost" style={{ marginTop: "16px" }} onClick={goBack}>⬅️ Back</button>
        </>
      )}
    </div>
  );
}