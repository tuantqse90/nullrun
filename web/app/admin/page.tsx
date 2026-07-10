"use client";

import { useCallback, useEffect, useState } from "react";
import { api } from "@/lib/api";

type Stats = {
  total_users: number;
  new_users_today: number;
  active_users_today: number;
  sessions_today: Record<string, number>;
  points_minted_today: number;
  points_spent_today: number;
  redemptions_today: Record<string, number>;
  review_pending: number;
};

type ReviewItem = {
  id: string;
  phone: string;
  activity_type: string;
  distance_m: number;
  duration_s: number;
  fraud_score: number | null;
  fraud_flags: string[];
  created_at: string;
};

type Lookup = {
  phone: string;
  display_name: string | null;
  points_balance: number;
  streak_current: number;
  guardian_linked: boolean;
  devices: { platform: string; attested: boolean }[];
  recent_sessions: {
    id: string;
    activity_type: string;
    verdict: string;
    distance_m: number;
    created_at: string;
  }[];
};

export default function Admin() {
  const [token, setToken] = useState("");
  const [ready, setReady] = useState(false);
  const [error, setError] = useState("");
  const [stats, setStats] = useState<Stats | null>(null);
  const [queue, setQueue] = useState<ReviewItem[]>([]);
  const [phone, setPhone] = useState("");
  const [lookup, setLookup] = useState<Lookup | null>(null);

  useEffect(() => {
    const saved = localStorage.getItem("admin_token");
    if (saved) setToken(saved);
  }, []);

  const H = useCallback(() => ({ "x-admin-token": token }), [token]);

  const refresh = useCallback(async () => {
    setError("");
    try {
      setStats(await api<Stats>("/v1/admin/stats", { headers: H() }));
      setQueue(await api<ReviewItem[]>("/v1/admin/review-queue", { headers: H() }));
      setReady(true);
      localStorage.setItem("admin_token", token);
    } catch (e) {
      setReady(false);
      setError((e as Error).message);
    }
  }, [H, token]);

  async function review(id: string, approve: boolean) {
    try {
      await api(`/v1/admin/sessions/${id}/review`, {
        method: "POST",
        body: { approve },
        headers: H(),
      });
      await refresh();
    } catch (e) {
      setError((e as Error).message);
    }
  }

  async function findUser() {
    setError("");
    setLookup(null);
    try {
      setLookup(await api<Lookup>(`/v1/admin/users/${encodeURIComponent(phone)}`, { headers: H() }));
    } catch (e) {
      setError((e as Error).message);
    }
  }

  if (!ready) {
    return (
      <main>
        <h1>Admin console</h1>
        <p className="sub">Nhập admin token để tiếp tục.</p>
        <div className="row">
          <input
            type="password"
            placeholder="x-admin-token"
            value={token}
            onChange={(e) => setToken(e.target.value)}
          />
          <button onClick={refresh}>Đăng nhập</button>
        </div>
        {error && <p className="err mt">{error}</p>}
      </main>
    );
  }

  return (
    <main>
      <div className="row" style={{ justifyContent: "space-between" }}>
        <h1>Admin console</h1>
        <button className="ghost" onClick={refresh}>↻ Làm mới</button>
      </div>
      {error && <p className="err">{error}</p>}

      {stats && (
        <>
          <h2>Hôm nay</h2>
          <div className="grid">
            <Stat n={stats.total_users} l="Tổng user" />
            <Stat n={stats.new_users_today} l="User mới" />
            <Stat n={stats.active_users_today} l="User hoạt động" />
            <Stat n={stats.points_minted_today} l="Điểm phát ra" />
            <Stat n={stats.points_spent_today} l="Điểm tiêu" />
            <Stat n={stats.review_pending} l="Chờ review" />
          </div>
          <div className="row mt muted" style={{ fontSize: "0.85rem" }}>
            Sessions:{" "}
            {Object.entries(stats.sessions_today).map(([k, v]) => (
              <span key={k} className={`badge ${k}`}>{k}: {v}</span>
            ))}
            {Object.entries(stats.redemptions_today).map(([k, v]) => (
              <span key={k} className={`badge ${k}`}>đổi quà {k}: {v}</span>
            ))}
          </div>
        </>
      )}

      <h2>Hàng chờ review gian lận ({queue.length})</h2>
      <div className="card">
        {queue.length === 0 ? (
          <p className="muted">Sạch sẽ — không có session nào chờ review 🎉</p>
        ) : (
          <table>
            <thead>
              <tr>
                <th>User</th><th>Loại</th><th>Quãng đường</th><th>Score</th>
                <th>Cờ</th><th></th>
              </tr>
            </thead>
            <tbody>
              {queue.map((q) => (
                <tr key={q.id}>
                  <td>{q.phone}</td>
                  <td>{q.activity_type}</td>
                  <td>{(q.distance_m / 1000).toFixed(2)} km / {Math.round(q.duration_s / 60)} phút</td>
                  <td>{q.fraud_score?.toFixed(2)}</td>
                  <td>{q.fraud_flags.map((f) => <div key={f} className="badge suspicious">{f}</div>)}</td>
                  <td>
                    <div className="row">
                      <button onClick={() => review(q.id, true)}>Duyệt</button>
                      <button className="danger" onClick={() => review(q.id, false)}>Từ chối</button>
                    </div>
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        )}
      </div>

      <h2>Tra cứu user</h2>
      <div className="row">
        <input placeholder="Số điện thoại (09xx…)" value={phone} onChange={(e) => setPhone(e.target.value)} />
        <button onClick={findUser}>Tìm</button>
      </div>
      {lookup && (
        <div className="card mt">
          <div className="row">
            <strong>{lookup.display_name ?? lookup.phone}</strong>
            <span className="muted">{lookup.phone}</span>
            <span className="badge clean">{lookup.points_balance} điểm</span>
            <span className="badge suspicious">streak {lookup.streak_current}</span>
            {lookup.guardian_linked && <span className="badge fulfilled">Guardian ✓</span>}
            {lookup.devices.map((d, i) => (
              <span key={i} className="badge clean">{d.platform}{d.attested ? " ✓attest" : " ✗"}</span>
            ))}
          </div>
          <table className="mt">
            <thead>
              <tr><th>Session</th><th>Verdict</th><th>Km</th><th>Lúc</th></tr>
            </thead>
            <tbody>
              {lookup.recent_sessions.map((s) => (
                <tr key={s.id}>
                  <td>{s.activity_type}</td>
                  <td><span className={`badge ${s.verdict}`}>{s.verdict}</span></td>
                  <td>{(s.distance_m / 1000).toFixed(2)}</td>
                  <td className="muted">{new Date(s.created_at).toLocaleString("vi-VN")}</td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      )}
    </main>
  );
}

function Stat({ n, l }: { n: number; l: string }) {
  return (
    <div className="card stat">
      <div className="n">{n.toLocaleString("vi-VN")}</div>
      <div className="l">{l}</div>
    </div>
  );
}
