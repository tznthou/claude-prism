# Traffic Stats

Auto-collected daily by GitHub Actions. One JSON record per line per day.

Query with: `cat traffic.jsonl | jq -s '.[] | select(.date >= "2026-03-01")'`
