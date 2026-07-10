export default function Landing() {
  return (
    <main style={{ maxWidth: "none", padding: 0 }}>
      <section className="hero">
        <h1>Chạy thật. Điểm thật. Quà thật.</h1>
        <p>
          NullShift biến mỗi bước chạy của bạn thành điểm thưởng — đổi quà thật
          tại Guardian. Không gian lận, không ảo.
        </p>
        <div className="features">
          <div className="card">
            <h2 style={{ marginTop: 0 }}>🏃 Hoạt động thật</h2>
            <p className="muted">
              GPS + cảm biến chuyển động xác thực từng buổi chạy. Chỉ vận động
              thật mới ra điểm.
            </p>
          </div>
          <div className="card">
            <h2 style={{ marginTop: 0 }}>🏆 Điểm & hạng</h2>
            <p className="muted">
              Streak mỗi ngày, leaderboard hàng tuần, thử thách cá nhân — càng
              đều đặn càng lên hạng.
            </p>
          </div>
          <div className="card">
            <h2 style={{ marginTop: 0 }}>🎁 Quà Guardian</h2>
            <p className="muted">
              Liên kết Hội Cam và đổi điểm lấy voucher sử dụng tại hệ thống cửa
              hàng Guardian.
            </p>
          </div>
        </div>
        <p className="mt muted">Sắp ra mắt trên iOS 🍎</p>
      </section>
    </main>
  );
}
