"""
FinTrace — Flask backend
Run:  python app.py      → open http://localhost:5000

Every change made during the clean-up is marked with a  # FIX:  comment
so you can see what was changed and why.
"""
import os
from functools import wraps

import MySQLdb
import re
from dotenv import load_dotenv
from flask import Flask, request, jsonify, render_template, session, redirect, Response
from flask_cors import CORS
from werkzeug.security import generate_password_hash, check_password_hash

from database import mysql, init_db

load_dotenv()

from datetime import datetime, date
from flask.json.provider import DefaultJSONProvider


class LocalTimeJSONProvider(DefaultJSONProvider):
    """FIX: send dates as '2026-11-11T20:16:00' (no timezone) so the browser
    shows them in local time. Flask's default format ends in 'GMT', which made
    the browser add +5:30 to every time (e.g. 8 PM showed as 1:46 AM next day)."""
    @staticmethod
    def default(o):
        if isinstance(o, (datetime, date)):
            return o.isoformat()
        return DefaultJSONProvider.default(o)


app = Flask(__name__)
app.json = LocalTimeJSONProvider(app)
# FIX: secret key now comes from .env instead of being hard-coded in the code
app.secret_key = os.getenv('SECRET_KEY', 'dev-only-change-me')
CORS(app)
init_db(app)


# ─────────────────────────────────────────
# AUTH DECORATORS
# ─────────────────────────────────────────
def require_auth(f):
    @wraps(f)
    def decorated(*args, **kwargs):
        if 'user_id' not in session:
            if request.path.startswith('/api/'):
                return jsonify({'success': False, 'error': 'Not authenticated'}), 401
            return redirect('/login-page')
        return f(*args, **kwargs)
    return decorated


def require_admin(f):
    @wraps(f)
    def decorated(*args, **kwargs):
        if 'user_id' not in session:
            if request.path.startswith('/api/'):
                return jsonify({'success': False, 'error': 'Not authenticated'}), 401
            return redirect('/login-page')
        if session.get('role') != 'admin':
            if request.path.startswith('/api/'):
                return jsonify({'success': False, 'error': 'Admin only'}), 403
            return redirect('/user-dashboard')
        return f(*args, **kwargs)
    return decorated


# ─────────────────────────────────────────
# HELPERS
# ─────────────────────────────────────────
def is_admin():
    return session.get('role') == 'admin'


# FIX: ownership checks. Before, any logged-in user could read or move money
# from ANY account just by changing the id in the URL / request body.
def owns_account(account_id):
    """True if the logged-in user owns this account (admins may access any)."""
    if is_admin():
        return True
    cursor = mysql.connection.cursor()
    cursor.execute("SELECT 1 FROM Accounts WHERE account_id=%s AND user_id=%s",
                   (account_id, session['user_id']))
    ok = cursor.fetchone() is not None
    cursor.close()
    return ok


def is_self(user_id):
    """True if user_id is the logged-in user (admins may access any)."""
    return is_admin() or int(user_id) == int(session['user_id'])


def forbidden():
    return jsonify({'success': False, 'error': 'You do not have access to this'}), 403


# FIX: database errors raised on purpose by our procedures (SIGNAL '45000',
# e.g. "Insufficient balance") are now returned as a clean message with
# status 400, instead of a raw Python tuple with status 500.
def db_error(e):
    try:
        mysql.connection.rollback()
    except Exception:
        pass
    if isinstance(e, MySQLdb.OperationalError) and e.args and e.args[0] == 1644:
        return jsonify({'success': False, 'error': e.args[1]}), 400
    if isinstance(e, MySQLdb.IntegrityError):
        return jsonify({'success': False, 'error': 'Invalid data: ' + str(e.args[-1])}), 400
    app.logger.exception(e)
    return jsonify({'success': False, 'error': str(e)}), 500


def call_procedure(cursor, name, args):
    """Call a stored procedure and drain every result set it returns.
    FIX: leaving result sets unread caused 'Commands out of sync' errors."""
    cursor.callproc(name, args)
    rows = cursor.fetchall()
    while cursor.nextset():
        pass
    return rows


# ─────────────────────────────────────────
# PAGE ROUTES
# ─────────────────────────────────────────
@app.route('/')
def root():
    if 'user_id' in session:
        return redirect('/admin-dashboard' if is_admin() else '/user-dashboard')
    return redirect('/login-page')

@app.route('/login-page')
def login_page():
    return render_template('login.html')

@app.route('/register-page')
def register_page():
    return render_template('register.html')

@app.route('/admin-dashboard')
@require_admin
def admin_dashboard():
    return render_template('admin_dashboard.html')

@app.route('/user-dashboard')
@require_auth
def user_dashboard():
    return render_template('user_dashboard.html')

@app.route('/my-transactions')
@require_auth
def my_transactions():
    return render_template('my_transactions.html')

@app.route('/transfers-page')
@require_auth
def transfers_page():
    return render_template('transfers.html')

@app.route('/budget-page')
@require_auth
def budget_page():
    return render_template('budget.html')

