# web/ — dashboard, admin, landing

Next.js 15 (App Router). **Not** the consumer app — that's iOS native (`ios/`).

## Run

```sh
npm install
PORT=3100 npm run dev    # 3000 is taken by another app on this machine
```

Backend must be running (`docker-compose up -d && cd backend && cargo run`).
API base defaults to `http://localhost:8080`; override with `NEXT_PUBLIC_API_BASE`.

## Pages

- `/` — landing (public)
- `/admin` — internal console: today's stats, fraud review queue (approve/reject), user lookup by phone. Token = `ADMIN_API_TOKEN` (dev default `dev-admin-token`).
- `/partner` — Guardian dashboard: redemption volume, active users, challenge performance. Token = `PARTNER_API_TOKEN` (dev default `dev-partner-token`).

Tokens are entered in the page and kept in localStorage. Static-token auth is a
pre-launch placeholder — replace with real auth before external access (M7).
