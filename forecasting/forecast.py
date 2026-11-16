"""
forecast.py
-----------
Called by Flask routes to serve forecast data.
Loads saved .pkl models and returns JSON-serialisable dicts.

Flask usage:
    from forecasting.forecast import get_forecast, get_suggested_po, get_all_forecasts
"""

import os
import joblib
import pandas as pd
from datetime import date

from forecasting.data_prep import load_training_data, get_current_inventory, PRODUCT_META

MODELS_DIR = os.path.join(os.path.dirname(__file__), "models")

PRODUCT_IDS = [2001, 2002, 2003]


# ── Model loader (cached in memory after first load) ──────────────────────────
_model_cache = {}

def _load_model(product_id: int) -> dict:
    """Load model from disk. Caches in _model_cache after first call."""
    if product_id not in _model_cache:
        model_path = os.path.join(MODELS_DIR, f"{product_id}.pkl")
        if not os.path.exists(model_path):
            raise FileNotFoundError(
                f"Model for product {product_id} not found. "
                f"Run: python forecasting/train.py"
            )
        _model_cache[product_id] = joblib.load(model_path)
    return _model_cache[product_id]


# ── Core forecast function ─────────────────────────────────────────────────────
def get_forecast(product_id: int, horizon_days: int = 90) -> dict:
    """
    Returns forecast for a single product.

    Args:
        product_id  : one of 2001, 2002, 2003
        horizon_days: number of days ahead to forecast (default 90 = ~3 months)

    Returns dict with:
        product_id, product_name, unit,
        historical: [{ds, y}],          ← actual past values
        forecast:   [{ds, yhat, lower, upper}]  ← predicted future values
        metrics:    {MAE, RMSE, MAPE}   ← from training evaluation
        trained_on: str date
    """
    bundle = _load_model(product_id)
    model  = bundle["model"]
    meta   = PRODUCT_META[product_id]

    # Convert horizon_days to approximate months
    horizon_months = max(1, round(horizon_days / 30))

    # Build future dataframe — Prophet needs this to generate predictions
    # freq="MS" = Month Start — matches our monthly training data
    future   = model.make_future_dataframe(periods=horizon_months, freq="MS")
    forecast = model.predict(future)

    # ── Historical actuals ────────────────────────────────────────────────────
    all_data    = load_training_data()
    history_df  = all_data.get(product_id, pd.DataFrame())

    historical = [
        {
            "ds": row["ds"].strftime("%Y-%m-%d"),
            "y":  round(float(row["y"]), 0)
        }
        for _, row in history_df.iterrows()
    ]

    # ── Forecast rows (future only — after last training date) ────────────────
    last_training_date = history_df["ds"].max() if not history_df.empty else pd.Timestamp("2020-01-01")

    forecast_rows = []
    for _, row in forecast.iterrows():
        if row["ds"] > last_training_date:
            forecast_rows.append({
                "ds"   : row["ds"].strftime("%Y-%m-%d"),
                "yhat" : max(0, round(float(row["yhat"]),  0)),   # floor at 0
                "lower": max(0, round(float(row["yhat_lower"]), 0)),
                "upper": max(0, round(float(row["yhat_upper"]), 0)),
            })

    return {
        "product_id"  : product_id,
        "product_name": meta["name"],
        "unit"        : meta["unit"],
        "historical"  : historical,
        "forecast"    : forecast_rows,
        "metrics"     : bundle.get("metrics", {}),
        "trained_on"  : bundle.get("trained_on", "unknown"),
        "n_months"    : bundle.get("n_months", 0),
    }


# ── Suggested PO quantity ──────────────────────────────────────────────────────
def get_suggested_po(product_id: int, horizon_days: int = 30) -> dict:
    """
    Calculates suggested purchase order quantity.

    Logic:
        suggested_qty = forecasted_demand_next_N_days - current_inventory
        If suggested_qty <= 0, no PO needed.

    Returns dict with:
        product_id, product_name,
        forecasted_demand (next horizon_days),
        current_inventory,
        suggested_po_qty,
        recommendation (str)
    """
    forecast_data    = get_forecast(product_id, horizon_days)
    current_inventory = get_current_inventory()
    current_stock    = current_inventory.get(product_id, 0)

    # Sum predicted demand over the forecast horizon
    forecasted_demand = sum(row["yhat"] for row in forecast_data["forecast"])
    forecasted_demand = round(forecasted_demand)

    suggested_qty = max(0, forecasted_demand - current_stock)

    if suggested_qty == 0:
        recommendation = f"✅ Current stock ({current_stock} units) covers forecasted demand ({forecasted_demand} units). No PO needed."
    else:
        recommendation = (
            f"⚠️ Forecasted demand: {forecasted_demand} units over next {horizon_days} days. "
            f"Current stock: {current_stock} units. "
            f"Suggested PO quantity: {suggested_qty} units."
        )

    return {
        "product_id"       : product_id,
        "product_name"     : forecast_data["product_name"],
        "unit"             : forecast_data["unit"],
        "horizon_days"     : horizon_days,
        "forecasted_demand": forecasted_demand,
        "current_inventory": current_stock,
        "suggested_po_qty" : suggested_qty,
        "recommendation"   : recommendation,
    }


# ── All products summary ───────────────────────────────────────────────────────
def get_all_forecasts(horizon_days: int = 90) -> list:
    """
    Returns forecast summary for all three products.
    Used by the dashboard overview tab.
    """
    results = []
    for pid in PRODUCT_IDS:
        try:
            f = get_forecast(pid, horizon_days)
            po = get_suggested_po(pid, 30)   # always 30-day PO suggestion
            results.append({
                "product_id"   : pid,
                "product_name" : f["product_name"],
                "unit"         : f["unit"],
                "metrics"      : f["metrics"],
                "next_3_months": f["forecast"][:3],   # first 3 forecast months
                "suggested_po" : po["suggested_po_qty"],
                "recommendation": po["recommendation"],
            })
        except FileNotFoundError as e:
            results.append({"product_id": pid, "error": str(e)})

    return results


if __name__ == "__main__":
    # Quick test — run directly to verify models load and forecast runs
    print("Testing forecast module...\n")
    for pid in PRODUCT_IDS:
        try:
            result = get_forecast(pid, horizon_days=90)
            print(f"Product {pid} — {result['product_name']}")
            print(f"  Trained on : {result['trained_on']} ({result['n_months']} months)")
            print(f"  Metrics    : {result['metrics']}")
            print(f"  Forecast   : {len(result['forecast'])} months ahead")
            if result["forecast"]:
                next_month = result["forecast"][0]
                print(f"  Next month : {next_month['ds']} → {next_month['yhat']} units "
                      f"(range: {next_month['lower']}–{next_month['upper']})")

            po = get_suggested_po(pid, 30)
            print(f"  PO suggest : {po['recommendation']}\n")
        except FileNotFoundError as e:
            print(f"  ❌ {e}\n")