@app.route('/reports-page')
@require_admin
def reports_page():
    return render_template('reports.html')

@app.route('/flagged-page')
@require_admin
def flagged_page():
    return render_template('flagged.html')

# FIX: the Fraud Flags page existed but had no route, so it could never be opened
@app.route('/fraud-flags-page')
@require_admin
def fraud_flags_page():
    return render_template('fraud_flags.html')

@app.route('/notifications-page')
@require_auth
def notifications_page():
    return render_template('notifications.html')

@app.route('/audit-page')
@require_admin
def audit_page():
    return render_template('audit.html')

@app.route('/delete-requests-page')
@require_admin
def delete_requests_page():
    return render_template('delete_requests.html')


# ─────────────────────────────────────────
# AUTH APIs
# ─────────────────────────────────────────
@app.route('/api/login', methods=['POST'])
def api_login():
    data     = request.get_json() or {}
    email    = data.get('email', '').strip().lower()
    password = data.get('password', '').strip()

    if not email or not password:
        return jsonify({'success': False, 'error': 'Email and password required'}), 400

    try:
        cursor = mysql.connection.cursor(MySQLdb.cursors.DictCursor)
        cursor.execute("SELECT * FROM Users WHERE email = %s", (email,))
        user = cursor.fetchone()

        # FIX: same message for "no such email" and "wrong password",
        # so the login form can't be used to discover which emails exist
        if not user or not user.get('password_hash') \
                or not check_password_hash(user['password_hash'], password):
            cursor.close()
            return jsonify({'success': False, 'error': 'Invalid email or password'}), 401

        cursor.execute(
            "SELECT account_id, account_name, balance FROM Accounts WHERE user_id = %s LIMIT 1",
            (user['user_id'],)
        )
        account = cursor.fetchone()

        cursor.execute("UPDATE Users SET last_login = NOW() WHERE user_id = %s", (user['user_id'],))
        mysql.connection.commit()
        cursor.close()

        session.clear()
        session['user_id']   = user['user_id']
        session['full_name'] = user['full_name']
        session['role']      = user['role']

        return jsonify({
            'success': True,
            'user': {
                'id':           user['user_id'],
                'name':         user['full_name'],
                'role':         user['role'],
                'email':        user['email'],
                'account_id':   account['account_id']   if account else None,
                'account_name': account['account_name'] if account else None,
                'balance':      float(account['balance']) if account else 0
            }
        })
    except Exception as e:
        return db_error(e)


@app.route('/api/register', methods=['POST'])
def api_register():
    data         = request.get_json() or {}
    full_name    = data.get('full_name', '').strip()
    email        = data.get('email', '').strip().lower()
    password     = data.get('password', '').strip()
    account_name = data.get('account_name', '').strip()
    # FIX: a non-numeric balance used to crash the server
    try:
        opening_balance = float(data.get('opening_balance', 0))
    except (TypeError, ValueError):
        return jsonify({'success': False, 'error': 'Opening balance must be a number'}), 400

    # ── Validations ──
    if not full_name or not email or not password or not account_name:
        return jsonify({'success': False, 'error': 'All fields are required'}), 400
    if '@' in full_name or '.com' in full_name.lower():
        return jsonify({'success': False, 'error': 'Full name should be your real name, not an email'}), 400
    if len(full_name) < 3:
        return jsonify({'success': False, 'error': 'Full name must be at least 3 characters'}), 400
    if not re.match(r'^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$', email):
        return jsonify({'success': False, 'error': 'Enter a valid email address'}), 400
    if len(password) < 6:
        return jsonify({'success': False, 'error': 'Password must be at least 6 characters'}), 400
    if len(account_name) < 3:
        return jsonify({'success': False, 'error': 'Account name must be at least 3 characters'}), 400
    if opening_balance < 500:
        return jsonify({'success': False, 'error': 'Minimum opening balance is ₹500'}), 400

    try:
        cursor = mysql.connection.cursor(MySQLdb.cursors.DictCursor)
        cursor.execute("SELECT user_id FROM Users WHERE email = %s", (email,))
        if cursor.fetchone():
            cursor.close()
            return jsonify({'success': False, 'error': 'Email already registered'}), 409

        cursor.execute(
            "INSERT INTO Users (full_name, email, password_hash, role) VALUES (%s,%s,%s,'user')",
            (full_name, email, generate_password_hash(password))
        )
        new_user_id = cursor.lastrowid
        cursor.execute(
            "INSERT INTO Accounts (user_id, account_name, balance) VALUES (%s,%s,%s)",
            (new_user_id, account_name, opening_balance)
        )
        mysql.connection.commit()
        cursor.close()
        return jsonify({'success': True, 'message': 'Account created! You can now login.'})
    except Exception as e:
        return db_error(e)


@app.route('/api/logout', methods=['POST'])
def api_logout():
    session.clear()
    return jsonify({'success': True})


