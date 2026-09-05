import { useState, useEffect } from "react";
import { BrowserRouter, Routes, Route, NavLink, Link } from "react-router-dom";
import Dashboard from "./pages/Dashboard";
import StockSearch from "./pages/StockSearch";
import BetSearch from "./pages/BetSearch";
import SignIn from "./SignIn";
import "./App.css";

const SESSION_KEY = "linetracker_session";

function App() {
  const [session, setSession] = useState(null); // { token, email }
  const [sessionLoaded, setSessionLoaded] = useState(false);

  useEffect(() => {
    try {
      const stored = localStorage.getItem(SESSION_KEY);
      if (stored) setSession(JSON.parse(stored));
    } catch {
      localStorage.removeItem(SESSION_KEY);
    }
    setSessionLoaded(true);

    // api.js clears the stored session and fires this event whenever a
    // request comes back 401 (session expired or revoked) — bounce back
    // to the sign-in screen instead of the app silently breaking.
    function handleExpired() {
      setSession(null);
    }
    window.addEventListener("linetracker:auth-expired", handleExpired);
    return () => window.removeEventListener("linetracker:auth-expired", handleExpired);
  }, []);

  function handleAuth({ token, email }) {
    const next = { token, email };
    localStorage.setItem(SESSION_KEY, JSON.stringify(next));
    setSession(next);
  }

  function handleSignOut() {
    localStorage.removeItem(SESSION_KEY);
    setSession(null);
  }

  const userEmail = session?.email || null;

  return (
    <BrowserRouter>
      {!userEmail && <SignIn onAuth={handleAuth} />}

      {userEmail && (
        <div className="app-shell">
          <header className="app-header">
            <div className="app-header-inner">
              <Link to="/" className="logo-link">
                LINE<span className="logo-accent">TRACKER</span>
              </Link>

              <nav className="main-nav">
                <NavLink
                  to="/stocks"
                  className={({ isActive }) => (isActive ? "nav-link active" : "nav-link")}
                >
                  Stocks 🌱
                </NavLink>
                <NavLink
                  to="/bets"
                  className={({ isActive }) => (isActive ? "nav-link active" : "nav-link")}
                >
                  Bets 🎟️
                </NavLink>
                <button
                  className="nav-link"
                  onClick={handleSignOut}
                  style={{ cursor: "pointer", border: "none", background: "transparent" }}
                >
                  {userEmail} ✕
                </button>
              </nav>
            </div>
          </header>

          <main className="app-main">
            {sessionLoaded && (
              <Routes>
                <Route path="/" element={<Dashboard userEmail={userEmail} />} />
                <Route path="/stocks" element={<StockSearch userEmail={userEmail} />} />
                <Route path="/bets" element={<BetSearch userEmail={userEmail} />} />
              </Routes>
            )}
          </main>
        </div>
      )}
    </BrowserRouter>
  );
}

export default App;
