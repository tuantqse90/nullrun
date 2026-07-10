"use client";

import { useCallback, useEffect, useState } from "react";
import { api } from "@/lib/api";

type PartnerStats = {
  days: number;
  redemptions: { day: string; status: string; count: number; points: number }[];
  active_users: { day: string; count: number }[];
  challenges: { title: string; joined: number; completed: number }[];
};

export default function Partner() {
  const [token, setToken] = useState("");
  const [ready, setReady] = useState(false);
  const [error, setError] = useState("");
  const [stats, setStats] = useState<PartnerStats | null>(null);

  useEffect(() => {
    const saved = localStorage.getItem("partner_token");
    if (saved) setToken(saved);
  }, []);

  const refresh = useCallback(async () => {
    setError("");
    try {
      setStats(
        await api<PartnerStats>("/v1/partner/stats?days=14", {
          headers: { "x-partner-token": token },
        }),
      );
      setReady(true);
      localStorage.setItem("partner_token", token);
    } catch (e) {
      setReady(false);
      setError((e as Error).message);
    }
  }, [token]);

  if (!ready) {
    return (
      <main>
        <h1>Guardian — Partner dashboard</h1>
        <p className="sub">Nhập partner token để xem báo cáo.</p>
        <div className="row">
          <input
            type="password"
            placeholder="x-partner-token"
            value={token}
            onChange={(e) => setToken(e.target.value)}
          />
          <button onClick={refresh}>Xem báo cáo</button>
        </div>
        {error && <p className="err mt">{error}</p>}
      </main>
    );
  }

  const fulfilled = stats?.redemptions.filter((r) => r.status === "fulfilled") ?? [];
  const totalRedemptions = fulfilled.reduce((a, r) => a + r.count, 0);
  const totalPoints = fulfilled.reduce((a, r) => a + r.points, 0);

  // "Active today" must actually match today's VN date — active_users[0] is
  // merely the most recent day that had any sessions, which is stale on a
  // quiet morning. Show 0 when today has no row yet.
  const todayVN = new Intl.DateTimeFormat("en-CA", {
    timeZone: "Asia/Ho_Chi_Minh",
  }).format(new Date());
  const activeToday =
    stats?.active_users.find((u) => u.day.startsWith(todayVN))?.count ?? 0;

  return (
    <main>
      <div className="row" style={{ justifyContent: "space-between" }}>
        <h1>Guardian — Partner dashboard</h1>
        <button className="ghost" onClick={refresh}>↻ Làm mới</button>
      </div>
      <p className="sub">{stats?.days} ngày gần nhất</p>
      {error && <p className="err">{error}</p>}

      <div className="grid">
        <div className="card stat">
          <div className="n">{totalRedemptions}</div>
          <div className="l">Voucher đã đổi</div>
        </div>
        <div className="card stat">
          <div className="n">{totalPoints.toLocaleString("vi-VN")}</div>
          <div className="l">Điểm quy đổi</div>
        </div>
        <div className="card stat">
          <div className="n">{activeToday}</div>
          <div className="l">User hoạt động hôm nay</div>
        </div>
      </div>

      <h2>Đổi quà theo ngày</h2>
      <div className="card">
        <table>
          <thead>
            <tr><th>Ngày</th><th>Trạng thái</th><th>Số lượt</th><th>Điểm</th></tr>
          </thead>
          <tbody>
            {stats?.redemptions.map((r, i) => (
              <tr key={i}>
                <td>{r.day}</td>
                <td><span className={`badge ${r.status}`}>{r.status}</span></td>
                <td>{r.count}</td>
                <td>{r.points.toLocaleString("vi-VN")}</td>
              </tr>
            ))}
            {stats?.redemptions.length === 0 && (
              <tr><td colSpan={4} className="muted">Chưa có lượt đổi quà nào.</td></tr>
            )}
          </tbody>
        </table>
      </div>

      <h2>User hoạt động theo ngày</h2>
      <div className="card">
        <table>
          <thead><tr><th>Ngày</th><th>User hoạt động</th></tr></thead>
          <tbody>
            {stats?.active_users.map((d) => (
              <tr key={d.day}><td>{d.day}</td><td>{d.count}</td></tr>
            ))}
          </tbody>
        </table>
      </div>

      <h2>Hiệu quả thử thách</h2>
      <div className="card">
        <table>
          <thead><tr><th>Thử thách</th><th>Tham gia</th><th>Hoàn thành</th></tr></thead>
          <tbody>
            {stats?.challenges.map((c) => (
              <tr key={c.title}>
                <td>{c.title}</td><td>{c.joined}</td><td>{c.completed}</td>
              </tr>
            ))}
          </tbody>
        </table>
      </div>
    </main>
  );
}
