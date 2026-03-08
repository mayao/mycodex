import type { ReactNode } from "react";

interface SectionCardProps {
  title: string;
  eyebrow?: string;
  description?: string;
  children: ReactNode;
}

export function SectionCard({
  title,
  eyebrow,
  description,
  children
}: SectionCardProps) {
  return (
    <section className="card">
      {eyebrow ? <p className="eyebrow">{eyebrow}</p> : null}
      <div className="section-header">
        <h2>{title}</h2>
        {description ? <p>{description}</p> : null}
      </div>
      {children}
    </section>
  );
}
