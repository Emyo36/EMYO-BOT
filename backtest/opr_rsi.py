"""Backtest de la stratégie XAUUSD 5 min « OPR + RSI » (live TikTok HORIIZON).

Règles affichées pendant le live :
    OPR      : 20h10 - 20h30 (UTC+2)
    Début    : 20h40   Fin : 22h00
    RSI      : 8   surachat 80   survente 25
    OPR min  : 300 pips   OPR max : 1900 pips   (1 pip = 0.01 $)
    RR       : 2   BE : 1R

Ce qui n'est PAS précisé dans le live est rendu paramétrable (et le défaut est
indiqué) : déclencheur d'entrée, rôle du RSI, placement du stop.

Hypothèses prudentes :
    - entrée à l'ouverture de la bougie qui suit la clôture de cassure ;
    - si SL et TP sont touchés dans la même bougie, on compte le SL ;
    - le passage à BE n'est actif qu'à partir de la bougie suivante ;
    - les prix OHLC sont des prix BID, l'achat se fait au ASK (= BID + spread).

Usage :
    python backtest/opr_rsi.py data/xauusd_m5.csv --data-tz UTC
    python backtest/opr_rsi.py data.csv --spread 0.30 --sl-mode candle --risk 1
"""

from __future__ import annotations

import argparse
from dataclasses import dataclass, field
from datetime import time

import numpy as np
import pandas as pd

PIP = 0.01            # 1 pip XAUUSD = 0.01 $
OZ_PER_LOT = 100      # 1 lot = 100 onces


@dataclass
class Params:
    tz: str = "Etc/GMT-2"           # UTC+2 fixe ; "Europe/Paris" pour suivre l'heure d'été
    opr_start: time = time(20, 10)
    opr_end: time = time(20, 30)
    entry_start: time = time(20, 40)
    session_end: time = time(22, 0)
    rsi_len: int = 8
    overbought: float = 80
    oversold: float = 25
    rsi_mode: str = "block"         # block | trend | off
    opr_min_pips: float = 300
    opr_max_pips: float = 1900
    rr: float = 2.0
    be_at_r: float = 1.0            # 0 = pas de BE
    sl_mode: str = "candle"         # candle | opposite | mid | frac
    sl_frac: float = 0.33           # pour sl_mode=frac : SL = frac * taille OPR
    spread: float = 0.30            # en $, payé une fois par trade
    commission: float = 0.0         # $ par lot aller-retour
    risk_pct: float = 1.0
    capital: float = 10_000.0
    extra: dict = field(default_factory=dict)


# --------------------------------------------------------------------------- data

def load_csv(path: str, data_tz: str = "UTC") -> pd.DataFrame:
    """Charge un CSV OHLC (export TradingView, MT4/MT5 ou générique).

    Retourne un DataFrame indexé par l'heure d'OUVERTURE de la bougie (tz-aware),
    colonnes open/high/low/close.
    """
    df = pd.read_csv(path, sep=None, engine="python")
    df.columns = [c.strip().strip("<>").lower() for c in df.columns]

    if "date" in df.columns and "time" in df.columns:          # export MT4/MT5
        ts = pd.to_datetime(df["date"].astype(str) + " " + df["time"].astype(str))
    else:
        col = next(c for c in ("time", "datetime", "timestamp", "date", "gmt time")
                   if c in df.columns)
        raw = df[col]
        if pd.api.types.is_numeric_dtype(raw):                 # epoch (TradingView)
            unit = "ms" if raw.iloc[0] > 1e11 else "s"
            ts = pd.to_datetime(raw, unit=unit, utc=True)
        else:
            ts = pd.to_datetime(raw, utc=False, dayfirst=False)

    ts = pd.DatetimeIndex(ts)
    if ts.tz is None:
        ts = ts.tz_localize(data_tz)
    out = df[["open", "high", "low", "close"]].astype(float)
    out.index = ts
    return out.sort_index().loc[lambda d: ~d.index.duplicated()]


def rsi(close: pd.Series, length: int) -> pd.Series:
    """RSI de Wilder (identique à TradingView)."""
    delta = close.diff()
    gain = delta.clip(lower=0).ewm(alpha=1 / length, adjust=False, min_periods=length).mean()
    loss = (-delta.clip(upper=0)).ewm(alpha=1 / length, adjust=False, min_periods=length).mean()
    rs = gain / loss
    return 100 - 100 / (1 + rs)


# ------------------------------------------------------------------------- engine