@app.route('/api/session', methods=['GET'])
def api_session():
    if 'user_id' in session:
        return jsonify({'success': True, 'logged_in': True, 'user': {
            'id': session['user_id'], 'name': session['full_name'], 'role': session['role']
        }})
    return jsonify({'success': False, 'logged_in': False})


# ─────────────────────────────────────────
# DASHBOARD API
# ─────────────────────────────────────────
@app.route('/api/dashboard/<int:user_id>/<string:role>', methods=['GET'])
@require_auth
def get_dashboard(user_id, role):
    # FIX: the role in the URL used to be trusted, so a normal user could open
    # /api/dashboard/1/admin and see system-wide data. Now we use the session.
    if role == 'admin' and not is_admin():
        return forbidden()
    if not is_self(user_id):
        return forbidden()
    try:
        cursor = mysql.connection.cursor(MySQLdb.cursors.DictCursor)

        if role == 'admin':
            cursor.execute("SELECT COUNT(*) AS c FROM Users")
            total_users = cursor.fetchone()['c']
            cursor.execute("SELECT COUNT(*) AS c FROM Transactions")
            total_tx = cursor.fetchone()['c']
            cursor.execute("SELECT COALESCE(SUM(balance),0) AS c FROM Accounts")
            total_bal = float(cursor.fetchone()['c'])
            cursor.execute("SELECT COUNT(*) AS c FROM Audit_Log")
            total_audit = cursor.fetchone()['c']
            cursor.execute("SELECT COUNT(*) AS c FROM Flagged_Transactions WHERE reviewed=FALSE")
            total_flagged = cursor.fetchone()['c']
            cursor.execute("SELECT COUNT(*) AS c FROM Fraud_Flags WHERE reviewed=FALSE")
            total_fraud = cursor.fetchone()['c']
            cursor.execute("SELECT COUNT(*) AS c FROM Delete_Requests WHERE status='pending'")
            pending_deletes = cursor.fetchone()['c']
            cursor.execute("""
                SELECT * FROM vw_transaction_report
                ORDER BY transaction_date DESC, transaction_id DESC LIMIT 10
            """)
            recent = cursor.fetchall()
            cursor.close()
            return jsonify({'success': True, 'data': {
                'total_users':             total_users,
                'total_transactions':      total_tx,
                'total_system_balance':    total_bal,
                'total_audit_events':      total_audit,
                'total_flagged':           total_flagged,
                'total_fraud_flags':       total_fraud,
                'pending_delete_requests': pending_deletes,
                'recent_transactions':     recent
            }})

        # ── USER DASHBOARD ──
        cursor.execute(
            "SELECT account_id, account_name, balance FROM Accounts WHERE user_id=%s LIMIT 1",
            (user_id,)
        )
        account = cursor.fetchone()
        if not account:
            cursor.close()
            return jsonify({'success': False, 'error': 'No account found'}), 404

        account_id = account['account_id']
        cursor.execute("SELECT CalculateTotalByType(%s,'credit') AS total", (account_id,))
        total_income = float(cursor.fetchone()['total'] or 0)
        cursor.execute("SELECT CalculateTotalByType(%s,'debit') AS total", (account_id,))
        total_expense = float(cursor.fetchone()['total'] or 0)

        cursor.execute("""
            SELECT t.transaction_id, t.amount, t.transaction_type,
                   t.description, t.transaction_date, c.category_name
            FROM Transactions t
            JOIN Categories c ON t.category_id = c.category_id
            WHERE t.account_id = %s
            ORDER BY t.transaction_date DESC, t.transaction_id DESC LIMIT 10
        """, (account_id,))
        recent = cursor.fetchall()

        cursor.execute(
            "SELECT COUNT(*) AS c FROM Notifications WHERE user_id=%s AND is_read=FALSE", (user_id,)
        )
        unread = cursor.fetchone()['c']
        cursor.close()
        return jsonify({'success': True, 'data': {
            'account_id':           account_id,
            'account_name':         account['account_name'],
            'balance':              float(account['balance']),
            'total_income':         total_income,
            'total_expense':        total_expense,
            'recent_transactions':  recent,
            'unread_notifications': unread
        }})
    except Exception as e:
        return db_error(e)


# ─────────────────────────────────────────
# TRANSACTION APIs
# ─────────────────────────────────────────
@app.route('/api/transactions', methods=['GET'])
@require_auth
def get_transactions():
    try:
        cursor = mysql.connection.cursor(MySQLdb.cursors.DictCursor)
        if is_admin():
            cursor.execute("SELECT * FROM vw_transaction_report ORDER BY transaction_date DESC")
        else:
            cursor.execute("""
                SELECT t.transaction_id, t.amount, t.transaction_type,
                       t.description, t.transaction_date,
                       c.category_name, c.category_type, a.account_name
                FROM Transactions t
                JOIN Accounts a   ON t.account_id  = a.account_id
                JOIN Categories c ON t.category_id = c.category_id
                WHERE a.user_id = %s
                ORDER BY t.transaction_date DESC
            """, (session['user_id'],))
        rows = cursor.fetchall()
        cursor.close()
        return jsonify({'success': True, 'count': len(rows), 'data': rows})
    except Exception as e:
        return db_error(e)


