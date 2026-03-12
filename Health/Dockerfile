FROM node:22-slim

WORKDIR /app

# Copy standalone build output
COPY .next/standalone/ ./
COPY .next/static/ .next/static/
COPY migrations/ migrations/

# Create data directory for SQLite
RUN mkdir -p data

# Environment defaults (override at runtime via -e or .env file)
ENV NODE_ENV=production
ENV PORT=3000
ENV HOSTNAME=0.0.0.0

EXPOSE 3000

CMD ["node", "server.js"]
