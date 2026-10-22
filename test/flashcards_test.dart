import 'dart:convert';

import 'package:chainlink/flashcards.dart';
import 'package:chainlink/study_session.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  testWidgets('review hides answers, scores recall, and retries missed cards', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 740);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      const MaterialApp(
        home: FlashcardReview(
          set: FlashcardSet(
            title: 'Networks',
            subject: 'CS',
            cards: [
              Flashcard('What does SYN do?', 'Starts a connection.'),
              Flashcard('What is an ACK?', 'An acknowledgment.'),
            ],
          ),
        ),
      ),
    );
    expect(find.text('Starts a connection.'), findsNothing);
    expect(find.text('Got it'), findsNothing);
    await tester.tap(find.text('Show answer'));
    await tester.pump();
    expect(find.text('Starts a connection.'), findsOneWidget);
    await tester.tap(find.text('Practice again'));
    await tester.pump();
    expect(find.text('Card 2 of 2'), findsOneWidget);
    await tester.tap(find.text('Show answer'));
    await tester.pump();
    await tester.tap(find.text('Got it'));
    await tester.pump();
    expect(find.text('1 of 2 remembered'), findsOneWidget);
    await tester.tap(find.text('Practice missed (1)'));
    await tester.pump();
    expect(find.text('Card 1 of 1'), findsOneWidget);
    expect(find.text('What does SYN do?'), findsOneWidget);
    expect(find.text('Starts a connection.'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('editor validates and retains input after a failed save', (
    tester,
  ) async {
    var saves = 0;
    final api = StudyApi(
      client: MockClient((request) async {
        saves++;
        final body = jsonDecode(request.body) as Map;
        expect(body['title'], 'Biology');
        expect(body['cards'][0]['front'], 'Cell?');
        return http.Response('{"error":"Try again later."}', 500);
      }),
    );
    await tester.pumpWidget(MaterialApp(home: FlashcardEditor(api: api)));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Save set'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save set'));
    await tester.pumpAndSettle();
    expect(saves, 0);
    expect(find.text('Enter a set title.'), findsOneWidget);
    final fields = find.byType(TextFormField);
    await tester.enterText(fields.at(0), 'Biology');
    await tester.enterText(fields.at(2), 'Cell?');
    await tester.enterText(fields.at(3), 'The basic unit of life.');
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Save set'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save set'));
    await tester.pumpAndSettle();
    expect(saves, 1);
    expect(find.text('Try again later.'), findsOneWidget);
    expect(find.text('Cell?'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('sets can be created and loaded through the library', (
    tester,
  ) async {
    final sets = <Map<String, dynamic>>[];
    final api = StudyApi(
      client: MockClient((request) async {
        if (request.url.path == '/flashcards/save') {
          final set = jsonDecode(request.body) as Map<String, dynamic>;
          set['id'] = 'set-1';
          sets.add(set);
          return http.Response(jsonEncode({'set': set}), 200);
        }
        return http.Response(jsonEncode({'sets': sets}), 200);
      }),
    );
    await tester.pumpWidget(MaterialApp(home: FlashcardsPage(api: api)));
    await tester.pumpAndSettle();
    expect(find.text('No flashcards yet'), findsOneWidget);
    await tester.tap(find.text('New set'));
    await tester.pumpAndSettle();
    final fields = find.byType(TextFormField);
    await tester.enterText(fields.at(0), 'French');
    await tester.enterText(fields.at(1), 'Languages');
    await tester.enterText(fields.at(2), 'Bonjour');
    await tester.enterText(fields.at(3), 'Hello');
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Save set'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save set'));
    await tester.pumpAndSettle();
    expect(find.text('French'), findsOneWidget);
    expect(find.text('Languages · 1 card'), findsOneWidget);
    await tester.tap(find.text('French'));
    await tester.pumpAndSettle();
    expect(find.text('Bonjour'), findsOneWidget);
    expect(find.text('Hello'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