def rsi_allows(direction: int, value: float, p: Params) -> bool:
    if p.rsi_mode == "off" or np.isnan(value):
        return p.rsi_mode == "off"
    if p.rsi_mode == "block":       # pas d'achat en surachat, pas de vente en survente
        return value < p.overbought if direction > 0 else value > p.oversold
    if p.rsi_mode == "trend":       # achat seulement si RSI > 50, vente si < 50
        return value > 50 if direction > 0 else value < 50
    raise ValueError(p.rsi_mode)


def stop_price(direction: int, entry: float, hi: float, lo: float,
               bar: pd.Series, p: Params) -> float:
    if p.sl_mode == "candle":
        return bar.low if direction > 0 else bar.high
    if p.sl_mode == "opposite":
        return lo if direction > 0 else hi
    if p.sl_mode == "mid":
        return (hi + lo) / 2
    if p.sl_mode == "frac":
        return entry - direction * p.sl_frac * (hi - lo)
    raise ValueError(p.sl_mode)


def simulate_day(day: pd.DataFrame, p: Params) -> dict | None:
    """Simule au plus un trade sur une journée (bougies en heure locale p.tz)."""
    t = day.index.time
    opr = day[(t >= p.opr_start) & (t < p.opr_end)]
    if len(opr) < 4:                                   # 20h10-20h30 = 4 bougies
        return None
    hi, lo = opr.high.max(), opr.low.min()
    size_pips = (hi - lo) / PIP
    if not (p.opr_min_pips <= size_pips <= p.opr_max_pips):
        return {"skipped": "opr_size", "opr_pips": size_pips}

    window = day[(t >= p.entry_start) & (t < p.session_end)]
    for i in range(len(window) - 1):
        bar = window.iloc[i]
        direction = 1 if bar.close > hi else -1 if bar.close < lo else 0
        if direction == 0 or not rsi_allows(direction, bar.rsi, p):
            continue

        nxt = window.iloc[i + 1]
        # BID -> ASK : on paie le spread à l'achat (long) ou au rachat (short)
        entry = nxt.open + (p.spread if direction > 0 else 0.0)
        sl = stop_price(direction, entry, hi, lo, bar, p)
        risk = (entry - sl) * direction
        if risk <= 0:
            continue
        tp = entry + direction * p.rr * risk
        return manage_trade(window.iloc[i + 1:], direction, entry, sl, tp, risk,
                            size_pips, bar, p)
    return {"skipped": "no_signal", "opr_pips": size_pips}


def manage_trade(bars: pd.DataFrame, d: int, entry: float, sl: float, tp: float,
                 risk: float, opr_pips: float, signal_bar: pd.Series, p: Params) -> dict:
    # Pour un short on sort au ASK : on décale les extrêmes BID du spread.
    adj = 0.0 if d > 0 else p.spread
    be_armed = False
    for ts, b in bars.iterrows():
        high, low, close = b.high + adj, b.low + adj, b.close + adj
        adverse, favor = (low, high) if d > 0 else (high, low)
        if (adverse - sl) * d <= 0:
            exit_px, reason = sl, "BE" if be_armed else "SL"
        elif (favor - tp) * d >= 0:
            exit_px, reason = tp, "TP"
        else:
            if p.be_at_r and not be_armed and (favor - entry) * d >= p.be_at_r * risk:
                sl, be_armed = entry, True          # actif dès la bougie suivante
            continue
        break
    else:
        exit_px, reason = close, "FIN"             # clôture 22h00
    return {
        "entry_time": bars.index[0], "exit_time": ts, "dir": "LONG" if d > 0 else "SHORT",
        "entry": entry, "exit": exit_px, "sl_pips": risk / PIP, "opr_pips": opr_pips,
        "rsi": signal_bar.rsi, "reason": reason, "r": (exit_px - entry) * d / risk,
    }


def run(df: pd.DataFrame, p: Params) -> tuple[pd.DataFrame, pd.DataFrame]:
    df = df.tz_convert(p.tz).copy()
    df["rsi"] = rsi(df.close, p.rsi_len)
    trades, skipped = [], []
    for day, g in df.groupby(df.index.date):
        res = simulate_day(g, p)
        if res is None:
            continue
        (skipped if "skipped" in res else trades).append(res | {"day": day})
    trades = pd.DataFrame(trades)
    if not trades.empty:
        trades = size_positions(trades, p)
    return trades, pd.DataFrame(skipped)


