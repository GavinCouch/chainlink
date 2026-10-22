"""Chainlink development API. Python 3.10+, no third-party dependencies."""
import argparse
from contextlib import contextmanager
import hashlib
import hmac
import json
import re
import secrets
import sqlite3
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path


class ApiError(Exception):
    def __init__(self, status, message):
        self.status, self.message = status, message


def require(condition, message, status=400):
    if not condition:
        raise ApiError(status, message)


def password_hash(password, salt):
    return hashlib.pbkdf2_hmac('sha256', password.encode(), salt.encode(), 210000).hex()


class Store:
    def __init__(self, path):
        self.path = str(path)
        with self.connect() as db:
            db.executescript('''
                PRAGMA journal_mode=WAL;
                CREATE TABLE IF NOT EXISTS users (
                    id TEXT PRIMARY KEY, name TEXT NOT NULL, email TEXT UNIQUE NOT NULL,
                    salt TEXT NOT NULL, password TEXT NOT NULL);
                CREATE TABLE IF NOT EXISTS sessions (
                    token TEXT PRIMARY KEY, user_id TEXT NOT NULL, expires REAL NOT NULL);
                CREATE TABLE IF NOT EXISTS rooms (
                    code TEXT PRIMARY KEY, kind TEXT NOT NULL, created REAL NOT NULL);
                CREATE TABLE IF NOT EXISTS members (
                    user_id TEXT PRIMARY KEY, code TEXT NOT NULL, seen REAL NOT NULL,
                    break_start REAL, break_seconds INTEGER, share_break INTEGER DEFAULT 1);
                CREATE TABLE IF NOT EXISTS messages (
                    id INTEGER PRIMARY KEY AUTOINCREMENT, code TEXT NOT NULL,
                    user_id TEXT NOT NULL, name TEXT NOT NULL, body TEXT NOT NULL, created REAL NOT NULL);
            ''')

    @contextmanager
    def connect(self):
        db = sqlite3.connect(self.path, timeout=15)
        db.row_factory = sqlite3.Row
        try:
            with db:
                yield db
        finally:
            db.close()

    def request(self, method, path, data, token):
        now = time.time()
        with self.connect() as db:
            # Serialize room-capacity checks and membership changes across devices.
            db.execute('BEGIN IMMEDIATE')
            db.execute('DELETE FROM sessions WHERE expires < ?', (now,))
            db.execute('DELETE FROM members WHERE seen < ?', (now - 90,))
            db.execute('DELETE FROM rooms WHERE code NOT IN (SELECT code FROM members)')
            db.execute('DELETE FROM messages WHERE code NOT IN (SELECT code FROM rooms)')
            if method == 'GET' and path == '/health':
                return {'status': 'ok'}
            if method == 'POST' and path in ('/register', '/login'):
                email = str(data.get('email', '')).strip().lower()
                password = str(data.get('password', ''))
                require(re.fullmatch(r'[^\s@]+@[^\s@]+\.[^\s@]+', email) and len(email) <= 254,
                        'Enter a valid email address.')
                require(8 <= len(password) <= 128, 'Use a password with 8–128 characters.')
                if path == '/register':
                    name = str(data.get('name', '')).strip()
                    require(1 <= len(name) <= 30, 'Your display name must be 1–30 characters.')
                    require(db.execute('SELECT 1 FROM users WHERE email=?', (email,)).fetchone() is None,
                            'An account with this email already exists.', 409)
                    salt = secrets.token_hex(16)
                    db.execute('INSERT INTO users VALUES (?, ?, ?, ?, ?)',
                               (secrets.token_hex(16), name, email, salt, password_hash(password, salt)))
                user = db.execute('SELECT * FROM users WHERE email=?', (email,)).fetchone()
                candidate = password_hash(password, user['salt'] if user else 'unknown-account')
                require(user is not None and hmac.compare_digest(user['password'], candidate),
                        'Email or password is incorrect.', 401)
                access = secrets.token_urlsafe(32)
                db.execute('INSERT INTO sessions VALUES (?, ?, ?)',
                           (hashlib.sha256(access.encode()).hexdigest(), user['id'], now + 604800))
                return {'token': access, 'user': {'id': user['id'], 'name': user['name']}}

            digest = hashlib.sha256(token.encode()).hexdigest()
            user = db.execute('SELECT users.* FROM users JOIN sessions ON users.id=sessions.user_id '
                              'WHERE sessions.token=?', (digest,)).fetchone()
            require(user is not None, 'Please log in again.', 401)
            uid = user['id']
            # Discover only open public rooms, never private/solo room codes.
            if method == 'GET' and path == '/public-rooms':
                rows = db.execute('''
                    SELECT rooms.code, COUNT(members.user_id) AS members
                    FROM rooms JOIN members ON rooms.code = members.code
                    WHERE rooms.kind = 'random'
                    GROUP BY rooms.code
                    HAVING COUNT(members.user_id) < 8
                    ORDER BY rooms.created DESC LIMIT 20
                ''').fetchall()
                return {'rooms': [dict(row) for row in rows]}
            if method == 'POST' and path == '/logout':
                db.execute('DELETE FROM sessions WHERE token=?', (digest,))
                db.execute('DELETE FROM members WHERE user_id=?', (uid,))
                return {'ok': True}
            if method == 'POST' and path == '/leave':
                db.execute('DELETE FROM members WHERE user_id=?', (uid,))
                return {'ok': True}
            if method == 'POST' and path in ('/rooms', '/join', '/random'):
                code = None
                if path == '/join':
                    code = str(data.get('code', '')).strip().upper()
                    room = db.execute('SELECT * FROM rooms WHERE code=? AND kind != ?', (code, 'solo')).fetchone()
                    require(room is not None, 'Room not found. Check the code or ask for a new invite.', 404)
                elif path == '/random':
                    room = db.execute('SELECT rooms.code FROM rooms JOIN members USING(code) '
                                      'WHERE kind=? GROUP BY code HAVING COUNT(*) < 8 ORDER BY created LIMIT 1',
                                      ('random',)).fetchone()
                    if room:
                        code = room['code']
                if code is None:
                    kind = 'random' if path == '/random' else data.get('kind', 'group')
                    require(kind in ('solo', 'group', 'random'), 'Unknown room type.')
                    while True:
                        code = ''.join(secrets.choice('ABCDEFGHJKLMNPQRSTUVWXYZ23456789') for _ in range(6))
                        if db.execute('SELECT 1 FROM rooms WHERE code=?', (code,)).fetchone() is None:
                            break
                    db.execute('INSERT INTO rooms VALUES (?, ?, ?)', (code, kind, now))
                count = db.execute('SELECT COUNT(*) FROM members WHERE code=? AND user_id != ?', (code, uid)).fetchone()[0]
                require(count < 8, 'This room is full. Try another room.', 409)
                db.execute('INSERT OR REPLACE INTO members(user_id, code, seen) VALUES (?, ?, ?)', (uid, code, now))
                return self.snapshot(db, uid, now)
            member = db.execute('SELECT * FROM members WHERE user_id=?', (uid,)).fetchone()
            require(member is not None, 'Your room session ended. Join again to continue.', 404)
            db.execute('UPDATE members SET seen=? WHERE user_id=?', (now, uid))
            if method == 'POST' and path == '/messages':
                body = str(data.get('body', '')).strip()
                require(1 <= len(body) <= 1000, 'Messages must be 1–1000 characters.')
                last = db.execute('SELECT MAX(created) FROM messages WHERE user_id=?', (uid,)).fetchone()[0]
                require(last is None or now - last >= 0.5, 'Wait a moment before sending another message.', 429)
                db.execute('INSERT INTO messages(code, user_id, name, body, created) VALUES (?, ?, ?, ?, ?)',
                           (member['code'], uid, user['name'], body, now))
            elif method == 'POST' and path == '/break':
                active = data.get('active')
                duration = data.get('seconds', 300)
                share = data.get('share', True)
                require(type(active) is bool and type(share) is bool, 'Invalid break options.')
                require(type(duration) is int and 0 <= duration <= 3600, 'Break duration must be 0–3600 seconds.')
                db.execute('UPDATE members SET break_start=?, break_seconds=?, share_break=? WHERE user_id=?',
                           (now if active else None, duration, int(share), uid))
            elif method != 'GET' or path != '/room':
                raise ApiError(404, 'Endpoint not found.')
            return self.snapshot(db, uid, now)

    def snapshot(self, db, uid, now):
        member = db.execute('SELECT * FROM members WHERE user_id=?', (uid,)).fetchone()
        code = member['code']
        db.execute('UPDATE members SET break_start=NULL WHERE code=? AND break_seconds>0 '
                   'AND break_start + break_seconds <= ?', (code, now))
        room = dict(db.execute('SELECT * FROM rooms WHERE code=?', (code,)).fetchone())
        room['members'] = []
        for row in db.execute('SELECT members.*, users.name FROM members JOIN users ON users.id=members.user_id '
                              'WHERE code=? ORDER BY name', (code,)):
            visible = row['share_break'] or row['user_id'] == uid
            room['members'].append({'id': row['user_id'], 'name': row['name'],
                                    'break_start': row['break_start'] if visible else None,
                                    'break_seconds': row['break_seconds'] if visible else None,
                                    'share_break': bool(row['share_break']) if row['user_id'] == uid else None})
        room['messages'] = [dict(row) for row in db.execute(
            'SELECT * FROM (SELECT id, user_id, name, body, created FROM messages WHERE code=? '
            'ORDER BY id DESC LIMIT 100) ORDER BY id', (code,))]
        room['server_time'] = now
        return room


