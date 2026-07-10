# NullShift

Running/fitness gamification app for the Vietnamese market.

- **On-device 3D body-scan** progress (body composition / silhouette)
- **ZK-attested activity** — prove achievements without exposing raw biometric data
- **Guardian (Hội Cam) rewards** — redeem genuine activity for real rewards

## Structure

| Path       | What                                                            |
|------------|-----------------------------------------------------------------|
| `backend/` | Rust monolith — Axum, sqlx, Postgres/TimescaleDB, Redis          |
| `ios/`     | iOS native consumer app — Swift/SwiftUI (not scaffolded yet)     |
| `web/`     | Next.js — partner dashboard, admin, landing (not scaffolded yet) |
| `docs/`    | Project spec and locked decisions                                |

## Quick start (backend)

```sh
docker-compose up -d      # Postgres+TimescaleDB (:5433) + Redis (:6380)
cd backend
cargo run                 # runs migrations, serves on :8080
curl localhost:8080/health   # {"db":true,"redis":true,...}
```

See `CLAUDE.md` for locked platform decisions, guardrails, and roadmap sequencing.
