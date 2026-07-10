import type { Metadata } from "next";
import Link from "next/link";
import "./globals.css";

export const metadata: Metadata = {
  title: "NullShift",
  description: "Chạy thật. Điểm thật. Quà thật.",
};

export default function RootLayout({ children }: { children: React.ReactNode }) {
  return (
    <html lang="vi">
      <body>
        <nav className="top">
          <Link href="/" className="logo">NullShift</Link>
          <Link href="/admin">Admin</Link>
          <Link href="/partner">Partner</Link>
        </nav>
        {children}
      </body>
    </html>
  );
}
