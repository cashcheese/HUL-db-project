"""
train.py
--------
Trains one Prophet model per finished good.
Evaluates on a held-out test set and prints MAE, RMSE, MAPE.
Saves trained models to forecasting/models/<product_id>.pkl

Run once:  python forecasting/train.py
Re-run any time you add new data.
"""

import os
import joblib
import numpy as np
import pandas as pd
from prophet import Prophet
from sklearn.metrics import mean_absolute_error, mean_squared_error

from forecasting.data_prep import load_training_data, PRODUCT_META

MODELS_DIR = os.path.join(os.path.dirname(__file__), "models")
os.makedirs(MODELS_DIR, exist_ok=True)

# ── Train/test split ───────────────────────────────────────────────────────────
# Train: Jan 2023 – Sep 2024  (21 months)
# Test : Oct 2024 – Jun 2025  (last 9 months — includes peak season, hardest test)
TRAIN_CUTOFF = "2024-12-31"


def compute_metrics(actual: pd.Series, predicted: pd.Series) -> dict:
    """Compute MAE, RMSE, MAPE. Returns a dict."""
    actual = actual.values
    predicted = predicted.values

    mae = mean_absolute_error(actual, predicted)
    rmse = np.sqrt(mean_squared_error(actual, predicted))

    # MAPE — avoid division by zero for any zero-demand months
    mask = actual != 0
    mape = np.mean(
        np.abs((actual[mask] - predicted[mask]) / actual[mask])) * 100

    return {"MAE": round(mae, 1), "RMSE": round(rmse, 1), "MAPE": round(mape, 1)}


def train_model(df: pd.DataFrame) -> Prophet:
    """
    Fit a Prophet model on the given DataFrame.
    df must have columns [ds, y].
    """
    model = Prophet(
        yearly_seasonality=True,   # Our key signal — annual FMCG cycles
        weekly_seasonality=False,  # Data is monthly aggregated — no weekly signal
        daily_seasonality=False,   # Same reason
        seasonality_mode="multiplicative",  # Better for FMCG: peaks are proportional
                                            # to trend level, not additive fixed bumps
        changepoint_prior_scale=0.15,       # Conservative — prevents overfitting
                                            # on 30 data points
        interval_width=0.80                 # 80% confidence interval on forecasts
    )
    model.fit(df)
    return model


def evaluate(model: Prophet, test_df: pd.DataFrame) -> dict:
    """
    Run model.predict on test period dates and compare to actuals.
    Returns metrics dict.
    """
    # Generate enough periods to cover the entire test set
    # len(test_df) + 2 gives a small buffer to ensure all test dates are included
    future = model.make_future_dataframe(periods=len(test_df) + 2, freq="MS")
    forecast = model.predict(future)

    # Merge forecast with test actuals on ds
    forecast["ds"] = pd.to_datetime(forecast["ds"])
    merged = test_df.merge(forecast[["ds", "yhat"]], on="ds", how="inner")

    if merged.empty:
        print("  ⚠️  No overlap between test set and forecast — check dates.")
        return {}

    return compute_metrics(merged["y"], merged["yhat"])


def run_training():
    print("=" * 55)
    print("  HUL Demand Forecasting — Training Pipeline")
    print("=" * 55)

    all_data = load_training_data()

    for product_id, df in all_data.items():
        name = PRODUCT_META[product_id]["name"]
        print(f"\n▶  Product {product_id} — {name}")
        print(f"   Total months of data: {len(df)}")

        # ── Split ──────────────────────────────────────────────────────────────
        train_df = df[df["ds"] <= TRAIN_CUTOFF].copy()
        test_df = df[df["ds"] > TRAIN_CUTOFF].copy()

        print(
            f"   Train: {len(train_df)} months  |  Test: {len(test_df)} months")

        if len(train_df) < 12:
            print("   ⚠️  Not enough training data (< 12 months). Skipping.")
            continue

        # ── Train ──────────────────────────────────────────────────────────────
        print("   Training Prophet model...", end=" ", flush=True)
        model = train_model(train_df)
        print("done.")

        # ── Evaluate ───────────────────────────────────────────────────────────
        if len(test_df) > 0:
            metrics = evaluate(model, test_df)
            print(
                f"   Evaluation metrics on test set ({len(test_df)} months):")
            print(f"     MAE  : {metrics.get('MAE',  'N/A')} units/month")
            print(f"     RMSE : {metrics.get('RMSE', 'N/A')} units/month")
            print(f"     MAPE : {metrics.get('MAPE', 'N/A')}%")

            # Context: is MAPE good?
            mape = metrics.get("MAPE", 999)
            if mape < 15:
                verdict = "✅ Excellent (< 15% — better than industry standard)"
            elif mape < 25:
                verdict = "✅ Good (15–25% — within industry standard for FMCG)"
            elif mape < 40:
                verdict = "⚠️  Acceptable (25–40% — usable but room to improve)"
            else:
                verdict = "❌ Poor (> 40% — check data quality)"
            print(f"     Verdict: {verdict}")
        else:
            print("   No test data available — skipping evaluation.")
            metrics = {}

        # ── Retrain on FULL data before saving ────────────────────────────────
        # We evaluate on train/test split, but save the model trained on
        # all available data so forecasts use the most recent patterns.
        print("   Retraining on full dataset before saving...", end=" ", flush=True)
        final_model = train_model(df)
        print("done.")

        # ── Save ───────────────────────────────────────────────────────────────
        model_path = os.path.join(MODELS_DIR, f"{product_id}.pkl")
        joblib.dump({
            "model":      final_model,
            "product_id": product_id,
            "name":       name,
            "metrics":    metrics,
            "trained_on": str(df["ds"].max().date()),
            "n_months":   len(df)
        }, model_path)
        print(f"   Model saved → {model_path}")

    print("\n" + "=" * 55)
    print("  Training complete. Models saved to forecasting/models/")
    print("=" * 55)


if __name__ == "__main__":
    run_training()
