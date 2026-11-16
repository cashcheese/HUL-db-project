import mysql.connector
from flask import Flask, jsonify, request, session, render_template, redirect, url_for
import os
import sys
from dotenv import load_dotenv
from functools import wraps
import bcrypt
from decimal import Decimal

# ── Path setup must come before any local imports ──────────────────────────────
PROJECT_ROOT = r"C:\5th semester\DBMS lab\mini_proj\HUL-db-project"
if PROJECT_ROOT not in sys.path:
    sys.path.insert(0, PROJECT_ROOT)

# ── Local imports (after path setup) ──────────────────────────────────────────
from forecasting.forecast import get_forecast, get_suggested_po, get_all_forecasts
from chatbot.agent import chat as agent_chat, clear_memory


# ============================================
# 1. APP & DB CONFIGURATION
# ============================================

load_dotenv(os.path.join(os.path.dirname(__file__), '..', '.env'))
app = Flask(__name__)

app.config['SECRET_KEY'] = os.getenv('FLASK_SECRET_KEY')
db_config = {
    'host': os.getenv('DB_HOST'),
    'user': os.getenv('DB_USER'),
    'password': os.getenv('DB_PASSWORD'),
    'database': os.getenv('DB_NAME')
}

if not app.config['SECRET_KEY']:
    raise ValueError("No FLASK_SECRET_KEY set in .env file.")

# ============================================
# 2. HELPER FUNCTIONS (RE-WRITTEN & FIXED)
# ============================================


def get_db_connection():
    try:
        conn = mysql.connector.connect(**db_config)
        return conn
    except mysql.connector.Error as err:
        print(f"Error: {err}")
        return None


def call_proc(proc_name, args=[]):
    """
    FIXED: This is a new, more robust helper function.
    It correctly uses 'dictionary=True' and handles 'Decimal' types.
    """
    conn = get_db_connection()
    if not conn:
        raise Exception("Database connection error")

    # dictionary=True returns rows as dicts
    cursor = conn.cursor(dictionary=True)
    try:
        # Call the procedure
        cursor.callproc(proc_name, args)

        results = []
        # This is the standard, reliable way to get results
        for result in cursor.stored_results():
            results = result.fetchall()  # This will be a list of dicts

        # Manually convert any Decimal types to float for JSON
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
        # This is critical: clear any remaining results
        cursor.close()
        conn.close()


# ============================================
# 3. HTML PAGE SERVING (FRONTEND)
# ============================================

@app.route('/login')
def login_page():
    return render_template('login.html')


@app.route('/dashboard')
def dashboard_page():
    if 'user_id' not in session:
        return redirect(url_for('login_page'))
    return render_template('index.html')


@app.route('/')
def home():
    if 'user_id' in session:
        return redirect(url_for('dashboard_page'))
    return redirect(url_for('login_page'))

# ============================================
# 4. USER AUTHENTICATION & SECURITY
# ============================================


def admin_required(f):
    @wraps(f)
    def decorated_function(*args, **kwargs):
        if session.get('role') != 'admin':
            return jsonify(message="Access forbidden: Requires admin privileges."), 403
        return f(*args, **kwargs)
    return decorated_function


@app.route('/api/auth/login', methods=['POST'])
def login():
    data = request.get_json()
    username = data.get('username')
    password = data.get('password').encode('utf-8')

    conn = get_db_connection()
    if not conn:
        return jsonify(message="Database connection error"), 500

    cursor = conn.cursor(dictionary=True)
    cursor.execute("SELECT * FROM Users WHERE Username = %s", (username,))
    user = cursor.fetchone()
    cursor.close()
    conn.close()

    if user and bcrypt.checkpw(password, user['PasswordHash'].encode('utf-8')):
        session['user_id'] = user['UserID']
        session['username'] = user['Username']
        session['role'] = user['Role']
        return jsonify(message="Login successful", user={'username': user['Username'], 'role': user['Role']}), 200
    else:
        return jsonify(message="Invalid username or password"), 401


@app.route('/api/auth/logout', methods=['POST'])
def logout():
    clear_memory(str(session.get('user_id', '')))
    session.clear()
    return jsonify(message="Logout successful"), 200


@app.route('/api/auth/current-user')
def current_user():
    if 'user_id' in session:
        return jsonify(user={'username': session['username'], 'role': session['role']}), 200
    else:
        return jsonify(message="Not logged in"), 401

# ============================================
# 5. DASHBOARD STATS API (KPIs)
# ============================================


@app.route('/api/dashboard/stats/pending-orders')
def get_pending_orders_count():
    conn = get_db_connection()
    if not conn:
        return jsonify(message="DB error"), 500
    cursor = conn.cursor()
    try:
        cursor.execute("SELECT fn_GetTotalPendingOrders() AS total")
        total = cursor.fetchone()[0]
        return jsonify(total=total), 200
    except Exception as e:
        return jsonify(message=str(e)), 500
    finally:
        cursor.close()
        conn.close()


