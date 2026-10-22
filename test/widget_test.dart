import 'dart:convert';

import 'package:chainlink/main.dart';
import 'package:chainlink/study_session.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(
      const MethodChannel('xyz.luan/audioplayers.global'),
      (_) async => null,
    );
    messenger.setMockMethodCallHandler(
      const MethodChannel('xyz.luan/audioplayers.global/events'),
      (_) async => null,
    );
    messenger.setMockMethodCallHandler(
      const MethodChannel('xyz.luan/audioplayers'),
      (call) async {
        if (call.method == 'create') {
          final id = (call.arguments as Map)['playerId'];
          messenger.setMockMethodCallHandler(
            MethodChannel('xyz.luan/audioplayers/events/$id'),
            (_) async => null,
          );
        }
        return null;
      },
    );
  });

  testWidgets(
    'phone sign-up validates empty fields without calling the server',
    (tester) async {
      tester.view.physicalSize = const Size(320, 740);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      var requests = 0;
      final session = StudySession(
        api: StudyApi(
          client: MockClient((_) async {
            requests++;
            return http.Response('{}', 500);
          }),
        ),
      );
      await tester.pumpWidget(ChainlinkApp(session: session));
      await tester.ensureVisible(find.text('Sign up'));
      await tester.tap(find.text('Sign up'));
      await tester.pump();
      expect(find.text('Enter your name.'), findsOneWidget);
      expect(find.text('Enter a valid email.'), findsOneWidget);
      expect(requests, 0);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      session.dispose();
    },
  );

  testWidgets('phone room supports break controls and chat without overflow', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 740);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final me = <String, dynamic>{
      'id': 'a',
      'name': 'Alex',
      'break_start': null,
      'break_seconds': 300,
      'share_break': true,
    };
    final room = <String, dynamic>{
      'code': 'ABC234',
      'kind': 'group',
      'server_time': DateTime.now().millisecondsSinceEpoch / 1000,
      'members': [me],
      'messages': [],
    };
    final session =
        StudySession(
            api: StudyApi(
              client: MockClient((request) async {
                if (request.url.path == '/break') {
                  final body = jsonDecode(request.body) as Map;
                  me['break_start'] = body['active'] == true
                      ? DateTime.now().millisecondsSinceEpoch / 1000
                      : null;
                  me['break_seconds'] = body['seconds'];
                  me['share_break'] = body['share'];
                }
                return http.Response(jsonEncode(room), 200);
              }),
            ),
          )
          ..user = {'id': 'a', 'name': 'Alex'}
          ..room = room;
    await tester.pumpWidget(ChainlinkApp(session: session));
    await tester.pump();
    await tester.ensureVisible(find.text('Take a break'));
    await tester.tap(find.text('Take a break'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Start break'));
    await tester.pumpAndSettle();
    expect(find.text('End break'), findsOneWidget);
    expect(find.text('05:00'), findsOneWidget);
    expect(find.text('On break'), findsOneWidget);
    await tester.tap(find.text('Chat'));
    await tester.pumpAndSettle();
    await tester.pump();
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    session.dispose();
  });
}