def make_handler(store):
    class Handler(BaseHTTPRequestHandler):
        def log_message(self, *_):
            pass  # Do not log tokens, email addresses, or message bodies.

        def do_OPTIONS(self):
            self.respond(204, {})

        def do_GET(self):
            self.handle_request()

        def do_POST(self):
            self.handle_request()

        def respond(self, status, payload):
            body = json.dumps(payload).encode()
            self.send_response(status)
            self.send_header('Content-Type', 'application/json')
            self.send_header('Access-Control-Allow-Origin', '*')
            self.send_header('Access-Control-Allow-Headers', 'Authorization, Content-Type')
            self.send_header('Access-Control-Allow-Methods', 'GET, POST, OPTIONS')
            self.send_header('Cache-Control', 'no-store')
            self.send_header('Content-Length', str(len(body)))
            self.end_headers()
            self.wfile.write(body)

        def handle_request(self):
            try:
                size = int(self.headers.get('Content-Length', '0'))
                require(0 <= size <= 16384, 'Request too large.', 413)
                data = json.loads(self.rfile.read(size)) if size else {}
                require(isinstance(data, dict), 'Expected a JSON object.')
                token = self.headers.get('Authorization', '').removeprefix('Bearer ')
                self.respond(200, store.request(self.command, self.path, data, token))
            except ApiError as exc:
                self.respond(exc.status, {'error': exc.message})
            except (ValueError, UnicodeDecodeError):
                self.respond(400, {'error': 'Invalid JSON request.'})
            except Exception:
                self.respond(500, {'error': 'Server error. Please try again.'})

    return Handler


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('--host', default='127.0.0.1')
    parser.add_argument('--port', type=int, default=8080)
    parser.add_argument('--db', default=str(Path(__file__).with_name('chainlink.sqlite3')))
    args = parser.parse_args()
    server = ThreadingHTTPServer((args.host, args.port), make_handler(Store(args.db)))
    print(f'Chainlink API listening at http://{args.host}:{args.port}', flush=True)
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        server.server_close()
