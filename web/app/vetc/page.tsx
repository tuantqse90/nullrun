"use client";

// VETC Engagement Console (AABW 2026 demo) — the partner-facing view of the
// NullShift engine running on mobility events: live stats, traffic-by-hour
// with peak-hour shading, DB-driven missions, and the AI panel
// (insight / personalize / win-back). Auth: the same x-partner-token the
// reconciliation API uses.

import { useCallback, useEffect, useState } from "react";
import { api } from "@/lib/api";

type EngageStats = {
  today: { events: number; drivers: number; points_minted: number };
  events_by_hour: { hour: number; count: number }[];
  by_type: { event_type: string; count: number }[];
  recent: {
    user_ref: string;
    event_type: string;
    station: string | null;
    province: string | null;
    occurred_at: string;
  }[];
  missions: {
    key: string;
    title: string;
    description: string;
    cadence: string;
    target: number;
    reward_points: number;
    achieved_count: number;
  }[];
  peak_hours: [number, number][];
};

const TYPE_LABEL: Record<string, string> = {
  toll_pass: "Qua trạm",
  topup: "Nạp tiền",
  fuel: "Đổ xăng",
  parking: "Đỗ xe",
};
const CADENCE_LABEL: Record<string, string> = {
  daily: "ngày",
  weekly: "tuần",
  monthly: "tháng",
};