def size_positions(trades: pd.DataFrame, p: Params) -> pd.DataFrame:
    """Risque fixe en % du capital, capitalisé ; lot arrondi à 0.01."""
    equity, rows = p.capital, []
    for t in trades.itertuples():
        risk_usd = equity * p.risk_pct / 100
        lot = max(0.01, np.floor(risk_usd / (t.sl_pips * PIP * OZ_PER_LOT) * 100) / 100)
        pnl = (t.exit - t.entry) * (1 if t.dir == "LONG" else -1) * lot * OZ_PER_LOT
        pnl -= p.commission * lot
        equity += pnl
        rows.append({"lot": lot, "pnl": pnl, "equity": equity})
    return pd.concat([trades, pd.DataFrame(rows, index=trades.index)], axis=1)


# ------------------------------------------------------------------------ rapport

def stats(trades: pd.DataFrame, p: Params) -> dict:
    if trades.empty:
        return {"trades": 0}
    eq = pd.concat([pd.Series([p.capital]), trades.equity])
    dd = (eq / eq.cummax() - 1).min() * 100
    wins, losses = trades.pnl[trades.pnl > 0].sum(), -trades.pnl[trades.pnl < 0].sum()
    return {
        "trades": len(trades),
        "taux_reussite_%": round(float((trades.reason == "TP").mean()) * 100, 1),
        "R_moyen": round(float(trades.r.mean()), 3),
        "profit_factor": round(float(wins / losses), 2) if losses else float("inf"),
        "P/L_%": round(float(trades.equity.iloc[-1] / p.capital - 1) * 100, 1),
        "drawdown_max_%": round(float(dd), 1),
        "sorties": trades.reason.value_counts().to_dict(),
    }


def monthly(trades: pd.DataFrame, p: Params) -> pd.DataFrame:
    t = trades.assign(mois=pd.to_datetime(trades.day).dt.to_period("M"))
    start = t.equity - t.pnl
    g = t.groupby("mois")
    return pd.DataFrame({
        "trades": g.size(),
        "gagnants": g.apply(lambda x: (x.reason == "TP").sum()),
        "R": g.r.sum().round(2),
        "P/L_%": ((g.equity.last() / start.groupby(t.mois).first() - 1) * 100).round(1),
    })


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("csv")
    ap.add_argument("--data-tz", default="UTC", help="fuseau des horodatages du CSV")
    ap.add_argument("--tz", default=Params.tz, help="fuseau des règles (défaut UTC+2 fixe)")
    ap.add_argument("--spread", type=float, default=Params.spread)
    ap.add_argument("--commission", type=float, default=Params.commission)
    ap.add_argument("--sl-mode", default=Params.sl_mode, choices=["candle", "opposite", "mid", "frac"])
    ap.add_argument("--sl-frac", type=float, default=Params.sl_frac)
    ap.add_argument("--rsi-mode", default=Params.rsi_mode, choices=["block", "trend", "off"])
    ap.add_argument("--risk", type=float, default=Params.risk_pct, help="%% du capital risqué par trade")
    ap.add_argument("--rr", type=float, default=Params.rr)
    ap.add_argument("--no-be", action="store_true")
    ap.add_argument("--trades-out", help="exporte la liste des trades en CSV")
    a = ap.parse_args()

    p = Params(tz=a.tz, spread=a.spread, commission=a.commission, sl_mode=a.sl_mode,
               sl_frac=a.sl_frac, rsi_mode=a.rsi_mode, risk_pct=a.risk, rr=a.rr,
               be_at_r=0 if a.no_be else Params.be_at_r)
    df = load_csv(a.csv, a.data_tz)
    print(f"Données : {df.index[0]} -> {df.index[-1]}  ({len(df)} bougies)\n")

    for label, spread in (("SANS spread (comme un replay)", 0.0), (f"AVEC spread {p.spread}$", p.spread)):
        q = Params(**{**p.__dict__, "spread": spread})
        trades, skipped = run(df, q)
        print(f"=== {label} ===")
        for k, v in stats(trades, q).items():
            print(f"  {k:16} {v}")
        if not skipped.empty:
            print(f"  jours ignorés    {skipped.skipped.value_counts().to_dict()}")
        print()
    if not trades.empty:
        print("=== Par mois (avec spread) ===")
        print(monthly(trades, p).to_string())
        if a.trades_out:
            trades.to_csv(a.trades_out, index=False)


if __name__ == "__main__":
    main()