@app.route('/api/dashboard/stats/outstanding-balance')
@admin_required
def get_outstanding_balance():
    conn = get_db_connection()
    if not conn:
        return jsonify(message="DB error"), 500
    cursor = conn.cursor()
    try:
        cursor.execute("SELECT fn_GetTotalOutstandingBalance() AS balance")
        balance = cursor.fetchone()[0]

        if isinstance(balance, Decimal):
            balance = float(balance)
        elif balance is None:
            balance = 0.0

        return jsonify(balance=f"{balance:,.2f}"), 200
    except Exception as e:
        return jsonify(message=str(e)), 500
    finally:
        cursor.close()
        conn.close()

# ============================================
# 6. CORE DASHBOARD API (Tables & Actions)
# ============================================


@app.route('/api/products/raw-materials')
@admin_required
def get_all_raw_materials():
    try:
        results = call_proc('sp_GetAllRawMaterials')
        return jsonify(data=results), 200
    except Exception as e:
        return jsonify(message=str(e)), 500


@app.route('/api/orders/pending')
def get_pending_orders_list():
    try:
        results = call_proc('sp_GetPendingOrders')
        return jsonify(data=results), 200
    except Exception as e:
        return jsonify(message=str(e)), 500


@app.route('/api/inventory/snapshot')
def get_inventory_snapshot():
    try:
        results = call_proc('sp_GetInventorySnapshot')
        return jsonify(data=results), 200
    except Exception as e:
        return jsonify(message=str(e)), 500


@app.route('/api/customers/overdue')
@admin_required
def get_overdue_customers():
    try:
        results = call_proc('sp_GetCustomersWithOverdueInvoices')
        return jsonify(data=results), 200
    except Exception as e:
        return jsonify(message=str(e)), 500


@app.route('/api/orders/details/<int:dist_id>')
def get_order_details(dist_id):
    try:
        results = call_proc('sp_GetOrderDetailsForTriage', [dist_id])
        return jsonify(data=results), 200
    except Exception as e:
        return jsonify(message=str(e)), 500


@app.route('/api/products/raw-materials/<int:product_id>/<int:qty_needed>')
def get_raw_material_needs(product_id, qty_needed):
    try:
        results = call_proc('sp_GetRawMaterialNeeds', [product_id, qty_needed])
        return jsonify(data=results), 200
    except Exception as e:
        return jsonify(message=str(e)), 500


@app.route('/api/suppliers/for-material/<int:raw_material_id>')
def get_suppliers(raw_material_id):
    try:
        results = call_proc('sp_GetSuppliersForRawMaterial', [raw_material_id])
        return jsonify(data=results), 200
    except Exception as e:
        return jsonify(message=str(e)), 500


@app.route('/api/orders/allocate', methods=['POST'])
@admin_required
def allocate_order():
    dist_id = request.get_json().get('dist_id')
    if not dist_id:
        return jsonify(message="dist_id is required"), 400

    try:
        call_proc('sp_AllocateStockForOrder', [dist_id])
        return jsonify(message=f"Order {dist_id} allocated. Stock updated and shipment created."), 200
    except Exception as e:
        return jsonify(message=str(e)), 500


@app.route('/api/orders/generate-po', methods=['POST'])
@admin_required
def generate_po_for_order():
    data = request.get_json()
    try:
        args = [
            data.get('dist_id'),
            data.get('supplier_id'),
            data.get('product_id'),
            data.get('quantity'),
            data.get('unit_price')
        ]
        results = call_proc('sp_GeneratePurchaseOrdersForShortfall', args)

        if results:
            new_po_id = results[0]['New_PO_ID']
            return jsonify(message=f"New Purchase Order {new_po_id} created for Order {data.get('dist_id')}."), 201
        else:
            return jsonify(message=f"Purchase Order created for Order {data.get('dist_id')}."), 201

    except Exception as e:
        return jsonify(message=str(e)), 500


@app.route('/api/procurement/purchase-orders', methods=['POST'])
@admin_required
def create_po():
    data = request.get_json()
    try:
        args = [
            data.get('supplier_id'),
            data.get('product_id'),
            data.get('quantity'),
            data.get('unit_price')
        ]
        results = call_proc('sp_CreateNewPurchaseOrder', args)
        new_po_id = results[0]['New_PO_ID']
        return jsonify(message=f"New Purchase Order {new_po_id} created."), 201
    except Exception as e:
        return jsonify(message=str(e)), 500


@app.route('/api/orders/cancel', methods=['POST'])
@admin_required
def cancel_order():
    dist_id = request.get_json().get('dist_id')
    if not dist_id:
        return jsonify(message="dist_id is required"), 400

    try:
        call_proc('sp_CancelDistributionOrder', [dist_id])
        return jsonify(message=f"Order {dist_id} canceled."), 200
    except Exception as e:
        return jsonify(message=str(e)), 500

# --- NEW ROUTE ---


@app.route('/api/orders/deallocate', methods=['POST'])
@admin_required
def deallocate_order():
    dist_id = request.get_json().get('dist_id')
    if not dist_id:
        return jsonify(message="dist_id is required"), 400

    try:
        call_proc('sp_DeallocateStockForOrder', [dist_id])
        return jsonify(message=f"Order {dist_id} deallocated. Stock returned."), 200
    except Exception as e:
        return jsonify(message=str(e)), 500


