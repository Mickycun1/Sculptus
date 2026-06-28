import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sculptus/main.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<void> signInForTest(WidgetTester tester) async {
  await tester.enterText(
    find.byKey(const ValueKey('authEmailField')),
    'mick@example.com',
  );
  await tester.tap(find.byKey(const ValueKey('authContinueButton')));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('Sculptus opens to the daily prompts', (tester) async {
    SharedPreferences.setMockInitialValues({});

    await tester.pumpWidget(const SculptusApp());
    await tester.pumpAndSettle();
    await signInForTest(tester);

    expect(find.text('Sculptus'), findsOneWidget);
    expect(find.text('Did you workout?'), findsOneWidget);
    expect(find.text('Steps'), findsOneWidget);
    await tester.drag(find.byType(ListView).first, const Offset(0, -500));
    await tester.pumpAndSettle();
    expect(find.text('What have you eaten?'), findsOneWidget);
  });

  test('food estimator handles a real daily log', () {
    final estimate = estimateFoodText('''
Worked out at CrossFit, burned 300 cals. Walked 12k steps.

Food:
2x small pink lady apples
Mexican bowl with 150g Greek yogurt (800 cals)
400g cantaloupe melon
10 drumstick chicken wings
one spring roll and one fried dumpling
''');

    expect(
      estimate.items.map((item) => item.name),
      contains('2 x small apple'),
    );
    expect(
      estimate.items.map((item) => item.name),
      contains('10 x chicken wing'),
    );
    expect(estimate.calories, greaterThan(1800));
    expect(estimate.calories, lessThan(2400));
  });

  testWidgets('food dialog can save without a framework exception', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});

    await tester.pumpWidget(const SculptusApp());
    await tester.pumpAndSettle();
    await signInForTest(tester);

    await tester.tap(find.byIcon(Icons.edit_note).last);
    await tester.pumpAndSettle();

    await tester.tap(find.text('Food').last);
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField).at(0), 'Banana');
    await tester.enterText(find.byType(TextField).at(1), '105');
    await tester.enterText(find.byType(TextField).at(2), '1');

    await tester.tap(find.widgetWithText(FilledButton, 'Add'));
    await tester.pumpAndSettle();
    await tester.drag(find.byType(ListView).first, const Offset(0, -500));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('Banana'), findsOneWidget);
  });

  testWidgets('workout dialog does not ask for steps', (tester) async {
    SharedPreferences.setMockInitialValues({});

    await tester.pumpWidget(const SculptusApp());
    await tester.pumpAndSettle();
    await signInForTest(tester);

    await tester.tap(find.text('Log').first);
    await tester.pumpAndSettle();

    expect(find.text('Did You Workout?'), findsOneWidget);
    expect(find.text('Steps so far'), findsNothing);
    expect(find.text('Calories burned'), findsOneWidget);
  });

  testWidgets('steps dialog logs current and projected steps', (tester) async {
    SharedPreferences.setMockInitialValues({});

    await tester.pumpWidget(const SculptusApp());
    await tester.pumpAndSettle();
    await signInForTest(tester);

    await tester.tap(find.text('Log').at(1));
    await tester.pumpAndSettle();

    await tester.tap(find.text('5k now'));
    await tester.tap(find.text('12k guess'));
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('5000 at'), findsNothing);
    expect(find.textContaining('5000 at'), findsOneWidget);
    expect(find.text('12000 projected'), findsOneWidget);
  });

  testWidgets('weight screen exposes WHOOP sync controls', (tester) async {
    SharedPreferences.setMockInitialValues({});

    await tester.pumpWidget(const SculptusApp());
    await tester.pumpAndSettle();
    await signInForTest(tester);

    await tester.tap(find.text('Weight'));
    await tester.pumpAndSettle();

    expect(find.text('WHOOP'), findsOneWidget);
    expect(find.text('Sync day'), findsOneWidget);
    expect(find.text('Backend'), findsOneWidget);
    expect(find.text('http://127.0.0.1:8787'), findsOneWidget);
  });

  test('WHOOP sync imports selected-day workout burn', () async {
    SharedPreferences.setMockInitialValues({});
    final state = SculptusState();
    await state.load();

    final date = DateTime(2026, 6, 28);
    await state.applyWhoopSnapshot(
      WhoopSnapshot(
        connected: true,
        summaryDate: date,
        profileName: 'Mick',
        todayWorkoutCalories: 375,
        todayWorkoutCount: 1,
        todayWorkoutMinutes: 48,
        latestWorkoutName: 'functional fitness',
        steps: 12000,
        stepsSource: 'cycle.steps',
      ),
    );

    expect(state.activityBurnFor(date), 375);
    expect(state.activitiesFor(date).single.name, 'WHOOP functional fitness');
    expect(state.stepsFor(date), 12000);
    expect(state.stepBurnFor(date), 600);
    expect(
      state.stepEntriesFor(date).single.notes,
      'Imported from WHOOP cycle.steps.',
    );
  });

  testWidgets('food estimator dialog can log pasted food text', (tester) async {
    SharedPreferences.setMockInitialValues({});

    await tester.pumpWidget(const SculptusApp());
    await tester.pumpAndSettle();
    await signInForTest(tester);

    await tester.drag(find.byType(ListView).first, const Offset(0, -500));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Estimate').last);
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byType(TextField).first,
      '2x small pink lady apples\n10 drumstick chicken wings\none spring roll',
    );
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(FilledButton, 'Log estimate'));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('Food estimate'), findsOneWidget);
  });
}
