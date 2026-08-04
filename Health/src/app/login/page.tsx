"use client";

import { useState } from "react";
import { useRouter } from "next/navigation";

type Step = "phone" | "code";

export default function LoginPage() {
  const router = useRouter();
  const [step, setStep] = useState<Step>("phone");
  const [phone, setPhone] = useState("");
  const [code, setCode] = useState("");
  const [error, setError] = useState("");
  const [loading, setLoading] = useState(false);
  const [countdown, setCountdown] = useState(0);

  async function requestCode(event: React.FormEvent) {
    event.preventDefault();
    setError("");
    setLoading(true);

    try {
      const res = await fetch("/api/auth/request-code", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ phoneNumber: phone }),
      });
      const data = await res.json() as { expires_in_seconds?: number; error?: { message?: string }; code?: string };

      if (!res.ok) {
        setError(data.error?.message ?? "发送失败，请稍后重试");
        return;
      }

      setStep("code");
      const expiry = data.expires_in_seconds ?? 300;
      setCountdown(expiry);
      const interval = setInterval(() => {
        setCountdown((prev) => {
          if (prev <= 1) {
            clearInterval(interval);
            return 0;
          }
          return prev - 1;
        });
      }, 1000);
    } catch {
      setError("网络错误，请稍后重试");
    } finally {
      setLoading(false);
    }
  }

  async function verifyCode(event: React.FormEvent) {
    event.preventDefault();
    setError("");
    setLoading(true);

    try {
      const res = await fetch("/api/auth/verify", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ phoneNumber: phone, code }),
      });
      const data = await res.json() as { token?: string; error?: { message?: string } };

      if (!res.ok || !data.token) {
        setError(data.error?.message ?? "验证失败，请重试");
        return;
      }

      const sessionRes = await fetch("/api/auth/session", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ token: data.token }),
      });

      if (!sessionRes.ok) {
        setError("登录失败，请重试");
        return;
      }

      router.replace("/");
    } catch {
      setError("网络错误，请稍后重试");
    } finally {
      setLoading(false);
    }
  }

  return (
    <div className="login-shell">
      <div className="login-card">
        <div className="login-brand">
          <p className="panel-kicker">Vital Command</p>
          <h1 className="login-title">健康经营驾驶舱</h1>
          <p className="login-subtitle">请登录以继续</p>
        </div>

        {step === "phone" ? (
          <form onSubmit={requestCode} className="login-form">
            <div className="login-field">
              <label htmlFor="phone" className="login-label">手机号</label>
              <input
                id="phone"
                type="tel"
                inputMode="numeric"
                autoComplete="tel"
                placeholder="请输入 11 位手机号"
                value={phone}
                onChange={(e) => setPhone(e.target.value.replace(/\D/g, "").slice(0, 11))}
                className="login-input"
                required
                disabled={loading}
              />
            </div>

            {error ? <p className="login-error">{error}</p> : null}

            <button
              type="submit"
              className="login-submit"
              disabled={loading || phone.length !== 11}
            >
              {loading ? "发送中…" : "获取验证码"}
            </button>
          </form>
        ) : (
          <form onSubmit={verifyCode} className="login-form">
            <p className="login-hint">验证码已发至 {phone}</p>

            <div className="login-field">
              <label htmlFor="code" className="login-label">验证码</label>
              <input
                id="code"
                type="text"
                inputMode="numeric"
                autoComplete="one-time-code"
                placeholder="请输入 6 位验证码"
                value={code}
                onChange={(e) => setCode(e.target.value.replace(/\D/g, "").slice(0, 6))}
                className="login-input login-input-code"
                required
                disabled={loading}
                autoFocus
              />
            </div>

            {error ? <p className="login-error">{error}</p> : null}

            <button
              type="submit"
              className="login-submit"
              disabled={loading || code.length !== 6}
            >
              {loading ? "验证中…" : "登录"}
            </button>

            <button
              type="button"
              className="login-resend"
              disabled={countdown > 0}
              onClick={() => {
                setStep("phone");
                setCode("");
                setError("");
              }}
            >
              {countdown > 0 ? `重新发送（${countdown}s）` : "重新发送验证码"}
            </button>
          </form>
        )}
      </div>
    </div>
  );
}
