# Personal Portfolio Workbench

## Features
- Reads your real broker statements from Tiger, Interactive Brokers, Futu, and Longbridge.
- Aggregates true holdings, recent trades, financing pressure, and derivative / FCN exposure across accounts.
- Shows portfolio views by broker, market, and investment theme.
- Adds a deeper Chinese strategy brief oriented around real position sizing, concentration, leverage, and execution discipline.
- Adds a more detailed single-stock fundamental layer covering business model, earnings drivers, valuation anchors, catalysts, and risk points.
- Supports uploading a fresh statement from the UI to replace a monitored account source without editing Python config.
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
1. Open the page and use `上传新结单` to replace the PDF for a specific account.
2. The dashboard writes the uploaded file into `market_dashboard/uploads/` and immediately rebuilds the statement cache.
3. Keep using `刷新行情与宏观` when you want to pull the latest price, trend, and macro summaries from external APIs and news search.
