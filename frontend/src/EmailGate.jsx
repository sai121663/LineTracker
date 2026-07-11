import { useState } from "react";
import "./EmailGate.css";

export default function EmailGate({ onSubmit }) {
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
        </form>
      </div>
    </div>
  );
}