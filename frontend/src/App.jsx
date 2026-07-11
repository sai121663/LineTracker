import { useState, useEffect } from "react";
import { BrowserRouter, Routes, Route, NavLink, Link } from "react-router-dom";
import Dashboard from "./pages/Dashboard";
import StockSearch from "./pages/StockSearch";
import BetSearch from "./pages/BetSearch";
import EmailGate from "./EmailGate";
import "./App.css";

function App() {
  const [userEmail, setUserEmail] = useState(null);

  useEffect(() => {
    const stored = localStorage.getItem("linetracker_email");
    if (stored) setUserEmail(stored);
  }, []);

  function handleEmailSubmit(email) {
    localStorage.setItem("linetracker_email", email);
    setUserEmail(email);
  }

  return (
    <BrowserRouter>
      {!userEmail && <EmailGate onSubmit={handleEmailSubmit} />}
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
            </nav>
          </div>
        </header>

        <main className="app-main">
          <Routes>
            <Route path="/" element={<Dashboard userEmail={userEmail} />} />
            <Route path="/stocks" element={<StockSearch userEmail={userEmail} />} />
            <Route path="/bets" element={<BetSearch userEmail={userEmail} />} />
          </Routes>
        </main>
      </div>
    </BrowserRouter>
  );
}

export default App;