// Messenger between React frontend and Flask backend
    // Connects functions like createAlert(), getStockPrice() from app.py (backend) to frontend

import axios from "axios";

const API_BASE = import.meta.env.VITE_API_URL || "http://localhost:5000";
const SESSION_KEY = "linetracker_session";

export const api = axios.create({
  baseURL: API_BASE,
});

// Attach the signed-in user's session token to every request. Nothing
// else in the app needs to remember to do this — sign in once, and every
// api.* call automatically proves who's asking.
api.interceptors.request.use((config) => {
  try {
    const stored = localStorage.getItem(SESSION_KEY);
    if (stored) {
      const { token } = JSON.parse(stored);
      if (token) {
        config.headers.Authorization = `Bearer ${token}`;
      }
    }
  } catch {
    // Malformed/missing session — just send the request unauthenticated
    // and let the backend reject it, same as if there were no session.
  }
  return config;
});

// If the backend ever says the session is invalid/expired, clear it and
// tell the rest of the app so it can bounce back to the sign-in screen,
// instead of silently failing every request from then on.
api.interceptors.response.use(
  (res) => res,
  (err) => {
    if (err.response?.status === 401) {
      localStorage.removeItem(SESSION_KEY);
      window.dispatchEvent(new Event("linetracker:auth-expired"));
    }
    return Promise.reject(err);
  }
);

export async function getAlerts() {
  const res = await api.get("/alerts");
  return res.data;
}

export async function createAlert(payload) {
  const res = await api.post("/alerts", payload);
  return res.data;
}

export async function deleteAlert(id) {
  const res = await api.delete(`/alerts/${id}`);
  return res.data;
}

export async function getStockPrice(ticker) {
  const res = await api.get("/stocks/price", { params: { ticker } });
  return res.data;
}

export async function getOdds(sport, market = "h2h") {
  const res = await api.get("/odds", { params: { sport, market } });
  return res.data;
}
