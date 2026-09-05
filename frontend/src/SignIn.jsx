import { useEffect, useRef, useState } from "react";
import { api } from "./api";
import "./SignIn.css";

const GOOGLE_CLIENT_ID = import.meta.env.VITE_GOOGLE_CLIENT_ID;

export default function SignIn({ onAuth }) {
  const buttonRef = useRef(null);
  const [error, setError] = useState("");
  const [ready, setReady] = useState(false);

  async function handleCredential(response) {
    setError("");
    try {
      const res = await api.post("/auth/google", { credential: response.credential });
      onAuth(res.data);
    } catch (err) {
      setError(
        err.response?.data?.error || "Couldn't sign you in with Google. Please try again."
      );
    }
  }

  useEffect(() => {
    if (!GOOGLE_CLIENT_ID) {
      setError("Google sign-in isn't configured yet (missing VITE_GOOGLE_CLIENT_ID).");
      return;
    }

    // The Google Identity Services script (loaded in index.html) is
    // async/defer, so window.google may not exist on the very first
    // render. Poll briefly until it's ready instead of assuming it's
    // already there.
    let cancelled = false;
    let attempts = 0;

    function tryInit() {
      if (cancelled) return;
      if (window.google?.accounts?.id) {
        window.google.accounts.id.initialize({
          client_id: GOOGLE_CLIENT_ID,
          callback: handleCredential,
        });
        if (buttonRef.current) {
          window.google.accounts.id.renderButton(buttonRef.current, {
            theme: "filled_black",
            size: "large",
            shape: "pill",
            width: 300,
            text: "continue_with",
          });
        }
        setReady(true);
        return;
      }
      attempts += 1;
      if (attempts < 40) {
        setTimeout(tryInit, 100);
      } else {
        setError("Couldn't load Google sign-in. Check your connection and refresh.");
      }
    }

    tryInit();
    return () => {
      cancelled = true;
    };
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  return (
    <div className="sign-in-overlay">
      <div className="sign-in-card">
        <p className="logo" style={{ marginBottom: "8px" }}>
          LINE<span style={{ color: "var(--accent)" }}>TRACKER</span>
        </p>
        <h2 className="sign-in-title">Sign in to continue</h2>
        <p className="sign-in-subtitle">
          Sign in with Google to see your alerts and get notified the moment they hit.
        </p>
        <div ref={buttonRef} className="google-button-slot" />
        {!ready && !error && <p className="sign-in-loading">Loading Google sign-in…</p>}
        {error && <p className="field-error" style={{ marginTop: "12px" }}>{error}</p>}
      </div>
    </div>
  );
}
