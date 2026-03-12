"use client";

import { useCallback, useRef, useState } from "react";
import Link from "next/link";

interface ChatMessage {
  id: string;
  role: "user" | "assistant";
  content: string;
  createdAt: string;
}

export default function AIChatPage() {
  const [messages, setMessages] = useState<ChatMessage[]>([]);
  const [input, setInput] = useState("");
  const [sending, setSending] = useState(false);
  const scrollRef = useRef<HTMLDivElement>(null);

  const scrollToBottom = useCallback(() => {
    requestAnimationFrame(() => {
      scrollRef.current?.scrollTo({ top: scrollRef.current.scrollHeight, behavior: "smooth" });
    });
  }, []);

  async function handleSend(event: React.FormEvent) {
    event.preventDefault();
    const text = input.trim();
    if (!text || sending) return;

    const userMsg: ChatMessage = {
      id: crypto.randomUUID(),
      role: "user",
      content: text,
      createdAt: new Date().toISOString()
    };

    const nextMessages = [...messages, userMsg];
    setMessages(nextMessages);
    setInput("");
    setSending(true);
    scrollToBottom();

    try {
      const response = await fetch("/api/ai/chat", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
          messages: nextMessages.slice(-10).map((m) => ({
            role: m.role,
            content: m.content
          }))
        })
      });
      const payload = await response.json();
      if (payload.reply) {
        setMessages((prev) => [...prev, payload.reply]);
        scrollToBottom();
      }
    } catch {
      setMessages((prev) => [
        ...prev,
        {
          id: crypto.randomUUID(),
          role: "assistant",
          content: "抱歉，AI 助手暂时无法回复，请稍后再试。",
          createdAt: new Date().toISOString()
        }
      ]);
    } finally {
      setSending(false);
    }
  }

  return (
    <main className="app-shell ai-chat-shell">
      <header className="ai-chat-header">
        <Link href="/" className="ai-chat-back" aria-label="返回首页">
          <svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round">
            <polyline points="15 18 9 12 15 6" />
          </svg>
        </Link>
        <div>
          <h1>AI 健康助手</h1>
          <p>基于你的健康档案回答问题</p>
        </div>
      </header>

      <div className="ai-chat-messages" ref={scrollRef}>
        {messages.length === 0 ? (
          <div className="ai-chat-empty">
            <p>你可以问我关于你的健康数据的问题，比如：</p>
            <div className="ai-chat-suggestions">
              {["我的血脂最近怎么样？", "睡眠恢复情况如何？", "基因报告有什么关注点？", "怎么上传新数据？"].map(
                (q) => (
                  <button
                    key={q}
                    type="button"
                    className="ai-chat-suggestion-chip"
                    onClick={() => setInput(q)}
                  >
                    {q}
                  </button>
                )
              )}
            </div>
          </div>
        ) : (
          messages.map((msg) => (
            <article
              key={msg.id}
              className={`ai-chat-bubble ${msg.role === "user" ? "is-user" : "is-assistant"}`}
            >
              <p>{msg.content}</p>
            </article>
          ))
        )}
        {sending ? (
          <article className="ai-chat-bubble is-assistant is-loading">
            <p>正在思考...</p>
          </article>
        ) : null}
      </div>

      <form className="ai-chat-input-bar" onSubmit={handleSend}>
        <input
          type="text"
          value={input}
          onChange={(e) => setInput(e.target.value)}
          placeholder="输入你的健康问题..."
          disabled={sending}
          autoFocus
        />
        <button type="submit" disabled={sending || !input.trim()}>
          发送
        </button>
      </form>
    </main>
  );
}
