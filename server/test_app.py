import concurrent.futures
import hashlib
import json
import tempfile
import threading
import time
import unittest
import urllib.error
import urllib.request
from http.server import ThreadingHTTPServer
from pathlib import Path
from app import ApiError, Store, make_handler


class RoomTests(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.store = Store(Path(self.directory.name) / 'test.sqlite3')
        self.alice = self.register('alice')
        self.bob = self.register('bob')

    def tearDown(self):
        self.directory.cleanup()

    def register(self, name):
        return self.store.request('POST', '/register', {'name': name, 'email': f'{name}@example.com', 'password': 'long-password'}, '')

    def call(self, path, data=None, user=None):
        return self.store.request('GET' if data is None else 'POST', path, data or {}, (user or self.alice)['token'])

    def group(self):
        room = self.call('/rooms', {'kind': 'group'})
        self.call('/join', {'code': room['code']}, self.bob)
        return room

    def test_credentials_and_revocation(self):
        with self.store.connect() as db:
            stored = db.execute('SELECT password FROM users LIMIT 1').fetchone()[0]
            self.assertNotEqual(stored, 'long-password')
            self.assertIsNone(db.execute('SELECT 1 FROM sessions WHERE token=?', (self.alice['token'],)).fetchone())
        with self.assertRaises(ApiError) as error:
            self.call('/login', {'email': 'alice@example.com', 'password': 'wrong-password'})
        self.assertEqual(error.exception.status, 401)
        self.call('/logout', {})
        with self.assertRaises(ApiError) as error:
            self.call('/rooms', {'kind': 'solo'})
        self.assertEqual(error.exception.status, 401)
        result = self.call('/login', {'email': 'ALICE@example.com', 'password': 'long-password'})
        self.assertEqual(result['user']['id'], self.alice['user']['id'])

    def test_two_people_share_chat_and_room(self):
        room = self.group()
        self.call('/messages', {'body': 'Working on calculus.'})
        snapshot = self.call('/room', user=self.bob)
        self.assertEqual(snapshot['code'], room['code'])
        self.assertEqual(len(snapshot['members']), 2)
        self.assertEqual(snapshot['messages'][0]['body'], 'Working on calculus.')
        self.call('/leave', {}, self.bob)
        self.assertEqual(len(self.call('/room')['members']), 1)
        with self.assertRaises(ApiError):
            self.call('/messages', {'body': 'Outside the room'}, self.bob)

    def test_chat_isolation_and_solo_privacy(self):
        room = self.call('/rooms', {'kind': 'solo'})
        with self.assertRaises(ApiError):
            self.call('/join', {'code': room['code']}, self.bob)
        self.call('/messages', {'body': 'Private note'})
        self.call('/rooms', {'kind': 'group'}, self.bob)
        self.assertEqual(self.call('/room', user=self.bob)['messages'], [])

    def test_break_visibility_countdown_and_stopwatch(self):
        self.group()
        self.call('/break', {'active': True, 'seconds': 300, 'share': False})
        own = next(m for m in self.call('/room')['members'] if m['id'] == self.alice['user']['id'])
        other = next(m for m in self.call('/room', user=self.bob)['members'] if m['id'] == self.alice['user']['id'])
        self.assertIsNotNone(own['break_start'])
        self.assertIsNone(other['break_start'])
        self.assertIsNone(other['break_seconds'])
        self.call('/break', {'active': True, 'seconds': 300, 'share': True})
        other = next(m for m in self.call('/room', user=self.bob)['members'] if m['id'] == self.alice['user']['id'])
        self.assertIsNotNone(other['break_start'])
        with self.store.connect() as db:
            db.execute('UPDATE members SET break_start=? WHERE user_id=?', (time.time() - 301, self.alice['user']['id']))
        own = next(m for m in self.call('/room')['members'] if m['id'] == self.alice['user']['id'])
        self.assertIsNone(own['break_start'])
        self.call('/break', {'active': True, 'seconds': 0, 'share': True})
        with self.store.connect() as db:
            db.execute('UPDATE members SET break_start=? WHERE user_id=?', (time.time() - 7200, self.alice['user']['id']))
        own = next(m for m in self.call('/room')['members'] if m['id'] == self.alice['user']['id'])
        self.assertIsNotNone(own['break_start'])
        self.call('/break', {'active': False})
        own = next(m for m in self.call('/room')['members'] if m['id'] == self.alice['user']['id'])
        self.assertIsNone(own['break_start'])

    def test_matchmaking_does_not_join_private_rooms(self):
        private = self.call('/rooms', {'kind': 'group'})
        public = self.call('/random', {}, self.bob)
        self.assertNotEqual(private['code'], public['code'])
        self.assertEqual(self.call('/random', {})['code'], public['code'])

    def test_capacity_is_atomic_under_simultaneous_joins(self):
        room = self.call('/rooms', {'kind': 'group'})
        users = [self.bob] + [self.register(f'user{i}') for i in range(8)]
        def join(user):
            try:
                self.call('/join', {'code': room['code']}, user)
                return True
            except ApiError as error:
                self.assertEqual(error.status, 409)
                return False
        with concurrent.futures.ThreadPoolExecutor(max_workers=9) as pool:
            self.assertEqual(sum(pool.map(join, users)), 7)
        self.assertEqual(len(self.call('/room')['members']), 8)

    def test_stale_members_and_expired_sessions(self):
        room = self.group()
        with self.store.connect() as db:
            db.execute('UPDATE members SET seen=? WHERE user_id=?', (time.time() - 91, self.bob['user']['id']))
        self.assertEqual(len(self.call('/room')['members']), 1)
        self.call('/leave', {})
        with self.assertRaises(ApiError):
            self.call('/join', {'code': room['code']}, self.bob)
        with self.store.connect() as db:
            db.execute('UPDATE sessions SET expires=0 WHERE token=?', (hashlib.sha256(self.alice['token'].encode()).hexdigest(),))
        with self.assertRaises(ApiError) as error:
            self.call('/rooms', {'kind': 'group'})
        self.assertEqual(error.exception.status, 401)

    def test_input_validation(self):
        self.call('/rooms', {'kind': 'group'})
        for body in ['', ' ' * 10, 'x' * 1001]:
            with self.assertRaises(ApiError): self.call('/messages', {'body': body})
        for duration in [-1, 3601, 'five', True]:
            with self.assertRaises(ApiError): self.call('/break', {'active': True, 'seconds': duration})
        with self.assertRaises(ApiError): self.register('alice')

    def test_http_transport_and_bad_payload(self):
        server = ThreadingHTTPServer(('127.0.0.1', 0), make_handler(self.store))
        thread = threading.Thread(target=server.serve_forever, daemon=True)
        thread.start()
        try:
            base = f'http://127.0.0.1:{server.server_port}'
            request = urllib.request.Request(base + '/rooms', data=b'{"kind":"group"}', headers={'Authorization': 'Bearer ' + self.alice['token'], 'Content-Type': 'application/json'})
            with urllib.request.urlopen(request) as response:
                self.assertEqual(json.load(response)['kind'], 'group')
            with self.assertRaises(urllib.error.HTTPError) as error:
                urllib.request.urlopen(urllib.request.Request(base + '/messages', data=b'[]'))
            self.assertEqual(error.exception.code, 400)
            error.exception.close()
        finally:
            server.shutdown()
            server.server_close()
            thread.join()


if __name__ == '__main__':
    unittest.main()