@app.route('/api/procurement/purchase-orders')
@admin_required
def get_all_purchase_orders():
    try:
        results = call_proc('sp_GetAllPurchaseOrders')
        return jsonify(data=results), 200
    except Exception as e:
        return jsonify(message=str(e)), 500


@app.route('/api/finance/invoices')
@admin_required
def get_unpaid_invoices():
    try:
        results = call_proc('sp_GetUnpaidInvoices')
        return jsonify(data=results), 200
    except Exception as e:
        return jsonify(message=str(e)), 500


@app.route('/api/finance/payments', methods=['POST'])
@admin_required
def record_payment():
    data = request.get_json()
    try:
        args = [
            data.get('invoice_id'),
            data.get('amount_paid'),
            data.get('pay_method')
        ]
        call_proc('sp_RecordPayment', args)
        return jsonify(message="Payment recorded!"), 201
    except Exception as e:
        return jsonify(message=str(e)), 500


@app.route('/api/finance/payment-history')
@admin_required
def get_payment_history():
    try:
        results = call_proc('sp_GetAllPayments')
        return jsonify(data=results), 200
    except Exception as e:
        return jsonify(message=str(e)), 500

'''
@app.route('/api/chat', methods=['POST'])
def chat_endpoint():
    data = request.get_json()
    user_message = data.get('message', '').strip()
    if not user_message:
        return jsonify(message="No message provided"), 400
    session_id = session.get('user_id', 'anonymous')
    try:
        response = agent_chat(user_message, str(session_id))
        return jsonify(reply=response), 200
    except Exception as e:
        return jsonify(message=str(e)), 500

@app.route('/api/chat/clear', methods=['POST'])
def clear_chat():
    session_id = session.get('user_id', 'anonymous')
    clear_memory(str(session_id))
    return jsonify(message="Conversation cleared"), 200  '''


# ============================================
# 8. FORECASTING API
# ============================================


@app.route('/api/forecast/all')
def forecast_all():
    """
    Returns forecast summary for all three finished goods.
    Used by the dashboard Forecast tab overview.
    """
    try:
        results = get_all_forecasts(horizon_days=90)
        return jsonify(data=results), 200
    except Exception as e:
        return jsonify(message=str(e)), 500


@app.route('/api/forecast/<int:product_id>')
def forecast_product(product_id):
    """
    Returns full forecast for one product — historical + future predictions.
    Used to render the Plotly chart for a specific product.
    Query param: ?horizon=90 (default 90 days)
    Example: /api/forecast/2001?horizon=90
    """
    if product_id not in [2001, 2002, 2003]:
        return jsonify(message="Invalid product_id. Must be 2001, 2002, or 2003."), 400
    try:
        horizon = int(request.args.get('horizon', 90))
        result = get_forecast(product_id, horizon_days=horizon)
        return jsonify(data=result), 200
    except FileNotFoundError:
        return jsonify(message="Model not found. Run forecasting/train.py first."), 500
    except Exception as e:
        return jsonify(message=str(e)), 500


@app.route('/api/forecast/suggested-po/<int:product_id>')
def forecast_suggested_po(product_id):
    """
    Returns suggested PO quantity for one product.
    Compares 30-day forecast against current inventory.
    Used by the 'Raise PO' button on the dashboard.
    Query param: ?horizon=30 (default 30 days)
    """
    if product_id not in [2001, 2002, 2003]:
        return jsonify(message="Invalid product_id. Must be 2001, 2002, or 2003."), 400
    try:
        horizon = int(request.args.get('horizon', 30))
        result = get_suggested_po(product_id, horizon_days=horizon)
        return jsonify(data=result), 200
    except FileNotFoundError:
        return jsonify(message="Model not found. Run forecasting/train.py first."), 500
    except Exception as e:
        return jsonify(message=str(e)), 500

# --- END NEW ROUTE ---

# ── Chatbot ───────────────────────────────────────────────────────────────────

from chatbot.agent import chat, clear_memory

@app.route('/api/chat', methods=['POST'])
def chat_endpoint():
    if 'user_id' not in session:
        return jsonify(message="Not logged in"), 401
    data = request.get_json()
    user_message = data.get('message', '').strip()
    if not user_message:
        return jsonify(message="Message cannot be empty"), 400
    session_id = str(session['user_id'])
    try:
        response = agent_chat(user_message, session_id)
        return jsonify(response=response), 200
    except Exception as e:
        return jsonify(message=str(e)), 500


@app.route('/api/chat/clear', methods=['POST'])
def clear_chat():
    if 'user_id' not in session:
        return jsonify(message="Not logged in"), 401
    clear_memory(str(session['user_id']))
    return jsonify(message="Chat history cleared"), 200

# ============================================
# 7. RUN THE APPLICATION
# ============================================


if __name__ == '__main__':
    app.run(debug=True)