@app.route('/api/my-transactions/<int:account_id>', methods=['GET'])
@require_auth
def get_my_transactions(account_id):
    if not owns_account(account_id):          # FIX: ownership check
        return forbidden()
    try:
        cursor = mysql.connection.cursor(MySQLdb.cursors.DictCursor)
        cursor.execute("""
            SELECT t.transaction_id, t.amount, t.transaction_type,
                   t.description, t.transaction_date, c.category_name
            FROM Transactions t
            JOIN Categories c ON t.category_id = c.category_id
            WHERE t.account_id = %s
            ORDER BY t.transaction_date DESC, t.transaction_id DESC
        """, (account_id,))
        rows = cursor.fetchall()
        cursor.close()
        return jsonify({'success': True, 'count': len(rows), 'data': rows})
    except Exception as e:
        return db_error(e)


@app.route('/api/add-transaction', methods=['POST'])
@require_auth
def add_transaction():
    data = request.get_json() or {}
    try:
        account_id  = int(data['account_id'])
        category_id = int(data['category_id'])
        amount      = float(data['amount'])
        trans_type  = data['transaction_type']
    except (KeyError, TypeError, ValueError):
        return jsonify({'success': False, 'error': 'Account, category, amount and type are required'}), 400
    if not owns_account(account_id):          # FIX: ownership check
        return forbidden()
    try:
        cursor = mysql.connection.cursor()
        # AddTransaction updates the balance itself, inside one DB transaction.
        # FIX: there is no longer a second trigger that ALSO changed the balance
        # (that made every amount count twice).
        call_procedure(cursor, 'AddTransaction',
                       [account_id, category_id, amount, trans_type, data.get('description', '')])
        mysql.connection.commit()
        cursor.close()
        return jsonify({'success': True, 'message': 'Transaction added. Audit log updated automatically.'})
    except Exception as e:
        return db_error(e)


@app.route('/api/delete-transaction/<int:tid>', methods=['DELETE'])
@require_admin
def delete_transaction(tid):
    try:
        cursor = mysql.connection.cursor()
        cursor.execute("DELETE FROM Transactions WHERE transaction_id=%s", (tid,))
        mysql.connection.commit()
        cursor.close()
        return jsonify({'success': True, 'message': f'Transaction {tid} deleted. Audit log updated.'})
    except Exception as e:
        return db_error(e)


# ─────────────────────────────────────────
# USERS & ACCOUNTS APIs
# ─────────────────────────────────────────
@app.route('/api/users', methods=['GET'])
@require_admin                                 # FIX: was open to every user
def get_users():
    try:
        cursor = mysql.connection.cursor(MySQLdb.cursors.DictCursor)
        cursor.execute("SELECT user_id, full_name, email, role, created_at FROM Users ORDER BY created_at DESC")
        rows = cursor.fetchall()
        cursor.close()
        return jsonify({'success': True, 'data': rows})
    except Exception as e:
        return db_error(e)


@app.route('/api/accounts', methods=['GET'])
@require_auth
def get_accounts():
    try:
        cursor = mysql.connection.cursor(MySQLdb.cursors.DictCursor)
        if is_admin():
            cursor.execute("""
                SELECT a.account_id, a.account_name, a.balance, u.full_name, u.email
                FROM Accounts a JOIN Users u ON a.user_id = u.user_id
                ORDER BY u.full_name
            """)
        else:
            cursor.execute("SELECT account_id, account_name, balance FROM Accounts WHERE user_id=%s",
                           (session['user_id'],))
        rows = cursor.fetchall()
        cursor.close()
        return jsonify({'success': True, 'data': rows})
    except Exception as e:
        return db_error(e)


@app.route('/api/accounts/all', methods=['GET'])
@require_auth
def get_all_accounts():
    """All accounts (names only, no balances) — used as transfer destinations."""
    try:
        cursor = mysql.connection.cursor(MySQLdb.cursors.DictCursor)
        cursor.execute("""
            SELECT a.account_id, a.account_name, u.full_name AS user_name
            FROM Accounts a JOIN Users u ON a.user_id = u.user_id
            ORDER BY u.full_name, a.account_name
        """)
        rows = cursor.fetchall()
        cursor.close()
        return jsonify({'success': True, 'data': rows})
    except Exception as e:
        return db_error(e)


@app.route('/api/categories', methods=['GET'])
@require_auth
def get_categories():
    try:
        cursor = mysql.connection.cursor(MySQLdb.cursors.DictCursor)
        # 'Transfer' is used internally by TransferFunds, so hide it from forms
        cursor.execute("""
            SELECT * FROM Categories WHERE category_name <> 'Transfer'
            ORDER BY category_type, category_name
        """)
        rows = cursor.fetchall()
        cursor.close()
        return jsonify({'success': True, 'data': rows})
    except Exception as e:
        return db_error(e)


