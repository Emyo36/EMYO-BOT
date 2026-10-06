"""Télécharge les bougies XAUUSD 1 min (BID) de Dukascopy et les agrège en 5 min.

Nécessite l'accès réseau à datafeed.dukascopy.com.

Usage :
    python backtest/fetch_dukascopy.py 2024-01-01 2026-09-30 data/xauusd_m5.csv
    python backtest/opr_rsi.py data/xauusd_m5.csv --data-tz UTC
"""

from __future__ import annotations

import lzma
import struct
import sys
import time
import urllib.error
import urllib.request
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path

import pandas as pd

URL = "https://datafeed.dukascopy.com/datafeed/{sym}/{y}/{m:02d}/{d:02d}/BID_candles_min_1.bi5"
RECORD = struct.Struct(">IIIIIf")   # secondes depuis 00:00 UTC, open, close, low, high, volume
SCALE = 1000                         # XAUUSD : prix stockés en millièmes


def fetch_day(day: pd.Timestamp, sym: str = "XAUUSD") -> pd.DataFrame | None:
    url = URL.format(sym=sym, y=day.year, m=day.month - 1, d=day.day)  # mois indexé à 0
    for attempt in range(4):
        try:
            with urllib.request.urlopen(url, timeout=30) as r:
                raw = r.read()
            break
        except urllib.error.HTTPError as e:
            if e.code == 404:
                return None
            time.sleep(2 ** attempt)
        except urllib.error.URLError:
            time.sleep(2 ** attempt)
    else:
        raise RuntimeError(f"échec du téléchargement : {url}")
    if not raw:
        return None
    data = lzma.decompress(raw)
    rows = [RECORD.unpack_from(data, i) for i in range(0, len(data), RECORD.size)]
    df = pd.DataFrame(rows, columns=["sec", "open", "close", "low", "high", "volume"])
    df = df[df.volume > 0]                           # minutes sans cotation (week-end)
    if df.empty:
        return None
    df.index = day.tz_localize("UTC") + pd.to_timedelta(df.pop("sec"), unit="s")
    df[["open", "high", "low", "close"]] /= SCALE
    return df[["open", "high", "low", "close"]]


def main() -> None:
    start, end, out = sys.argv[1], sys.argv[2], Path(sys.argv[3])
    days = [d for d in pd.date_range(start, end, freq="D") if d.dayofweek < 5]
    with ThreadPoolExecutor(8) as pool:
        parts = [p for p in pool.map(fetch_day, days) if p is not None]
    m1 = pd.concat(parts).sort_index()
    if not 300 < m1.close.median() < 20_000:
        raise SystemExit(f"prix incohérents (médiane {m1.close.median()}), échelle à vérifier")
    m5 = m1.resample("5min").agg({"open": "first", "high": "max", "low": "min", "close": "last"}).dropna()
    m5.index = m5.index.tz_localize(None)
    m5.index.name = "time"
    out.parent.mkdir(parents=True, exist_ok=True)
    m5.to_csv(out)
    print(f"{len(m5)} bougies 5 min ({m5.index[0]} -> {m5.index[-1]}) -> {out}")


if __name__ == "__main__":
    main()
