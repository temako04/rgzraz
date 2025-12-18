from flask import Flask, request, render_template, redirect, url_for, session
import sqlite3
from datetime import datetime, timedelta
from werkzeug.security import generate_password_hash, check_password_hash
from functools import wraps

app = Flask(__name__)
app.secret_key = 'secret_key_123'  # Простой ключ

DATABASE = 'subscriptions.db'

def get_db_connection():
    conn = sqlite3.connect(DATABASE)
    conn.row_factory = sqlite3.Row
    return conn

def init_db():
    conn = get_db_connection()
    cur = conn.cursor()
    
    # Упрощённая таблица пользователей
    cur.execute('''
        CREATE TABLE IF NOT EXISTS users (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            username TEXT UNIQUE NOT NULL,
            password TEXT NOT NULL
        )
    ''')
    
    # Таблица подписок
    cur.execute('''
        CREATE TABLE IF NOT EXISTS subscriptions (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            user_id INTEGER NOT NULL,
            name TEXT NOT NULL,
            amount REAL NOT NULL,
            interval TEXT NOT NULL,
            start_date TEXT NOT NULL,
            next_charge_date TEXT NOT NULL,
            is_active INTEGER DEFAULT 1
        )
    ''')
    
    conn.commit()
    cur.close()
    conn.close()

def calculate_next_charge(start_date_str, interval):
    start_date = datetime.strptime(start_date_str, '%Y-%m-%d')
    
    if interval == 'monthly':
        next_date = start_date + timedelta(days=30)
    elif interval == 'yearly':
        next_date = start_date.replace(year=start_date.year + 1)
    elif interval == 'weekly':
        next_date = start_date + timedelta(days=7)
    else:
        next_date = start_date + timedelta(days=30)
    
    return next_date.strftime('%Y-%m-%d')

init_db()

# ====================================
# ФУНКЦИИ ПОЛЬЗОВАТЕЛЕЙ
# ====================================

def get_user_by_username(username):
    conn = get_db_connection()
    cur = conn.cursor()
    cur.execute('SELECT * FROM users WHERE username = ?', (username,))
    user = cur.fetchone()
    cur.close()
    conn.close()
    return user

def create_user(username, password):
    conn = get_db_connection()
    cur = conn.cursor()
    hashed_password = generate_password_hash(password)
    
    try:
        cur.execute('INSERT INTO users (username, password) VALUES (?, ?)', 
                   (username, hashed_password))
        conn.commit()
        success = True
    except sqlite3.IntegrityError:
        success = False
    finally:
        cur.close()
        conn.close()
    
    return success

# ====================================
# ДЕКОРАТОР
# ====================================

def login_required(f):
    @wraps(f)
    def decorated_function(*args, **kwargs):
        if 'user_id' not in session:
            return redirect('/login')
        return f(*args, **kwargs)
    return decorated_function

# ====================================
# АУТЕНТИФИКАЦИЯ
# ====================================

@app.route('/')
def index():
    if 'user_id' in session:
        return redirect('/subscriptions')
    return render_template('index.html')

@app.route('/register', methods=['GET', 'POST'])
def register():
    if request.method == 'POST':
        username = request.form.get('username')
        password = request.form.get('password')
        
        if not username or not password:
            return render_template('register.html', error='Заполните все поля')
        
        if get_user_by_username(username):
            return render_template('register.html', error='Имя уже занято')
        
        if create_user(username, password):
            return redirect('/login?success=1')
        else:
            return render_template('register.html', error='Ошибка регистрации')
    
    return render_template('register.html')

@app.route('/login', methods=['GET', 'POST'])
def login():
    if request.method == 'POST':
        username = request.form.get('username')
        password = request.form.get('password')
        
        if not username or not password:
            return render_template('login.html', error='Заполните все поля')
        
        user = get_user_by_username(username)
        if not user:
            return render_template('login.html', error='Неверные данные')
        
        if check_password_hash(user['password'], password):
            session['user_id'] = user['id']
            session['username'] = user['username']
            return redirect('/subscriptions')
        else:
            return render_template('login.html', error='Неверные данные')
    
    success = request.args.get('success')
    return render_template('login.html', success=success)

@app.route('/logout')
def logout():
    session.clear()
    return redirect('/')

