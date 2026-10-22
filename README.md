# Chainlink

A Flutter Android app for studying alone, alongside new people, or with friends using a room code. Includes a responsive web preview and a Python/SQLite development backend.

## Implemented

- Email/password registration, login, and server-side logout; display names.
- Private solo sessions, private group rooms, and random matching into open rooms.
- Six-character room codes, copyable invites, and Android `chainlink://join?code=ABC234` links. Invites prefill the join field after login; joining requires a tap.
- Up to eight members in group rooms; room membership, messages, and break status refresh every two seconds.
- Room text chat, with personal notification volume and mute controls.
- Five-, ten-, and fifteen-minute break countdowns or an open-ended stopwatch. Countdown breaks end automatically.
- Optional break sharing. Private break timestamps are omitted from other members’ API responses. Shared breaks appear as an in-app notification and member status.
- An original bundled 24-second lo-fi loop with play/pause, volume, and mute. Music controls affect only the current listener.

## Run locally

Requires Flutter with Dart 3.13.2 or compatible newer versions, Python 3.10+, and the Android SDK for Android builds.

Start the backend from this directory:

```sh
python3 server/app.py
```

In another terminal:

```sh
flutter pub get
flutter run
```

The Android emulator uses `http://10.0.2.2:8080`. The browser preview uses `http://127.0.0.1:8080`. The settings button on the login screen lets you change the server address for the current app session. You can set a build default with `--dart-define=API_URL=https://your-server.example`.

### Two physical phones

Start `python3 server/app.py --host 0.0.0.0`, connect the computer and phones to the same trusted Wi-Fi, and set both apps’ server address to `http://YOUR_COMPUTER_LAN_IP:8080`. Allow the local Python server through the computer’s firewall if needed. Create separate accounts, create a room on one phone, and enter its code on the other. HTTP is allowed only in Android debug builds; release builds require HTTPS.

### Browser preview

```sh
flutter build web --no-wasm-dry-run
python3 -m http.server 8090 --bind 127.0.0.1 --directory build/web
```

Open `http://127.0.0.1:8090`. Open two tabs to test two accounts. Browser invite links use the preview’s current origin; a localhost link is only usable on the same computer. Android custom-scheme invites require Chainlink installed and both devices configured to the same backend.

### Android APK

With an Android SDK and Java 17+ configured:

```sh
flutter doctor
flutter build apk --debug
```

The APK is written to `build/app/outputs/flutter-apk/app-debug.apk`. Release signing has not been configured; the generated Flutter release config still uses the development signing key.

## Verify

```sh
flutter analyze
flutter test
python3 -m unittest discover -s server -v
flutter build web --no-wasm-dry-run
```

The backend tests cover two-user chat, access isolation, break privacy/expiry, random matching, concurrent room capacity, stale presence, input validation, HTTP transport, password hashing, and session revocation. Flutter tests cover invite parsing, authentication errors, logout, and a stale-poll race during room transitions. UI layout/interaction tests run at phone width.

## Architecture

- `lib/main.dart`: Material UI, audio controls, invite handling, and break display.
- `lib/study_session.dart`: HTTP API client and session controller; prevents stale polls from overwriting later actions.
- `server/app.py`: development HTTP API, transactional SQLite membership, salted PBKDF2 password hashes, hashed expiring bearer tokens.
- `tools/generate_audio.py`: reproducible synthesis for the original audio assets; no external music service or downloaded recordings.

The database is `server/chainlink.sqlite3` (gitignored). Accounts persist there. The app keeps login tokens and listening preferences in memory, so restarting the app requires login again. Sessions expire after seven days. One account has one room membership; use separate accounts for separate people. Presence expires after 90 seconds without polling, including when Android suspends the app. Empty rooms and their chat history are removed; the UI returns the latest 100 messages per room.

## Scope of this first version

This backend is for local development and small-group testing, not public production hosting. Before public release, add managed deployment with HTTPS, auth rate limiting, email verification/password recovery, abuse reporting/moderation, retention policies, secure persistent login, and production signing. Break/chat notifications are in-app; there are no background push notifications or voice chat. “Chat volume” controls the text-message notification sound. Music is personal playback of one bundled loop, not a synchronized third-party music bot. Random matching currently uses available room capacity, without subject or preference filters.

Integration references: [Flutter networking](https://docs.flutter.dev/cookbook/networking/send-data), [audioplayers](https://pub.dev/packages/audioplayers), and [app_links](https://pub.dev/packages/app_links).

## Interface decisions

The interface uses white, charcoal, and a small blue accent for links and status. The home screen prioritizes room-code entry, followed by three direct actions. Study and Chat have separate tabs; break and notification settings appear when requested. Copy names the action or state without motivational slogans. Decorative heroes, orbit graphics, promotional feature cards, colored panels, and pill-shaped status badges have been removed.

Research used for this revision: [NN/g on aesthetic and minimalist design](https://www.nngroup.com/articles/aesthetic-minimalist-design/) and [visual hierarchy](https://www.nngroup.com/articles/visual-hierarchy-ux-definition/). Both support reducing irrelevant content and using hierarchy to prioritize useful controls. The [InterfaceKit critique of generated interfaces](https://blog.interfacekit.io/what-makes-a-website-look-ai-generated) also emphasizes product-specific structure and reviewing real interactions, rather than treating any individual color or component as inherently wrong.

## Flashcards

Flashcards are available from home and inside solo/group sessions. Create, edit, and delete personal sets with an optional subject and up to 50 question/answer cards. Sets persist per account in SQLite, independently of rooms. Review hides answers until revealed and supports self-assessed recall, shuffled restarts, a per-round score, and practice of missed cards. Scores are session-only; sets remain private to their owner.