@app.route('/api/admin/users-summary', methods=['GET'])
@require_admin
def admin_users_summary():
    try:
        cursor = mysql.connection.cursor(MySQLdb.cursors.DictCursor)
        cursor.execute("""
            SELECT u.user_id, u.full_name, u.email, u.role, u.last_login,
                   COALESCE(a.account_id, 0)             AS account_id,
                   COALESCE(a.account_name,'No Account') AS account_name,
                   COALESCE(a.balance, 0.00)             AS balance,
                   COUNT(t.transaction_id)               AS transaction_count,
                   CalculateCreditScore(u.user_id)       AS credit_score
            FROM Users u
            LEFT JOIN Accounts a     ON u.user_id    = a.user_id
            LEFT JOIN Transactions t ON a.account_id = t.account_id
            GROUP BY u.user_id, u.full_name, u.email, u.role, u.last_login,
                     u.created_at, a.account_id, a.account_name, a.balance
            ORDER BY u.created_at DESC
        """)
        rows = cursor.fetchall()
        cursor.close()
        return jsonify({'success': True, 'count': len(rows), 'data': rows})
    except Exception as e:
        return db_error(e)


@app.route('/api/admin/delete-user/<int:user_id>', methods=['DELETE'])
@require_admin
def admin_delete_user(user_id):
    if user_id == session['user_id']:
        return jsonify({'success': False, 'error': 'You cannot delete your own account'}), 400
    try:
        cursor = mysql.connection.cursor(MySQLdb.cursors.DictCursor)
        cursor.execute("SELECT role FROM Users WHERE user_id=%s", (user_id,))
        user = cursor.fetchone()
        if not user:
            cursor.close()
            return jsonify({'success': False, 'error': 'User not found'}), 404
        if user['role'] == 'admin':
            cursor.close()
            return jsonify({'success': False, 'error': 'Cannot delete admin accounts'}), 403
        # CASCADE removes the account, transactions, transfers, budgets, etc.
        cursor.execute("DELETE FROM Users WHERE user_id=%s", (user_id,))
        mysql.connection.commit()
        cursor.close()
        return jsonify({'success': True, 'message': 'User deleted. All their data removed.'})
    except Exception as e:
        return db_error(e)


# ─────────────────────────────────────────
# DELETE REQUESTS SYSTEM
# ─────────────────────────────────────────
@app.route('/api/request-account-deletion', methods=['POST'])
@require_auth
def request_account_deletion():
    user_id = session['user_id']
    reason  = ((request.get_json() or {}).get('reason') or 'No reason provided').strip()
    try:
        cursor = mysql.connection.cursor(MySQLdb.cursors.DictCursor)
        cursor.execute("SELECT request_id FROM Delete_Requests WHERE user_id=%s AND status='pending'",
                       (user_id,))
        if cursor.fetchone():
            cursor.close()
            return jsonify({'success': False, 'error': 'You already have a pending deletion request'}), 409
        cursor.execute("INSERT INTO Delete_Requests (user_id, reason) VALUES (%s, %s)", (user_id, reason))
        mysql.connection.commit()
        cursor.close()
        return jsonify({'success': True, 'message': 'Deletion request submitted. Admin will review it.'})
    except Exception as e:
        return db_error(e)


@app.route('/api/delete-requests', methods=['GET'])
@require_admin
def get_delete_requests():
    try:
        cursor = mysql.connection.cursor(MySQLdb.cursors.DictCursor)
        cursor.execute("""
            SELECT dr.request_id, dr.user_id, dr.reason, dr.status, dr.requested_at,
                   u.full_name, u.email, u.role,
                   COALESCE(a.account_name,'No Account') AS account_name,
                   COALESCE(a.balance, 0)                AS balance
            FROM Delete_Requests dr
            JOIN Users u         ON dr.user_id = u.user_id
            LEFT JOIN Accounts a ON u.user_id  = a.user_id
            ORDER BY dr.requested_at DESC
        """)
        rows = cursor.fetchall()
        cursor.close()
        return jsonify({'success': True, 'count': len(rows), 'data': rows})
    except Exception as e:
        return db_error(e)


@app.route('/api/handle-delete-request/<int:request_id>', methods=['POST'])
@require_admin
def handle_delete_request(request_id):
    action = (request.get_json() or {}).get('action')
    if action not in ('approve', 'reject'):
        return jsonify({'success': False, 'error': 'Invalid action'}), 400
    try:
        cursor = mysql.connection.cursor(MySQLdb.cursors.DictCursor)
        cursor.execute("SELECT * FROM Delete_Requests WHERE request_id=%s AND status='pending'",
                       (request_id,))
        req = cursor.fetchone()
        if not req:
            cursor.close()
            return jsonify({'success': False, 'error': 'Request not found or already handled'}), 404

        if action == 'approve':
            # Deleting the user CASCADE-removes their account, transactions and this request
            cursor.execute("DELETE FROM Users WHERE user_id=%s", (req['user_id'],))
            msg = 'User account deleted successfully.'
        else:
            cursor.execute("UPDATE Delete_Requests SET status='rejected' WHERE request_id=%s", (request_id,))
            msg = 'Deletion request rejected.'
        mysql.connection.commit()
        cursor.close()
        return jsonify({'success': True, 'message': msg})
    except Exception as e:
        return db_error(e)


