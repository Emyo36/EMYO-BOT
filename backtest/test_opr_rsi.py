"""Tests du moteur : python -m pytest backtest -q  (ou python backtest/test_opr_rsi.py)"""

import os
import sys

import numpy as np
import pandas as pd

sys.path.insert(0, os.path.dirname(__file__))
from opr_rsi import Params, run, stats  # noqa: E402

TZ = "Etc/GMT-2"


def make_day(rows, start="2026-06-01 19:00"):
    """rows = liste de (open, high, low, close) en bougies 5 min, heure UTC+2."""
    idx = pd.date_range(start, periods=len(rows), freq="5min", tz=TZ)
    return pd.DataFrame(rows, columns=["open", "high", "low", "close"], index=idx)


def flat(n, px=4000.0):
    return [(px, px + 0.5, px - 0.5, px)] * n


def scenario(after):
    # 19:00-20:10 plat (14 bougies), OPR 20:10-20:30 range 3998-4002 (400 pips),
    # 20:30-20:40 dans le range, puis `after` à partir de 20:40.
    opr = [(4000, 4002, 3998, 4000)] * 4
    return make_day(flat(14) + opr + flat(2) + after)


P = Params(rsi_mode="off", spread=0.0, sl_mode="opposite")


def test_long_tp():
    # cassure haute à 20:40 (clôture 4003), entrée 4003 à 20:45, SL 3998 => risque 5, TP 4013
    df = scenario([(4000, 4003.5, 3999.5, 4003)] + [(4003, 4014, 4002, 4013)] + flat(10, 4013))
    trades, _ = run(df, P)
    assert len(trades) == 1
    t = trades.iloc[0]
    assert t.dir == "LONG" and t.reason == "TP" and abs(t.r - 2) < 1e-9


def test_short_sl_and_same_bar_ambiguity_counts_sl():
    # cassure basse, puis bougie qui touche SL ET TP : on compte le SL
    df = scenario([(4000, 4000.5, 3996, 3997), (3997, 4003, 3980, 3990)] + flat(5, 3990))
    t = run(df, P)[0].iloc[0]
    assert t.dir == "SHORT" and t.reason == "SL" and abs(t.r + 1) < 1e-9


def test_break_even():
    # long, monte à +1R (BE armé), puis revient sur l'entrée => sortie BE à 0R
    df = scenario([(4000, 4003.5, 3999.5, 4003), (4003, 4008.5, 4003, 4008),
                   (4008, 4008, 4001, 4002)] + flat(5, 4002))
    t = run(df, P)[0].iloc[0]
    assert t.reason == "BE" and abs(t.r) < 1e-9


def test_session_end_exit():
    df = scenario([(4000, 4003.5, 3999.5, 4003)] + flat(30, 4004))
    t = run(df, P)[0].iloc[0]
    assert t.reason == "FIN" and t.exit_time.time() < pd.Timestamp("22:00").time()


def test_opr_filter():
    tiny = make_day(flat(14) + [(4000, 4001, 3999.5, 4000)] * 4 + flat(30))  # 150 pips
    trades, skipped = run(tiny, P)
    assert trades.empty and skipped.skipped.iloc[0] == "opr_size"


def test_spread_costs_money():
    # sans spread TP = 4013 (touché) ; avec spread entrée 4003.3 => TP 4013.6 (raté)
    after = [(4000, 4003.5, 3999.5, 4003)] + [(4003, 4013.2, 4002, 4013)] + flat(10, 4013)
    r0 = run(scenario(after), P)[0].iloc[0].r
    r1 = run(scenario(after), Params(**{**P.__dict__, "spread": 0.3}))[0].iloc[0].r
    assert r1 < r0


def test_random_walk_has_no_edge():
    """Sur un marché aléatoire, la stratégie doit tourner autour de 0R sans frais
    et devenir négative avec le spread : contrôle qu'il n'y a pas de biais
    (regard dans le futur) dans le moteur."""
    rng = np.random.default_rng(7)
    # marche aléatoire à la minute, agrégée en 5 min (mèches cohérentes avec le chemin)
    idx = pd.date_range("2024-01-01", "2025-12-31", freq="1min", tz="UTC")
    idx = idx[(idx.dayofweek < 5) & (idx.hour >= 16) & (idx.hour < 21)]
    px = pd.Series(2000 + np.cumsum(rng.normal(0, 0.4, len(idx))), index=idx)
    df = px.resample("5min").ohlc().dropna()
    df["open"] = df.close.shift(1).fillna(df.open)       # pas de gap entre bougies
    df["high"] = df[["open", "high"]].max(axis=1)
    df["low"] = df[["open", "low"]].min(axis=1)
    base = Params(sl_mode="candle")
    r_free = run(df, Params(**{**base.__dict__, "spread": 0.0}))[0].r.mean()
    r_cost = run(df, Params(**{**base.__dict__, "spread": 0.3}))[0].r.mean()
    assert abs(r_free) < 0.2, r_free   # ~0 aux erreurs statistiques près
    assert r_cost < r_free


if __name__ == "__main__":
    for name, fn in list(globals().items()):
        if name.startswith("test_"):
            fn()
            print("ok", name)
