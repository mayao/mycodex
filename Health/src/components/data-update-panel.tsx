"use client";

import { startTransition, useMemo, useState } from "react";
import { useRouter } from "next/navigation";

import type {
  HealthImportOption,
  HealthSourceDimensionCard
} from "../server/domain/health-hub";

interface ImportResponsePayload {
  accepted?: boolean;
  task?: {
    importTaskId: string;
    title: string;
    importerKey?: string;
    taskStatus: string;
    startedAt: string;
  };
  error?: {
    message: string;
  };
}

export function DataUpdatePanel({
  options,
  sources
}: {
  options: HealthImportOption[];
  sources: HealthSourceDimensionCard[];
}) {
  const router = useRouter();
  const [selectedKey, setSelectedKey] = useState<string>(options[0]?.key ?? "annual_exam");
  const [file, setFile] = useState<File | null>(null);
  const [submitting, setSubmitting] = useState(false);
  const [result, setResult] = useState<ImportResponsePayload["task"]>();
  const [error, setError] = useState<string>();

  const selectedOption = useMemo(
    () => options.find((option) => option.key === selectedKey) ?? options[0],
    [options, selectedKey]
  );

  async function handleSubmit(event: React.FormEvent<HTMLFormElement>) {
    event.preventDefault();

    if (!file || !selectedOption) {
      setError("请选择要导入的文件。");
      return;
    }

    setSubmitting(true);
    setError(undefined);
    setResult(undefined);

    const formData = new FormData();
    formData.append("importerKey", selectedOption.key);
    formData.append("file", file);

    try {
      const response = await fetch("/api/imports", {
        method: "POST",
        body: formData
      });
      const payload = (await response.json()) as ImportResponsePayload;

      if (!response.ok || !payload.task) {
        setError(payload.error?.message ?? "导入失败，请检查文件格式和列名。");
        return;
      }

      setResult(payload.task);
      setFile(null);
      startTransition(() => {
        router.refresh();
      });
    } catch {
      setError("导入请求未完成，请稍后重试。");
    } finally {
      setSubmitting(false);
    }
  }

  function handleRefresh() {
    startTransition(() => {
      router.refresh();
    });
  }

  return (
    <section id="data-update" className="data-update-panel">
      <div className="data-update-copy">
        <div className="data-update-header">
          <div>
            <p className="panel-kicker">Data Update</p>
            <h2>上传新数据，自动刷新洞察</h2>
          </div>
          <button type="button" className="refresh-button" onClick={handleRefresh} title="刷新数据">
            <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round">
              <polyline points="23 4 23 10 17 10" />
              <path d="M20.49 15a9 9 0 1 1-2.12-9.36L23 10" />
            </svg>
            刷新
          </button>
        </div>
        <p className="panel-description">
          上传后会自动完成字段映射、单位换算和异常标记，并更新当前健康档案。
        </p>

        <div className="data-update-status-grid">
          {sources.map((source) => (
            <article key={source.key} className={`data-update-status-card source-${source.status}`}>
              <span>{source.label}</span>
              <strong>{source.highlight}</strong>
              <p>{source.latestAt ? `最近记录 ${source.latestAt.slice(0, 10)}` : "还没有导入记录"}</p>
            </article>
          ))}
        </div>
      </div>

      <form className="data-update-form" onSubmit={handleSubmit}>
        <div className="importer-chip-row" role="radiogroup" aria-label="选择导入类型">
          {options.map((option) => (
            <button
              key={option.key}
              type="button"
              className={option.key === selectedKey ? "importer-chip is-active" : "importer-chip"}
              onClick={() => setSelectedKey(option.key)}
            >
              {option.title}
            </button>
          ))}
        </div>

        {selectedOption ? (
          <div className="importer-detail-card">
            <h3>{selectedOption.title}</h3>
            <p>{selectedOption.description}</p>
            <div className="importer-meta-row">
              {selectedOption.formats.map((format) => (
                <span key={format} className="mini-pill">
                  {format}
                </span>
              ))}
            </div>
            <ul className="analysis-list importer-hints">
              {selectedOption.hints.map((hint) => (
                <li key={hint}>{hint}</li>
              ))}
            </ul>
          </div>
        ) : null}

        <label className="upload-dropzone">
          <span>{file ? file.name : "选择 CSV / Excel 文件"}</span>
          <small>{selectedOption?.formats.join(" / ")}</small>
          <input
            type="file"
            accept={selectedOption?.formats.join(",")}
            onChange={(event) => setFile(event.target.files?.[0] ?? null)}
          />
        </label>

        <button type="submit" className="upload-submit-button" disabled={submitting}>
          {submitting ? "正在导入..." : "开始更新数据"}
        </button>

        {error ? <p className="upload-feedback is-error">{error}</p> : null}

        {result ? (
          <div className="upload-result-card">
            <div className="upload-result-head">
              <h3>任务已创建</h3>
              <span className="mini-pill">{result.importerKey ?? "后台任务"}</span>
            </div>
            <p>{result.title}</p>
            <p>任务 ID：{result.importTaskId}</p>
            <p>状态：{result.taskStatus === "running" ? "处理中" : result.taskStatus}</p>
          </div>
        ) : null}
      </form>
    </section>
  );
}
