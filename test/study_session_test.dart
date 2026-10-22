import 'dart:async';
import 'dart:convert';

import 'package:chainlink/study_session.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  test(
    'room codes accept invites, normalize case, and reject invalid input',
    () {
      expect(roomCodeFrom(' abc234 '), 'ABC234');
      expect(roomCodeFrom('chainlink://join?code=abc234'), 'ABC234');
      expect(roomCodeFrom('https://study.example/?code=XYZ789'), 'XYZ789');
      expect(roomCodeFrom('BAD01I'), isNull);
      expect(roomCodeFrom(''), isNull);
    },
  );
  test(
    'server errors are readable and failed login does not authenticate',
    () async {
      final session = StudySession(
        api: StudyApi(
          client: MockClient(
            (_) async =>
                http.Response('{"error":"Incorrect credentials"}', 401),
          ),
        ),
      );
      expect(await session.authenticate('a@b.com', 'password', null), isFalse);
      expect(session.user, isNull);
      expect(session.error, 'Incorrect credentials');
      session.dispose();
    },
  );
  test('old room poll cannot overwrite a newer room transition', () async {
    final pending = Completer<http.Response>();
    final room = {'code': 'ABC234', 'members': [], 'messages': []};
    final session = StudySession(
      api: StudyApi(
        client: MockClient((request) async {
          if (request.url.path == '/room') return pending.future;
          if (request.url.path == '/leave') return http.Response('{}', 200);
          return http.Response(jsonEncode(room), 200);
        }),
      ),
    );
    await session.join('group');
    final refresh = session.refresh();
    await session.leave();
    pending.complete(http.Response(jsonEncode(room), 200));
    await refresh;
    expect(session.room, isNull);
    session.dispose();
  });
  test('logout revokes bearer token and clears local room', () async {
    String? seenToken;
    final session = StudySession(
      api: StudyApi(
        client: MockClient((request) async {
          if (request.url.path == '/login') {
            return http.Response(
              '{"token":"secret","user":{"id":"1","name":"A"}}',
              200,
            );
          }
          seenToken = request.headers['Authorization'];
          return http.Response('{}', 200);
        }),
      ),
    );
    await session.authenticate('a@b.com', 'password', null);
    await session.logout();
    expect(seenToken, 'Bearer secret');
    expect(session.api.token, isNull);
    expect(session.user, isNull);
    session.dispose();
  });
}