# ─────────────────────────────────────────
# AUDIT, NOTIFICATIONS, TRANSFERS, BUDGETS
# ─────────────────────────────────────────
@app.route('/api/audit-logs', methods=['GET'])
@require_admin
def get_audit_logs():
    try:
        cursor = mysql.connection.cursor(MySQLdb.cursors.DictCursor)
        cursor.execute("SELECT * FROM vw_audit_report")
        rows = cursor.fetchall()
        cursor.close()
        return jsonify({'success': True, 'count': len(rows), 'data': rows})
    except Exception as e:
        return db_error(e)


@app.route('/api/notifications/<int:user_id>', methods=['GET'])
@require_auth
def get_notifications(user_id):
    if not is_self(user_id):                   # FIX: ownership check
        return forbidden()
    try:
        cursor = mysql.connection.cursor(MySQLdb.cursors.DictCursor)
        cursor.execute("SELECT * FROM Notifications WHERE user_id=%s ORDER BY created_at DESC, notification_id DESC",
                       (user_id,))
        rows = cursor.fetchall()
        cursor.close()
        return jsonify({'success': True, 'count': len(rows), 'data': rows})
    except Exception as e:
        return db_error(e)


@app.route('/api/mark-notification-read/<int:nid>', methods=['POST'])
@require_auth
def mark_notification_read(nid):
    try:
        cursor = mysql.connection.cursor()
        # FIX: a user can only mark their OWN notifications as read
        cursor.execute("UPDATE Notifications SET is_read=TRUE WHERE notification_id=%s AND user_id=%s",
                       (nid, session['user_id']))
        mysql.connection.commit()
        cursor.close()
        return jsonify({'success': True})
    except Exception as e:
        return db_error(e)


@app.route('/api/transfer', methods=['POST'])
@require_auth
def transfer_funds():
    data = request.get_json() or {}
    try:
        from_account = int(data.get('from_account_id'))
        to_account   = int(data.get('to_account_id'))
        amount       = float(data.get('amount', 0))
    except (TypeError, ValueError):
        return jsonify({'success': False, 'error': 'From account, to account and amount are required'}), 400
    if amount <= 0:
        return jsonify({'success': False, 'error': 'Amount must be positive'}), 400
    # FIX: before this check, a user could send money OUT of someone else's account
    if not owns_account(from_account):
        return jsonify({'success': False, 'error': 'You can only transfer from your own account'}), 403
    try:
        cursor = mysql.connection.cursor()
        call_procedure(cursor, 'TransferFunds',
                       [from_account, to_account, amount, data.get('description') or 'Fund Transfer'])
        mysql.connection.commit()
        cursor.close()
        return jsonify({'success': True, 'message': 'Transfer completed successfully'})
    except Exception as e:
        return db_error(e)


@app.route('/api/transfers/<int:account_id>', methods=['GET'])
@require_auth
def get_transfers(account_id):
    if not owns_account(account_id):          # FIX: ownership check
        return forbidden()
    try:
        cursor = mysql.connection.cursor(MySQLdb.cursors.DictCursor)
        cursor.execute("""
            SELECT t.*, a1.account_name AS from_account_name, a2.account_name AS to_account_name
            FROM Transfers t
            LEFT JOIN Accounts a1 ON t.from_account_id = a1.account_id
            LEFT JOIN Accounts a2 ON t.to_account_id   = a2.account_id
            WHERE t.from_account_id=%s OR t.to_account_id=%s
            ORDER BY t.transfer_date DESC, t.transfer_id DESC
        """, (account_id, account_id))
        rows = cursor.fetchall()
        cursor.close()
        return jsonify({'success': True, 'count': len(rows), 'data': rows})
    except Exception as e:
        return db_error(e)


@app.route('/api/set-budget', methods=['POST'])
@require_auth
def set_budget():
    data = request.get_json() or {}
    try:
        user_id       = int(data.get('user_id') or session['user_id'])
        category_id   = int(data.get('category_id'))
        monthly_limit = float(data.get('monthly_limit', 0))
    except (TypeError, ValueError):
        return jsonify({'success': False, 'error': 'Category and limit are required'}), 400
    if not is_self(user_id):                   # FIX: ownership check
        return forbidden()
    if monthly_limit <= 0:
        return jsonify({'success': False, 'error': 'Limit must be positive'}), 400
    try:
        cursor = mysql.connection.cursor()
        # FIX: used to fail with "Commands out of sync" (result set never read)
        call_procedure(cursor, 'SetBudget', [user_id, category_id, monthly_limit])
        mysql.connection.commit()
        cursor.close()
        return jsonify({'success': True, 'message': 'Budget set successfully'})
    except Exception as e:
        return db_error(e)


