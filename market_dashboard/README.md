# Personal Portfolio Workbench

## Features
- Reads your real broker statements from Tiger, Interactive Brokers, Futu, and Longbridge.
- Aggregates true holdings, recent trades, financing pressure, and derivative / FCN exposure across accounts.
- Shows portfolio views by broker, market, and investment theme.
- Adds a deeper Chinese strategy brief oriented around real position sizing, concentration, leverage, and execution discipline.
- Uses file-signature caching, so replacing a statement file and clicking refresh is enough to rebuild the dashboard.
- Provides an offline `--check` path that validates the local portfolio payload without depending on external market APIs.

## Run
```bash
cd market_dashboard
python3 app.py
```

Open: `http://127.0.0.1:8008`

## Validate
```bash
cd market_dashboard
python3 app.py --check
```

## Update workflow
1. Keep `statement_sources.py` pointing at the latest statement files.
2. Replace the PDFs / documents when you have a new cycle.
3. Reload the page and click `强制刷新结单快照`.
