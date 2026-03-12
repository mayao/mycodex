const desensitizationRules = [
  {
    title: "身份与来源替换",
    description: "姓名、医院、供应商、报告标题全部改成通用样例，不保留任何可追溯个人身份的信息。"
  },
  {
    title: "时间轴做平移",
    description: "日期统一做了平移和重写，只保留趋势关系与节奏，不映射真实就诊和检测时间。"
  },
  {
    title: "展示边界收紧",
    description: "分享页不暴露导入入口、原始报告详情和真实快照跳转，只保留产品结构与交互表达。"
  }
];

const shareUseCases = ["产品方案评审", "跨团队介绍", "能力演示", "投屏讲解"];

export function ShareReadyPanel() {
  return (
    <section className="share-ready-panel">
      <div className="share-ready-copy">
        <p className="panel-kicker">Share Mode</p>
        <h2>内部分享脱敏视图</h2>
        <p className="panel-description">
          当前页面所有内容都用于演示产品表达方式，数据为 mock 或做过结构性调整，不对应任何个人真实健康记录。
        </p>
      </div>

      <div className="share-ready-grid">
        {desensitizationRules.map((rule) => (
          <article key={rule.title} className="share-ready-card">
            <span>{rule.title}</span>
            <p>{rule.description}</p>
          </article>
        ))}
      </div>

      <div className="share-ready-tag-row" aria-label="适用场景">
        {shareUseCases.map((item) => (
          <span key={item} className="share-ready-tag">
            {item}
          </span>
        ))}
      </div>
    </section>
  );
}
