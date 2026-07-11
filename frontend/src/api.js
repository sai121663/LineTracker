// Messenger between React frontend and Flask backend
    // Connects functions like createAlert(), getStockPrice() from app.py (backend) to frontend

import axios from "axios";

const API_BASE = import.meta.env.VITE_API_URL || "http://localhost:5000";

export const api = axios.create({
  baseURL: API_BASE,
});

export async function getAlerts(email) {
  const params = email ? { email } : {};
  const res = await api.get("/alerts", { params });
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