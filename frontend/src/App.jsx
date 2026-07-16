import { useState, useEffect } from "react";
import { BrowserRouter, Routes, Route, NavLink, Link } from "react-router-dom";
import Dashboard from "./pages/Dashboard";
import StockSearch from "./pages/StockSearch";
import BetSearch from "./pages/BetSearch";
import EmailGate from "./EmailGate";
import "./App.css";

function App() {
  const [userEmail, setUserEmail] = useState(null);
  const [emailLoaded, setEmailLoaded] = useState(false);
  const [showEmailGate, setShowEmailGate] = useState(false);


  useEffect(() => {
    const stored = localStorage.getItem("linetracker_email");
    if (stored) setUserEmail(stored);
    setEmailLoaded(true);
  }, []);

  function handleEmailSubmit(email) {
    localStorage.setItem("linetracker_email", email);
    setUserEmail(email);
  }

  return (
    <BrowserRouter>
    {(!userEmail || showEmailGate) && (
      <EmailGate
        onSubmit={(email) => {
          localStorage.setItem("linetracker_email", email);
          setUserEmail(email);
          setShowEmailGate(false);
        }}
        onCancel={userEmail ? () => setShowEmailGate(false) : null}
      />
    )}
      
      {userEmail && !showEmailGate && (
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
                {userEmail && (
                  <button
                    className="nav-link"
                    onClick={() => setShowEmailGate(true)}
                    style={{ cursor: "pointer", border: "none", background: "transparent" }}
                  >
                    {userEmail} ✕
                  </button>
                )}
              </nav>
            </div>
          </header>

          <main className="app-main">
            {emailLoaded && (
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