@app.route('/api/budgets/<int:user_id>', methods=['GET'])
@require_auth
def get_budgets(user_id):
    if not is_self(user_id):                   # FIX: ownership check
        return forbidden()
    try:
        cursor = mysql.connection.cursor(MySQLdb.cursors.DictCursor)
        # FIX: GetMonthlySpending now takes a user_id (it used to expect an
        # account_id while being given a user_id, so "spent" was wrong)
        cursor.execute("""
            SELECT b.*, c.category_name,
                   GetMonthlySpending(b.user_id, b.category_id) AS amount_spent
            FROM Budgets b JOIN Categories c ON b.category_id = c.category_id
            WHERE b.user_id = %s
            ORDER BY c.category_name
        """, (user_id,))
        budgets = cursor.fetchall()
        cursor.close()
        for b in budgets:
            b['amount_spent']     = float(b['amount_spent'] or 0)
            b['amount_remaining'] = float(b['monthly_limit']) - b['amount_spent']
        return jsonify({'success': True, 'count': len(budgets), 'data': budgets})
    except Exception as e:
        return db_error(e)


# ─────────────────────────────────────────
# REPORTS
# ─────────────────────────────────────────
@app.route('/api/generate-report', methods=['POST'])
@require_admin
def generate_report():
    data = request.get_json() or {}
    try:
        month = int(data.get('month'))
        year  = int(data.get('year'))
    except (TypeError, ValueError):
        return jsonify({'success': False, 'error': 'Month and year are required'}), 400
    user_id = data.get('user_id')
    try:
        cursor = mysql.connection.cursor(MySQLdb.cursors.DictCursor)
        # FIX: now uses the cursor-based stored procedure (as the README describes)
        # and upserts, so re-generating a month no longer creates duplicate rows
        rows = call_procedure(cursor, 'GenerateMonthlyReport', [month, year, user_id])
        mysql.connection.commit()
        cursor.close()
        processed = rows[0]['accounts_processed'] if rows else 0
        return jsonify({'success': True,
                        'message': f'Report generated for {processed} account(s)',
                        'data': [None] * processed})
    except Exception as e:
        return db_error(e)


@app.route('/api/monthly-reports', methods=['GET'])
@require_admin
def get_monthly_reports():
    try:
        cursor = mysql.connection.cursor(MySQLdb.cursors.DictCursor)
        cursor.execute("""
            SELECT r.*, a.account_name, u.full_name
            FROM Monthly_Reports r
            JOIN Accounts a ON r.account_id = a.account_id
            JOIN Users u    ON a.user_id    = u.user_id
            ORDER BY r.report_year DESC, r.report_month DESC, u.full_name
        """)
        rows = cursor.fetchall()
        cursor.close()
        return jsonify({'success': True, 'count': len(rows), 'data': rows})
    except Exception as e:
        return db_error(e)


@app.route('/api/download-report/<int:report_id>', methods=['GET'])
@require_admin
def download_report(report_id):
    try:
        cursor = mysql.connection.cursor(MySQLdb.cursors.DictCursor)
        cursor.execute("""
            SELECT r.*, a.account_name, u.full_name, u.email
            FROM Monthly_Reports r
            JOIN Accounts a ON r.account_id = a.account_id
            JOIN Users u    ON a.user_id    = u.user_id
            WHERE r.report_id = %s
        """, (report_id,))
        r = cursor.fetchone()
        cursor.close()
        if not r:
            return jsonify({'success': False, 'error': 'Report not found'}), 404

        csv = "Report ID,User Name,Email,Account Name,Month,Year,Total Income,Total Expense,Net Savings\n"
        csv += (f"{r['report_id']},\"{r['full_name']}\",{r['email']},\"{r['account_name']}\","
                f"{r['report_month']},{r['report_year']},"
                f"{r['total_income']},{r['total_expense']},{r['net_savings']}\n")
        return Response(csv, mimetype='text/csv',
                        headers={'Content-Disposition': f'attachment; filename=report_{report_id}.csv'})
    except Exception as e:
        return db_error(e)


# ─────────────────────────────────────────
# FLAGS, FRAUD & CREDIT SCORE
# ─────────────────────────────────────────
@app.route('/api/flagged-transactions', methods=['GET'])
@require_admin
def get_flagged_transactions():
    try:
        cursor = mysql.connection.cursor(MySQLdb.cursors.DictCursor)
        cursor.execute("""
            SELECT ft.flag_id, ft.transaction_id, ft.reason, ft.flagged_at, ft.reviewed,
                   t.amount, t.transaction_type, t.description, u.full_name
            FROM Flagged_Transactions ft
            JOIN Transactions t ON ft.transaction_id = t.transaction_id
            JOIN Accounts a     ON t.account_id      = a.account_id
            JOIN Users u        ON a.user_id         = u.user_id
            ORDER BY ft.flagged_at DESC
        """)
        rows = cursor.fetchall()
        cursor.close()
        return jsonify({'success': True, 'count': len(rows), 'data': rows})
    except Exception as e:
        return db_error(e)