export default function VetcConsole() {
  const [token, setToken] = useState("");
  const [ready, setReady] = useState(false);
  const [error, setError] = useState("");
  const [stats, setStats] = useState<EngageStats | null>(null);

  const [phone, setPhone] = useState("");
  const [aiBusy, setAiBusy] = useState("");
  const [aiOut, setAiOut] = useState<{ kind: string; data: unknown } | null>(null);

  useEffect(() => {
    const saved = localStorage.getItem("partner_token");
    if (saved) setToken(saved);
  }, []);

  const refresh = useCallback(async () => {
    setError("");
    try {
      setStats(
        await api<EngageStats>("/v1/partner/engage/stats", {
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

  const runAi = async (kind: "insight" | "personalize" | "winback") => {
    setAiBusy(kind);
    setAiOut(null);
    try {
      const data = await api<unknown>(`/v1/partner/ai/${kind}`, {
        method: "POST",
        body: { user_ref: phone },
        headers: { "x-partner-token": token },
      });
      setAiOut({ kind, data });
    } catch (e) {
      setAiOut({ kind, data: { error: (e as Error).message } });
    }
    setAiBusy("");
  };

  if (!ready) {
    return (
      <main className="console gate">
        <h1>🛣️ VETC Engagement Console</h1>
        <p className="sub">
          Engine gamification NullShift chạy trên sự kiện di chuyển — demo AABW 2026.
        </p>
        <div className="row">
          <input
            type="password"
            placeholder="x-partner-token"
            value={token}
            onChange={(e) => setToken(e.target.value)}
          />
          <button onClick={refresh}>Vào console</button>
        </div>
        {error && <p className="error">{error}</p>}
        <style dangerouslySetInnerHTML={{ __html: styles }} />
      </main>
    );
  }

  const maxHour = Math.max(1, ...(stats?.events_by_hour.map((h) => h.count) ?? [1]));
  const isPeak = (h: number) =>
    (stats?.peak_hours ?? []).some(([a, b]) => h >= a && h < b);

  return (
    <main className="console">
      <header>
        <h1>🛣️ VETC Engagement Console</h1>
        <button className="ghost" onClick={refresh}>↻ Làm mới</button>
      </header>

      <section className="cards">
        <div className="card stat">
          <span className="label">Sự kiện hôm nay</span>
          <span className="big">{stats?.today.events ?? 0}</span>
        </div>
        <div className="card stat">
          <span className="label">Tài xế hoạt động</span>
          <span className="big">{stats?.today.drivers ?? 0}</span>
        </div>
        <div className="card stat">
          <span className="label">Điểm đã mint</span>
          <span className="big green">{stats?.today.points_minted ?? 0}</span>
        </div>
      </section>

      <section className="card">
        <h2>Lưu lượng theo giờ (VN) — vùng đỏ là giờ cao điểm</h2>
        <div className="chart">
          {Array.from({ length: 24 }, (_, h) => {
            const count = stats?.events_by_hour.find((x) => x.hour === h)?.count ?? 0;
            return (
              <div key={h} className="col" title={`${h}h: ${count}`}>
                <div
                  className={`bar ${isPeak(h) ? "peak" : ""}`}
                  style={{ height: `${(count / maxHour) * 90 + (count > 0 ? 6 : 1)}px` }}
                />
                <span className="hour">{h}</span>
              </div>
            );
          })}
        </div>
        <p className="note">
          Nhiệm vụ &quot;Né giờ cao điểm&quot; trả thưởng cho chuyến NGOÀI vùng đỏ — engine
          không bao giờ thưởng chạy nhanh/chạy ẩu.
        </p>
      </section>

      <div className="grid2">
        <section className="card">
          <h2>Nhiệm vụ (DB rows — sửa không cần code)</h2>
          <table>
            <thead>
              <tr><th>Nhiệm vụ</th><th>Kỳ</th><th>Thưởng</th><th>Đạt kỳ này</th></tr>
            </thead>
            <tbody>
              {stats?.missions.map((m) => (
                <tr key={m.key}>
                  <td>
                    <b>{m.title}</b>
                    <div className="dim">{m.description}</div>
                  </td>
                  <td>{CADENCE_LABEL[m.cadence] ?? m.cadence}</td>
                  <td className="green">+{m.reward_points}</td>
                  <td>{m.achieved_count} tài xế</td>
                </tr>
              ))}
            </tbody>
          </table>
        </section>

        <section className="card">
          <h2>Sự kiện gần nhất</h2>
          <table>
            <thead>
              <tr><th>Tài xế</th><th>Loại</th><th>Trạm</th><th>Lúc</th></tr>
            </thead>
            <tbody>
              {stats?.recent.map((r, i) => (
                <tr key={i}>
                  <td>{r.user_ref}</td>
                  <td>{TYPE_LABEL[r.event_type] ?? r.event_type}</td>
                  <td>{r.station ?? "—"}{r.province ? ` · ${r.province}` : ""}</td>
                  <td className="dim">
                    {new Date(r.occurred_at).toLocaleTimeString("vi-VN", {
                      hour: "2-digit",
                      minute: "2-digit",
                      timeZone: "Asia/Ho_Chi_Minh",
                    })}
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        </section>
      </div>

      <section className="card ai">
        <h2>🤖 AI cá nhân hoá (DeepSeek-compatible, chọn từ template — không bịa economy)</h2>
        <div className="row">
          <input
            placeholder="SĐT tài xế, vd 0931005983"
            value={phone}
            onChange={(e) => setPhone(e.target.value)}
          />
          <button disabled={!phone || !!aiBusy} onClick={() => runAi("insight")}>
            {aiBusy === "insight" ? "Đang viết…" : "Thẻ insight"}
          </button>
          <button disabled={!phone || !!aiBusy} onClick={() => runAi("personalize")}>
            {aiBusy === "personalize" ? "Đang chọn…" : "Cá nhân hoá nhiệm vụ"}
          </button>
          <button disabled={!phone || !!aiBusy} onClick={() => runAi("winback")}>
            {aiBusy === "winback" ? "Đang viết…" : "Win-back"}
          </button>
        </div>
        {aiOut && <AiResult kind={aiOut.kind} data={aiOut.data} />}
      </section>

      <style dangerouslySetInnerHTML={{ __html: styles }} />
    </main>
  );
}

function AiResult({ kind, data }: { kind: string; data: unknown }) {
  const d = data as Record<string, unknown>;
  if (d.error) return <p className="error">{String(d.error)}</p>;

  if (kind === "insight") {
    return (
      <div className="aiCard">
        <div className="badge">{d.ai ? "AI" : "template"}</div>
        <h3>{String(d.headline ?? "")}</h3>
        <p>{String(d.body ?? "")}</p>
      </div>
    );
  }
  if (kind === "personalize") {
    const applied = (d.applied ?? []) as {
      title: string;
      base_target: number;
      personal_target: number;
      reward_points: number;
      cadence: string;
    }[];
    return (
      <div className="aiCard">
        <div className="badge">{d.ai ? "AI" : "heuristic"}</div>
        <p><i>{String(d.rationale ?? "")}</i></p>
        <ul>
          {applied.map((a, i) => (
            <li key={i}>
              <b>{a.title}</b> — chỉ tiêu {a.base_target} → <b>{a.personal_target}</b>
              {" "}(+{a.reward_points} điểm/{CADENCE_LABEL[a.cadence] ?? a.cadence})
            </li>
          ))}
        </ul>
        <p className="dim">Đã ghi đè chỉ tiêu cho kỳ hiện tại — bảng nhiệm vụ của tài xế đổi ngay.</p>
      </div>
    );
  }
  return (
    <div className="aiCard">
      <div className="badge">{d.ai ? "AI" : "template"}</div>
      <p>
        Rủi ro rời bỏ: <b>{Math.round(Number(d.risk_score ?? 0) * 100)}%</b>
        {" "}· im ắng {String(d.days_inactive)} ngày
      </p>
      <p className="msg">💬 {String(d.message ?? "")}</p>
    </div>
  );
}

const styles = `
  .console { max-width: 1060px; margin: 0 auto; padding: 28px 20px 60px;
    font-family: ui-sans-serif, system-ui; color: #26221c; }
  .console .gate { max-width: 520px; padding-top: 90px; }
  header { display: flex; justify-content: space-between; align-items: center;
    margin-bottom: 18px; }
  h1 { font-size: 24px; margin: 0 0 6px; }
  h2 { font-size: 15px; margin: 0 0 12px; }
  .console .sub { color: #8a8072; margin: 0 0 18px; }
  .console .row { display: flex; gap: 8px; flex-wrap: wrap; }
  input { flex: 1; min-width: 220px; padding: 10px 12px; border: 1px solid #ece6da;
    border-radius: 10px; font-size: 14px; background: #fff; }
  button { padding: 10px 16px; border: 0; border-radius: 10px; background: #1e8a5b;
    color: #fff; font-weight: 600; cursor: pointer; }
  button:disabled { opacity: .5; cursor: default; }
  .console .ghost { background: #ece6da; color: #26221c; }
  .console .error { color: #b3403a; }
  .console .cards { display: grid; grid-template-columns: repeat(3, 1fr); gap: 12px;
    margin-bottom: 12px; }
  .console .card { background: #fff; border: 1px solid #ece6da; border-radius: 16px;
    padding: 16px 18px; margin-bottom: 12px; }
  .console .stat { margin-bottom: 0; }
  .console .label { color: #8a8072; font-size: 12.5px; }
  .console .big { display: block; font-size: 30px; font-weight: 800; margin-top: 2px; }
  .console .green { color: #14663f; }
  .console .grid2 { display: grid; grid-template-columns: 1.2fr 1fr; gap: 12px; }
  @media (max-width: 800px) { .console .grid2, .console .cards { grid-template-columns: 1fr; } }
  .console .chart { display: flex; align-items: flex-end; gap: 3px; height: 120px;
    padding-top: 8px; }
  .console .col { flex: 1; display: flex; flex-direction: column; align-items: center;
    gap: 3px; }
  .console .bar { width: 100%; background: #34b37d; border-radius: 3px 3px 0 0; }
  .console .bar.peak { background: #e8834a; }
  .console .hour { font-size: 9px; color: #a29a8b; }
  .console .note { font-size: 12px; color: #8a8072; margin: 10px 0 0; }
  table { width: 100%; border-collapse: collapse; font-size: 13px; }
  th { text-align: left; color: #8a8072; font-weight: 600; font-size: 11.5px;
    padding: 4px 6px; border-bottom: 1px solid #f0eae0; }
  td { padding: 7px 6px; border-bottom: 1px solid #f7f4ee; vertical-align: top; }
  .console .dim { color: #a29a8b; font-size: 11.5px; }
  .console .ai { background: #1d1830; color: #f2ede4; border: 0; }
  .console .ai h2 { color: #d9ccf2; }
  .console .ai input { background: #2a2244; border-color: #3a2f5c; color: #fff; }
  .console .aiCard { background: #2a2244; border-radius: 12px; padding: 14px 16px;
    margin-top: 12px; position: relative; }
  .console .aiCard h3 { margin: 4px 0 6px; color: #ffe3ac; }
  .console .aiCard ul { margin: 8px 0; padding-left: 18px; }
  .console .aiCard .dim { color: #8f82b8; }
  .console .badge { position: absolute; top: 10px; right: 12px; font-size: 10px;
    font-weight: 800; letter-spacing: .5px; text-transform: uppercase;
    background: #34b37d; color: #12291d; padding: 3px 8px; border-radius: 99px; }
  .console .msg { background: #1d1830; border-radius: 10px; padding: 10px 12px; }

`;
