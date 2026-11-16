"""
tools.py
--------
Stored procedures wrapped as LangChain tools.
call_proc defined independently here to avoid circular imports with Flask.
"""

import json
import sys
import os
from decimal import Decimal
import mysql.connector
from dotenv import load_dotenv
from langchain_core.tools import tool

load_dotenv(os.path.join(os.path.dirname(__file__), '..', '.env'))

PROJECT_ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), '..'))
if PROJECT_ROOT not in sys.path:
    sys.path.insert(0, PROJECT_ROOT)


def _get_connection():
    return mysql.connector.connect(
        host=os.getenv("DB_HOST", "localhost"),
        user=os.getenv("DB_USER"),
        password=os.getenv("DB_PASSWORD"),
        database=os.getenv("DB_NAME", "hul_db")
    )


def _call_proc(proc_name, args=[]):
    conn = _get_connection()
    cursor = conn.cursor(dictionary=True)
    try:
        cursor.callproc(proc_name, args)
        results = []
        for result in cursor.stored_results():
            results = result.fetchall()
        for row in results:
            for key, value in row.items():
                if isinstance(value, Decimal):
                    row[key] = float(value)
        conn.commit()
        return results
    except mysql.connector.Error as err:
        conn.rollback()
        raise Exception(err.msg)
    finally:
        cursor.close()
        conn.close()


@tool
def get_pending_orders(query: str) -> str:
    """Get all pending and blocked distribution orders with live stock status.
    Use when the user asks about pending orders, blocked orders,
    orders waiting to be processed, or the order queue."""
    try:
        results = _call_proc('sp_GetPendingOrders')
        if not results:
            return "No pending orders found."
        return json.dumps(results, default=str)
    except Exception as e:
        return f"Error: {str(e)}"


@tool
def get_inventory_snapshot(query: str) -> str:
    """Get current stock levels for all finished goods in the warehouse.
    Use when the user asks about inventory, stock levels, or warehouse stock."""
    try:
        results = _call_proc('sp_GetInventorySnapshot')
        if not results:
            return "No inventory data found."
        return json.dumps(results, default=str)
    except Exception as e:
        return f"Error: {str(e)}"


@tool
def get_overdue_customers(query: str) -> str:
    """Get customers with invoices overdue by more than 30 days.
    Use when the user asks about overdue payments or customers who have not paid."""
    try:
        results = _call_proc('sp_GetCustomersWithOverdueInvoices')
        if not results:
            return "No overdue customers found."
        return json.dumps(results, default=str)
    except Exception as e:
        return f"Error: {str(e)}"


@tool
def get_unpaid_invoices(query: str) -> str:
    """Get all unpaid and partially paid invoices.
    Use when the user asks about unpaid invoices or outstanding payments."""
    try:
        results = _call_proc('sp_GetUnpaidInvoices')
        if not results:
            return "No unpaid invoices found."
        return json.dumps(results, default=str)
    except Exception as e:
        return f"Error: {str(e)}"


@tool
def get_purchase_orders(query: str) -> str:
    """Get all purchase orders with their status.
    Use when the user asks about purchase orders, procurement, or supplier orders."""
    try:
        results = _call_proc('sp_GetAllPurchaseOrders')
        if not results:
            return "No purchase orders found."
        return json.dumps(results, default=str)
    except Exception as e:
        return f"Error: {str(e)}"


@tool
def get_order_triage_details(dist_id: int) -> str:
    """Get detailed breakdown for a specific distribution order including stock shortfall.
    Use when the user asks for details about a specific order ID or why an order is blocked.
    Input: dist_id as integer."""
    try:
        results = _call_proc('sp_GetOrderDetailsForTriage', [dist_id])
        if not results:
            return f"No details found for Order {dist_id}."
        return json.dumps(results, default=str)
    except Exception as e:
        return f"Error: {str(e)}"


@tool
def get_demand_forecast(product_id: int) -> str:
    """Get demand forecast and suggested purchase order quantity for a finished good.
    Use when the user asks about forecast, predicted demand, how much to order,
    or suggested PO quantity for any product.
    IMPORTANT: Input must be an integer product_id only.
    Use 2001 for Bru Coffee, 2002 for Knorr Soup, 2003 for Surf Excel.
    Example input: 2001"""
    try:
        product_id = int(str(product_id).strip())
        from forecasting.forecast import get_suggested_po
        result = get_suggested_po(product_id, horizon_days=30)
        return (
            f"Product: {result['product_name']}\n"
            f"Forecasted demand (next 30 days): {result['forecasted_demand']} units\n"
            f"Current inventory: {result['current_inventory']} units\n"
            f"Suggested PO quantity: {result['suggested_po_qty']} units\n"
            f"Recommendation: {result['recommendation']}"
        )
    except Exception as e:
        return f"Error: {str(e)}"


@tool
def allocate_stock_for_order(dist_id: int) -> str:
    """Allocate stock for a distribution order that is ready to fulfill.
    Deducts inventory, updates order status, and creates a shipment record.
    Only use when the user explicitly confirms they want to allocate.
    Input: dist_id as integer."""
    try:
        _call_proc('sp_AllocateStockForOrder', [dist_id])
        return f"Order {dist_id} successfully allocated. Stock deducted and shipment created."
    except Exception as e:
        return f"Allocation failed for Order {dist_id}: {str(e)}"


@tool
def record_payment(invoice_id: int, amount_paid: float, pay_method: str) -> str:
    """Record a payment against an invoice. Invoice status updates automatically.
    Only use when user explicitly provides invoice ID, amount, and payment method.
    Valid pay_method values: NEFT, Bank Transfer, Cheque, UPI, Cash, Card."""
    try:
        _call_proc('sp_RecordPayment', [invoice_id, amount_paid, pay_method])
        return f"Payment of {amount_paid} recorded for Invoice {invoice_id} via {pay_method}."
    except Exception as e:
        return f"Payment failed: {str(e)}"


READ_TOOLS = [
    get_pending_orders,
    get_inventory_snapshot,
    get_overdue_customers,
    get_unpaid_invoices,
    get_purchase_orders,
    get_order_triage_details,
    get_demand_forecast,
]

WRITE_TOOLS = [
    allocate_stock_for_order,
    record_payment,
]

ALL_TOOLS = READ_TOOLS + WRITE_TOOLS