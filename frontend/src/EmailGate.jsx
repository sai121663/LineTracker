import { useState } from "react";
import "./EmailGate.css";

export default function EmailGate({ onSubmit, onCancel }) {
  const [email, setEmail] = useState("");
  const [error, setError] = useState("");

  function handleSubmit(e) {
    e.preventDefault();
    if (!email.includes("@")) {
      setError("Please enter a valid email.");
      return;
    }
    onSubmit(email);
  }

  return (
    <div className="email-gate-overlay">
      <div className="email-gate-card">
        <p className="logo" style={{ marginBottom: "8px" }}>
          LINE<span style={{ color: "var(--accent)" }}>TRACKER</span>
        </p>
        <h2 className="email-gate-title">What's your email?</h2>
        <p className="email-gate-subtitle">
          We'll use this to show your alerts and send you notifications.
        </p>
        <form onSubmit={handleSubmit}>
          <input
            type="email"
            placeholder="you@example.com"
            value={email}
            onChange={(e) => setEmail(e.target.value)}
            className="text-input"
            autoFocus
          />
          {error && <p className="field-error" style={{ marginTop: "8px" }}>{error}</p>}
          <button type="submit" className="btn btn-primary btn-block" style={{ marginTop: "12px" }}>
            Continue
          </button>
          {onCancel && (
            <button
              type="button"
              className="btn btn-ghost btn-block"
              style={{ marginTop: "8px" }}
              onClick={onCancel}
            >
              Cancel
            </button>
          )}
        </form>
      </div>
    </div>
  );
}