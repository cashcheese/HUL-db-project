"""
data_prep.py
------------
Pulls historical distribution order data from hul_db and returns
a dict of DataFrames shaped for Prophet: {product_id: df with columns [ds, y]}
"""

import pandas as pd
import mysql.connector
from dotenv import load_dotenv
import os

load_dotenv()

# ── DB connection ──────────────────────────────────────────────────────────────


def get_connection():
    return mysql.connector.connect(
        host=os.getenv("DB_HOST", "localhost"),
        user=os.getenv("DB_USER"),
        password=os.getenv("DB_PASSWORD"),
        database=os.getenv("DB_NAME", "hul_db")
    )


# ── The core query ─────────────────────────────────────────────────────────────
FORECAST_QUERY = """
    SELECT
        p.Product_ID,
        p.Name                              AS Product_Name,
        DATE_FORMAT(do.Order_Date, '%Y-%m-01') AS ds,
        SUM(dol.Qty_Ordered)                AS y
    FROM DistributionOrderLine dol
    JOIN DistributionOrder  do  ON dol.Dist_ID      = do.Dist_ID
    JOIN Inventory          i   ON dol.Inventory_ID = i.Inventory_ID
    JOIN Batch              b   ON i.Batch_ID        = b.Batch_ID
    JOIN Product            p   ON b.Product_ID      = p.Product_ID
    WHERE do.Status     = 'Delivered'
      AND p.Product_ID IN (2001, 2002, 2003)
    GROUP BY p.Product_ID,
             p.Name,
             DATE_FORMAT(do.Order_Date, '%Y-%m-01')
    ORDER BY p.Product_ID, ds;
"""

# ── Product metadata ───────────────────────────────────────────────────────────
PRODUCT_META = {
    2001: {"name": "Bru Instant Coffee 50g Jar",         "unit": "jar",    "inventory_id": 5001},
    2002: {"name": "Knorr Classic Thick Tomato Soup 50g", "unit": "packet", "inventory_id": 5002},
    2003: {"name": "Surf Excel Matic Top Load 1kg",       "unit": "box",   "inventory_id": 5003},
}

# ── Main function ──────────────────────────────────────────────────────────────


def load_training_data() -> dict:
    """
    Returns a dict keyed by Product_ID.
    Each value is a DataFrame with columns [ds (datetime), y (float)].
    """
    import warnings
    conn = get_connection()
    with warnings.catch_warnings():
        # suppress the SQLAlchemy warning
        warnings.simplefilter("ignore")
        df_all = pd.read_sql(FORECAST_QUERY, conn)
    conn.close()

    df_all["ds"] = pd.to_datetime(df_all["ds"], format="%Y-%m-%d")
    df_all["y"] = df_all["y"].astype(float)

    product_data = {}
    for pid in df_all["Product_ID"].unique():
        df_product = (
            df_all[df_all["Product_ID"] == pid][["ds", "y"]]
            .sort_values("ds")
            .reset_index(drop=True)
        )
        product_data[int(pid)] = df_product

    return product_data


def get_current_inventory() -> dict:
    """
    Returns current Inventory.Quantity for each finished good.
    {product_id: current_quantity}
    """
    conn = get_connection()
    cursor = conn.cursor(dictionary=True)
    cursor.execute("""
        SELECT b.Product_ID, i.Quantity
        FROM Inventory i
        JOIN Batch b ON i.Batch_ID = b.Batch_ID
        WHERE b.Product_ID IN (2001, 2002, 2003)
    """)
    rows = cursor.fetchall()
    conn.close()
    return {row["Product_ID"]: row["Quantity"] for row in rows}


if __name__ == "__main__":
    data = load_training_data()
    for pid, df in data.items():
        print(f"\nProduct {pid} — {PRODUCT_META[pid]['name']}")
        print(f"  Rows      : {len(df)}")
        print(
            f"  Date range: {df['ds'].min().date()} → {df['ds'].max().date()}")
        print(f"  y range   : {int(df['y'].min())} → {int(df['y'].max())}")
        print(df.tail(3).to_string(index=False))
