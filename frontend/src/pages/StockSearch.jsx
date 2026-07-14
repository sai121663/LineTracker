import { useState, useRef, useEffect } from "react";
import { useNavigate } from "react-router-dom";
import { getStockPrice, createAlert } from "../api";
import "./StockSearch.css";

export default function StockSearch({ userEmail }) {
  const navigate = useNavigate();

  const [email, setEmail] = useState(userEmail || "");

  const LOGOKIT_TOKEN = import.meta.env.VITE_LOGOKIT_API_TOKEN;
  const FMP_KEY = import.meta.env.VITE_FMP_API_KEY;

  const [ticker, setTicker] = useState("");
  const [stock, setStock] = useState(null);
  const [searchError, setSearchError] = useState(null);
  const [searching, setSearching] = useState(false);

  const [direction, setDirection] = useState("above");
  const [targetValue, setTargetValue] = useState("");
  const [saving, setSaving] = useState(false);
  const [saveError, setSaveError] = useState(null);

  const [query, setQuery] = useState("");
  const [suggestions, setSuggestions] = useState([]);
  const [showDropdown, setShowDropdown] = useState(false);
  const [searchedTicker, setSearchedTicker] = useState("");

  const [searchMode, setSearchMode] = useState("name");
  const [priceInput, setPriceInput] = useState("");

  const debounceRef = useRef(null);
  const dropdownRef = useRef(null);

  useEffect(() => {
    function handleClickOutside(e) {
      if (dropdownRef.current && !dropdownRef.current.contains(e.target)) {
        setShowDropdown(false);
      }
    }
    document.addEventListener("mousedown", handleClickOutside);
    return () => document.removeEventListener("mousedown", handleClickOutside);
  }, []);

  useEffect(() => {
    if (query.trim().length > 0) {
      fetchSuggestions(query);
    }
  }, [searchMode]);

  async function handleSearch(e) {
    e.preventDefault();
    if (!ticker.trim()) return;

    setSearching(true);
    setSearchError(null);
    setStock(null);

    try {
      const data = await getStockPrice(ticker.trim().toUpperCase());
      setStock(data);
      setSearchedTicker(ticker.trim().toUpperCase());
      setTargetValue(data.price);
    } catch (err) {
      setSearchError(
        err.response?.data?.error || "Could not find that ticker. Double check the symbol."
      );
    } finally {
      setSearching(false);
    }
  }

  async function fetchSuggestions(q) {
    if (!q.trim() || q.length < 1) {
      setSuggestions([]);
      return;
    }
    try {
      const endpoint = searchMode === "name"
        ? `https://financialmodelingprep.com/stable/search-name?query=${q}&apikey=${FMP_KEY}`
        : `https://financialmodelingprep.com/stable/search-symbol?query=${q}&apikey=${FMP_KEY}`;

      const res = await fetch(endpoint);
      const data = await res.json();
      setSuggestions(data || []);
      setShowDropdown(true);
    } catch (err) {
      setSuggestions([]);
    }
  }

function handleQueryChange(e) {
  const val = e.target.value;
  setQuery(val);
  setSearchError(null);
  clearTimeout(debounceRef.current);
  debounceRef.current = setTimeout(() => {
    fetchSuggestions(val);
  }, 300);
}

async function selectSuggestion(symbol, name) {
  setQuery(symbol);
  setShowDropdown(false);
  setSuggestions([]);
  setSearchError(null);
  setSearching(true);
  try {
    const data = await getStockPrice(symbol);
    setStock({ ...data, companyName: name });
    setSearchedTicker(symbol);
    setTargetValue(data.price);
    setSearchError(null);
    setPriceInput(String(data.price));
  } catch (err) {
    setSearchError(
      err.response?.data?.error || "Could not fetch price. Try again."
    );
  } finally {
    setSearching(false);
  }
}

  async function handleSaveAlert(e) {
    e.preventDefault();
    if (!stock || !targetValue || !userEmail) return;

    setSaving(true);
    setSaveError(null);

    try {
      await createAlert({
        alert_type: "Stock 🌱",
        ticker: stock.ticker,
        company_name: stock.companyName,
        target_value: parseFloat(targetValue),
        current_value: stock.price,
        direction,
        user_email: email,
      });
      navigate("/");
    } catch (err) {
      setSaveError(err.response?.data?.error || "Could not save the alert. Try again.");
    } finally {
      setSaving(false);
    }

  }

  return (
    <div className="stock-search">
      <h1>Track a stock</h1>
      <p className="page-subtitle">Look up a ticker, set your target, get an email when it hits.</p>

{/*  */}
      <div className="search-wrapper" ref={dropdownRef}>
        <div className="search-mode-toggle">
          <button
            type="button"
            className={searchMode === "name" ? "toggle-btn active" : "toggle-btn"}
            onClick={() => setSearchMode("name")}
          >
            Company
          </button>
          <button
            type="button"
            className={searchMode === "symbol" ? "toggle-btn active" : "toggle-btn"}
            onClick={() => setSearchMode("symbol")}
          >
            Ticker 
          </button>
        </div>

        <input
          type="text"
          placeholder="Search"
          value={query}
          onChange={handleQueryChange}
          onFocus={() => suggestions.length > 0 && setShowDropdown(true)}
          className="text-input mono"
          autoFocus
        />
        
        {showDropdown && suggestions.length > 0 && (
          <div className="dropdown">
            {suggestions.map((s) => (
              <button
                key={s.symbol}
                className="dropdown-item"
                onMouseDown={() => selectSuggestion(s.symbol, s.name)}
              >
            
                <span className="dropdown-ticker">{s.symbol}</span>
                <span className="dropdown-name">{s.name}</span>
              </button>
            ))}
          </div>
        )}
      </div>
{/*  */}

      {searchError && <p className="field-error">{searchError}</p>}

      {stock && (
        <>
        <div className="stock-result">
          <div className="stock-result-left">
            <img
              src={`https://img.logokit.com/ticker/${searchedTicker}?token=${LOGOKIT_TOKEN}`}
              alt={searchedTicker}
              onError={(e) => { e.target.style.display = "none"; }}
            />

            <div>
              <p className="result-ticker">{stock.ticker}</p>
              <span style={{
                fontSize: "11px",
                fontFamily: "var(--font-mono)",
                background: "white",
                border: "1px solid var(--border-bright)",
                borderRadius: "999px",
                padding: "2px 8px",
                color: "black"
              }}>
                Closed at ${stock.previous_close.toFixed(2) ?? "—"}
              </span>
            </div>
          </div>
          
            <p className="result-price">${stock.price.toFixed(2)}</p>
          </div>

          <form className="alert-form" onSubmit={handleSaveAlert}>
            <div className="form-row">

              <div className="slider-header">
                <label className="form-label">Target Price: </label>
                <span className="slider-target-display">
                  <span style={{ color: parseFloat(targetValue) >= stock.price ? "green" : "red"}}>
                    {parseFloat(targetValue) >= stock.price ? "▲" : "▼"}
                  </span>
                  <span className={parseFloat(targetValue) >= stock.price ? "above-text" : "below-text"}>
                    ${parseFloat(targetValue).toFixed(2)}
                  </span>
                </span>
              </div>

              <div style={{ display: "flex", alignItems: "center", gap: "10px", margin: "12px 0" }}>
                <label className="form-label" style={{ margin: 0, whiteSpace: "nowrap" }}>Or type price:</label>
                <input
                  type="number"
                  step="0.01"
                  value={priceInput}
                  onChange={(e) => {
                    const raw = e.target.value;
                    setPriceInput(raw);
                    const val = parseFloat(raw);
                    if (isNaN(val)) return;
                    if (val <= 0) return;
                    setTargetValue(val);
                    setDirection(val >= stock.price ? "above" : "below");
                  }}
                  className="text-input mono"
                  style={{ width: "120px" }}
                />
              </div>

              <div className="slider-wrapper">
                <input
                  type="range"
                  min={(stock.price * 0.5).toFixed(2)}
                  max={(stock.price * 1.5).toFixed(2)}
                  step="0.01"
                  value={targetValue}
                  onChange={(e) => {
                    const val = parseFloat(e.target.value);
                    setTargetValue(val);
                    setPriceInput(String(val));
                    setDirection(val >= stock.price ? "above" : "below");
                  }}
                  className="price-slider"
                  style={{
                    background: (() => {
                      const min = stock.price * 0.5;
                      const max = stock.price * 1.5;
                      const current = stock.price;
                      const target = parseFloat(targetValue);
                      const currentPct = ((current - min) / (max - min)) * 100;
                      const targetPct = ((target - min) / (max - min)) * 100;

                      if (target >= current) {
                        return `linear-gradient(to right,
                          #2A3038 0%,
                          #2A3038 ${currentPct}%,
                          #3DDC97 ${currentPct}%,
                          #3DDC97 ${targetPct}%,
                          #2A3038 ${targetPct}%,
                          #2A3038 100%)`;
                      } else {
                        return `linear-gradient(to right,
                          #2A3038 0%,
                          #2A3038 ${targetPct}%,
                          #E0585C ${targetPct}%,
                          #E0585C ${currentPct}%,
                          #2A3038 ${currentPct}%,
                          #2A3038 100%)`;
                      }
                    })()
                  }}
                />
                <div className="slider-labels">
                  <span>${(stock.price * 0.5).toFixed(2)}</span>
                  <span className="slider-current-marker">Current: ${stock.price.toFixed(2)}</span>
                  <span>${(stock.price * 1.5).toFixed(2)}</span>
                </div>
              </div>
            </div>

            {saveError && <p className="field-error">{saveError}</p>}

            <button type="submit" className="btn btn-primary btn-block" disabled={saving}>
              {saving ? "Saving…" : "Set alert"}
            </button>
          </form>
        </>
      )}
    </div>
  );
}