@app.route('/api/review-flag/<int:flag_id>', methods=['POST'])
@require_admin
def review_flag(flag_id):
    try:
        cursor = mysql.connection.cursor()
        cursor.execute("UPDATE Flagged_Transactions SET reviewed=TRUE WHERE flag_id=%s", (flag_id,))
        mysql.connection.commit()
        cursor.close()
        return jsonify({'success': True})
    except Exception as e:
        return db_error(e)


@app.route('/api/total/<int:account_id>/<string:trans_type>', methods=['GET'])
@require_auth
def get_total(account_id, trans_type):
    if not owns_account(account_id):          # FIX: ownership check
        return forbidden()
    try:
        cursor = mysql.connection.cursor(MySQLdb.cursors.DictCursor)
        cursor.execute("SELECT CalculateTotalByType(%s,%s) AS total", (account_id, trans_type))
        result = cursor.fetchone()
        cursor.close()
        return jsonify({'success': True, 'account_id': account_id,
                        'type': trans_type, 'total': str(result['total'])})
    except Exception as e:
        return db_error(e)


@app.route('/api/account-summary/<int:account_id>', methods=['GET'])
@require_auth
def account_summary(account_id):
    if not owns_account(account_id):          # FIX: ownership check
        return forbidden()
    try:
        cursor = mysql.connection.cursor(MySQLdb.cursors.DictCursor)
        rows = call_procedure(cursor, 'GetAccountSummary', [account_id])
        cursor.close()
        return jsonify({'success': True, 'data': rows})
    except Exception as e:
        return db_error(e)


@app.route('/api/fraud-flags', methods=['GET'])
@require_admin
def get_fraud_flags():
    try:
        cursor = mysql.connection.cursor(MySQLdb.cursors.DictCursor)
        # FIX: also return the transaction amount/type the Fraud page displays
        cursor.execute("""
            SELECT ff.*, u.full_name, u.email,
                   t.amount AS transaction_amount, t.transaction_type
            FROM Fraud_Flags ff
            JOIN Users u             ON ff.user_id        = u.user_id
            LEFT JOIN Transactions t ON ff.transaction_id = t.transaction_id
            ORDER BY ff.flagged_at DESC
        """)
        rows = cursor.fetchall()
        cursor.close()
        return jsonify({'success': True, 'count': len(rows), 'data': rows})
    except Exception as e:
        return db_error(e)


@app.route('/api/run-fraud-scan', methods=['POST'])
@require_admin
def run_fraud_scan():
    """NEW: run the inactive-user fraud check now (it also runs daily via a MySQL EVENT)."""
    try:
        cursor = mysql.connection.cursor(MySQLdb.cursors.DictCursor)
        rows = call_procedure(cursor, 'DetectInactiveUsers', [])
        mysql.connection.commit()
        cursor.close()
        flagged = int(rows[0]['users_flagged']) if rows else 0
        return jsonify({'success': True, 'flagged': flagged,
                        'message': f'Scan complete: {flagged} new inactive user(s) flagged'})
    except Exception as e:
        return db_error(e)


@app.route('/api/review-fraud/<int:fraud_id>', methods=['POST'])
@require_admin
def review_fraud_flag(fraud_id):
    try:
        cursor = mysql.connection.cursor()
        cursor.execute("UPDATE Fraud_Flags SET reviewed=TRUE WHERE fraud_id=%s", (fraud_id,))
        mysql.connection.commit()
        cursor.close()
        return jsonify({'success': True, 'message': 'Fraud flag reviewed'})
    except Exception as e:
        return db_error(e)


@app.route('/api/credit-score/<int:user_id>', methods=['GET'])
@require_auth
def get_credit_score(user_id):
    if not is_self(user_id):
        return forbidden()
    try:
        cursor = mysql.connection.cursor(MySQLdb.cursors.DictCursor)
        cursor.execute("SELECT CalculateCreditScore(%s) AS score", (user_id,))
        score = int(cursor.fetchone()['score'])
        cursor.execute("SELECT full_name FROM Users WHERE user_id=%s", (user_id,))
        user = cursor.fetchone()
        cursor.close()
        return jsonify({
            'success':   True,
            'score':     score,
            'user_name': user['full_name'] if user else 'Unknown',
            'rating':    'Excellent' if score >= 750 else 'Good' if score >= 650
                         else 'Fair' if score >= 500 else 'Poor'
        })
    except Exception as e:
        return db_error(e)


@app.route('/health')
def health():
    """Simple health check — useful later for the AWS load balancer."""
    try:
        cursor = mysql.connection.cursor()
        cursor.execute("SELECT 1")
        cursor.close()
        return jsonify({'status': 'ok', 'database': 'connected'})
    except Exception as e:
        return jsonify({'status': 'error', 'database': str(e)}), 503


if __name__ == '__main__':
    # FIX: debug mode and port now come from .env
    app.run(host=os.getenv('FLASK_HOST', '127.0.0.1'),
            port=int(os.getenv('FLASK_PORT', 5000)),
            debug=os.getenv('FLASK_DEBUG', '0') == '1')