# ====================================
# ПОДПИСКИ
# ====================================

@app.route('/subscriptions')
@login_required
def view_subscriptions():
    user_id = session['user_id']
    
    conn = get_db_connection()
    cur = conn.cursor()
    
    cur.execute('SELECT * FROM subscriptions WHERE user_id = ? AND is_active = 1 ORDER BY next_charge_date', 
                (user_id,))
    subscriptions = [dict(row) for row in cur.fetchall()]
    
    total_monthly = sum(sub['amount'] for sub in subscriptions if sub['interval'] == 'monthly')
    total_all = sum(sub['amount'] for sub in subscriptions)
    
    cur.close()
    conn.close()
    
    return render_template('subscriptions.html',
                         subscriptions=subscriptions,
                         total_monthly=total_monthly,
                         total_all=total_all,
                         username=session.get('username'))

@app.route('/subscriptions/add', methods=['GET', 'POST'])
@login_required
def add_subscription():
    if request.method == 'POST':
        user_id = session['user_id']
        name = request.form.get('name')
        amount = request.form.get('amount')
        interval = request.form.get('interval')
        start_date = request.form.get('start_date')
        
        if not all([name, amount, interval, start_date]):
            return render_template('add_subscription.html', error='Заполните все поля')
        
        try:
            amount = float(amount)
            datetime.strptime(start_date, '%Y-%m-%d')
            next_charge_date = calculate_next_charge(start_date, interval)
            
            conn = get_db_connection()
            cur = conn.cursor()
            
            cur.execute('''
                INSERT INTO subscriptions (user_id, name, amount, interval, start_date, next_charge_date)
                VALUES (?, ?, ?, ?, ?, ?)
            ''', (user_id, name, amount, interval, start_date, next_charge_date))
            
            conn.commit()
            cur.close()
            conn.close()
            
            return redirect('/subscriptions')
            
        except:
            return render_template('add_subscription.html', error='Ошибка в данных')
    
    return render_template('add_subscription.html')

@app.route('/subscriptions/edit/<int:subscription_id>', methods=['GET', 'POST'])
@login_required
def edit_subscription(subscription_id):
    user_id = session['user_id']
    
    conn = get_db_connection()
    cur = conn.cursor()
    
    cur.execute('SELECT * FROM subscriptions WHERE id = ? AND user_id = ?', (subscription_id, user_id))
    subscription = cur.fetchone()
    
    if not subscription:
        cur.close()
        conn.close()
        return redirect('/subscriptions')
    
    if request.method == 'POST':
        name = request.form.get('name')
        amount = request.form.get('amount')
        interval = request.form.get('interval')
        start_date = request.form.get('start_date')
        
        if not all([name, amount, interval, start_date]):
            cur.close()
            conn.close()
            return render_template('edit_subscription.html',
                                 error='Заполните все поля',
                                 subscription=dict(subscription))
        
        try:
            amount = float(amount)
            datetime.strptime(start_date, '%Y-%m-%d')
            next_charge_date = calculate_next_charge(start_date, interval)
            
            cur.execute('''
                UPDATE subscriptions 
                SET name=?, amount=?, interval=?, start_date=?, next_charge_date=?
                WHERE id=? AND user_id=?
            ''', (name, amount, interval, start_date, next_charge_date, subscription_id, user_id))
            
            conn.commit()
            cur.close()
            conn.close()
            
            return redirect('/subscriptions')
            
        except:
            cur.close()
            conn.close()
            return render_template('edit_subscription.html',
                                 error='Ошибка в данных',
                                 subscription=dict(subscription))
    
    cur.close()
    conn.close()
    
    return render_template('edit_subscription.html', subscription=dict(subscription))

@app.route('/subscriptions/delete/<int:subscription_id>')
@login_required
def delete_subscription(subscription_id):
    user_id = session['user_id']
    
    conn = get_db_connection()
    cur = conn.cursor()
    cur.execute('UPDATE subscriptions SET is_active=0 WHERE id=? AND user_id=?', 
                (subscription_id, user_id))
    conn.commit()
    cur.close()
    conn.close()
    
    return redirect('/subscriptions')

if __name__ == '__main__':
    app.run(debug=True, port=5000)