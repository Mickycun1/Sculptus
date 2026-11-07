import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sculptus/main.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

Widget shadHarness(Widget child) {
  return ShadApp.custom(
    theme: sculptusTheme(Brightness.light),
    appBuilder: (context) => MaterialApp(
      theme: Theme.of(context),
      localizationsDelegates: const [
        GlobalShadLocalizations.delegate,
        DefaultMaterialLocalizations.delegate,
        DefaultWidgetsLocalizations.delegate,
      ],
      builder: (context, child) => ShadAppBuilder(child: child!),
      home: Scaffold(body: child),
    ),
  );
}

class FakeMeals extends MealsApiClient {
  FakeMeals(this.meals) : super('', '');

  List<SavedMeal> meals;

  @override
  Future<List<SavedMeal>> list() async => meals;

  @override
  Future<List<SavedMeal>> remove(String name) async => meals = [
    for (final m in meals)
      if (m.name != name) m,
  ];

  @override
  Future<List<SavedMeal>> save(SavedMeal meal) async =>
      meals = [...meals, meal];

  @override
  Future<MealEstimate> estimate(
    String name,
    String ingredients, {
    int portions = 1,
  }) async => const MealEstimate(
    name: 'Burrito bowl',
    calories: 4800,
    proteinGrams: 360,
    items: [
      SavedMeal(name: '1.2kg chicken thigh', calories: 2400, proteinGrams: 300),
      SavedMeal(name: '600g rice', calories: 2400, proteinGrams: 60),
    ],
    assumption: '',
  );
}

const signedInSession =
    '{"userId":"user_1","email":"mick@example.com","displayName":"Mick '
    'Cunningham","provider":"apple","backendToken":"t","signedInAt":'
    '"2026-11-06T08:00:00.000"}';

Future<SculptusState> pumpScreen(
  WidgetTester tester,
  Widget Function(SculptusState state) builder,
) async {
  SharedPreferences.setMockInitialValues({});
  final state = SculptusState();
  await state.load();
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: AnimatedBuilder(
          animation: state,
          builder: (context, _) => builder(state),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return state;
}

void main() {
  testWidgets('signed out, Sculptus offers Apple and email sign in', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1179, 2556);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    SharedPreferences.setMockInitialValues({});

    await tester.pumpWidget(const SculptusApp());
    await tester.pumpAndSettle();

    expect(find.text('Sculptus'), findsOneWidget);
    expect(find.text('Get started'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('welcomeSignIn')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('authEmailField')), findsOneWidget);
    expect(find.byKey(const ValueKey('authPasswordField')), findsOneWidget);
    expect(find.byKey(const ValueKey('authNameField')), findsNothing);
    await tester.tap(find.text('Create an account'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('authNameField')), findsOneWidget);
    expect(find.text('Create account'), findsOneWidget);
  });

  testWidgets('signed in, Today opens and the avatar opens the profile', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1179, 2556);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    SharedPreferences.setMockInitialValues({
      'sculptus_auth_v1': signedInSession,
      'sculptus_ai_consent_v1': true,
    });

    await tester.pumpWidget(const SculptusApp());
    await tester.pumpAndSettle();

    expect(find.text('What should we call you?'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('setupSkip')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('todayLogField')), findsOneWidget);
    expect(find.text('Log it'), findsOneWidget);
    expect(find.text('MC'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('profileButton')));
    await tester.pumpAndSettle();
    expect(find.text('Profile'), findsOneWidget);
    expect(find.text('Mick Cunningham'), findsOneWidget);
    expect(find.text('Signed in with Apple'), findsOneWidget);
  });

  test('a parsed log becomes food, burn, steps and weight', () async {
    SharedPreferences.setMockInitialValues({});
    final state = SculptusState();
    await state.load();
    final day = DateTime(2026, 10, 22);

    await state.applyLog(
      LoggedDay.fromJson({
        'foods': [
          {
            'name': '3 bananas',
            'calories': 315,
            'caloriesLow': 300,
            'caloriesHigh': 330,
            'proteinGrams': 4,
            'assumption': '',
          },
          {
            'name': '10 mints',
            'calories': 150,
            'caloriesLow': 150,
            'caloriesHigh': 150,
            'proteinGrams': 0,
            'assumption': 'label says 15 kcal each',
          },
        ],
        'workouts': [
          {'name': 'CrossFit', 'caloriesBurned': 523, 'minutes': 29},
        ],
        'steps': 12000,
        'weightLb': 202,
        'question': null,
      }),
      day,
    );

    expect(state.consumedFor(day).calories, 465);
    expect(state.activityBurnFor(day), 523);
    expect(state.stepsFor(day), 12000);
    expect(state.weightTrendFor(day), 202);
    expect(
      state.entriesFor(day).map((entry) => entry.notes),
      contains('150-150 kcal · label says 15 kcal each'),
    );

    await state.applyWhoopSnapshot(
      WhoopSnapshot(
        connected: true,
        summaryDate: day,
        todayWorkoutCalories: 540,
        todayWorkoutCount: 1,
        latestWorkoutName: 'functional fitness',
      ),
    );
    expect(state.activityBurnFor(day), 540);
  });

  test('maintenance and deficit come from profile, burn and steps', () async {
    SharedPreferences.setMockInitialValues({});
    final state = SculptusState();
    await state.load();
    final day = DateTime(2026, 10, 22);

    expect(state.maintenanceFor(day), isNull);

    await state.updateGoals(
      state.goals.copyWith(age: 33, heightInches: 75, sex: 'male'),
    );
    await state.applyLog(
      LoggedDay.fromJson({
        'foods': [
          {
            'name': 'Mexican bowl with 200g Greek yogurt',
            'calories': 700,
            'caloriesLow': 650,
            'caloriesHigh': 750,
            'proteinGrams': 55,
            'assumption': '',
          },
        ],
        'workouts': [
          {'name': 'CrossFit', 'caloriesBurned': 523, 'minutes': 29},
        ],
        'steps': 12000,
        'weightLb': 202.4,
      }),
      day,
    );

    final maintenance = state.maintenanceFor(day)!;
    expect(maintenance, 3176);
    expect(maintenance - state.consumedFor(day).calories, 2476);
  });

  test('considered foods are parsed but not logged as eaten', () async {
    SharedPreferences.setMockInitialValues({});
    final state = SculptusState();
    await state.load();
    final day = DateTime(2026, 11, 1);
    final log = LoggedDay.fromJson({
      'foods': [],
      'considering': [
        {'name': 'Popcorn', 'calories': 150, 'proteinGrams': 4},
      ],
    });

    await state.applyLog(log, day);

    expect(log.considering.single.name, 'Popcorn');
    expect(state.consumedFor(day).calories, 0);
  });

  testWidgets('considering panel shows the deficit after and logs on Ate it', (
    tester,
  ) async {
    LoggedFood? ate;
    const option = LoggedFood(
      name: '200g Greek yogurt + 1/2 scoop whey',
      calories: 170,
      caloriesLow: 150,
      caloriesHigh: 190,
      proteinGrams: 30,
      assumption: '',
    );
    await tester.pumpWidget(
      shadHarness(
        ConsideringPanel(
          options: const [option],
          balance: 768,
          hasMaintenance: true,
          onAte: (food) => ate = food,
        ),
      ),
    );

    expect(find.text('+170 · 30g protein · deficit 598'), findsOneWidget);
    await tester.tap(find.text('Ate it'));
    expect(ate, option);
  });

  testWidgets('My meals lists saved meals and forgets one', (tester) async {
    final client = FakeMeals([
      const SavedMeal(name: 'Mexican bowl', calories: 640, proteinGrams: 48),
      const SavedMeal(name: 'Earth Bowl', calories: 720, proteinGrams: 35),
    ]);
    await tester.pumpWidget(
      shadHarness(MyMealsCard(auth: AuthController(), client: client)),
    );
    await tester.pumpAndSettle();

    expect(find.text('640 kcal · 48g protein'), findsOneWidget);
    await tester.tap(find.text('Mexican bowl'));
    await tester.pumpAndSettle();
    expect(find.text('Edit meal'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('Delete this meal'),
      300,
      scrollable: find
          .descendant(
            of: find.byType(ListView).last,
            matching: find.byType(Scrollable),
          )
          .first,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete this meal'));
    await tester.pumpAndSettle();
    expect(find.text('Mexican bowl'), findsNothing);
    expect(find.text('Earth Bowl'), findsOneWidget);
  });

  test(
    'WHOOP counts by default and the WOD estimate only when chosen',
    () async {
      SharedPreferences.setMockInitialValues({});
      final state = SculptusState();
      await state.load();
      final day = DateTime(2026, 11, 6);
      await state.addActivity(
        ActivityEntry(
          id: 'whoop-2026-11-06',
          date: day,
          name: 'WHOOP workouts (2)',
          caloriesBurned: 410,
          createdAt: day,
        ),
      );
      expect(state.activityBurnFor(day), 410);

      await state.applyLog(
        LoggedDay.fromJson({
          'workouts': [
            {
              'name': 'CrossFit WOD',
              'caloriesBurned': 0,
              'estimatedCaloriesBurned': 330,
              'minutes': 19,
              'details': '5 rounds: 400m run, 15 thrusters @ 95 lb; 18:40',
            },
          ],
        }),
        day,
      );

      expect(state.activityBurnFor(day), 410);
      expect(state.hasWodAndWhoop(day), isTrue);
      final whoop = state
          .activitiesFor(day)
          .firstWhere((entry) => entry.id.startsWith('whoop-'));
      expect(state.isActivityOverridden(whoop), isFalse);

      await state.setPrefersWod(day, true);
      expect(state.activityBurnFor(day), 330);
      expect(state.isActivityOverridden(whoop), isTrue);

      await state.setPrefersWod(day, false);
      expect(state.activityBurnFor(day), 410);
    },
  );

  test(
    'a typed tracker burn counts unless the WOD estimate is chosen',
    () async {
      SharedPreferences.setMockInitialValues({});
      final state = SculptusState();
      await state.load();
      final day = DateTime(2026, 11, 6);

      await state.applyLog(
        LoggedDay.fromJson({
          'workouts': [
            {
              'name': 'CrossFit',
              'caloriesBurned': 571,
              'estimatedCaloriesBurned': 400,
              'minutes': 0,
              'details': '5 rounds; 21:30',
            },
          ],
        }),
        day,
      );

      expect(state.activityBurnFor(day), 571);
      await state.setPrefersWod(day, true);
      expect(state.activityBurnFor(day), 400);
      expect(
        state
            .activitiesFor(day)
            .firstWhere((entry) => entry.id.startsWith('wod'))
            .notes,
        contains('Tracker said 571'),
      );
    },
  );

  testWidgets('the burn info explains resting, training and walking', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final state = SculptusState();
    await state.load();
    final day = DateTime.now();
    await state.updateGoals(
      state.goals.copyWith(age: 33, heightInches: 75, sex: 'male'),
    );
    await state.setWeight(day, 204);
    final parts = state.burnBreakdownFor(day)!;
    expect(
      parts.resting + parts.training + parts.walking,
      state.maintenanceFor(day),
    );

    await tester.pumpWidget(shadHarness(BalanceCard(state: state, date: day)));
    await tester.tap(find.byKey(const ValueKey('burnInfo')));
    await tester.pumpAndSettle();
    expect(find.text('How your burn is estimated'), findsOneWidget);
    expect(find.text('Resting'), findsOneWidget);
  });

  test('recent foods are de-duplicated, most frequent first', () async {
    SharedPreferences.setMockInitialValues({});
    final state = SculptusState();
    await state.load();
    LoggedDay food(String name, int calories) => LoggedDay(
      foods: [
        LoggedFood(
          name: name,
          calories: calories,
          caloriesLow: 0,
          caloriesHigh: 0,
          proteinGrams: 10,
          assumption: '',
        ),
      ],
    );
    await state.applyLog(food('Banana', 105), DateTime(2026, 11, 3));
    await state.applyLog(food('Mexican bowl', 640), DateTime(2026, 11, 4));
    await state.applyLog(food('mexican bowl', 640), DateTime(2026, 11, 5));
    await state.applyLog(food('Apple', 95), DateTime(2026, 11, 6));

    final recents = state.recentFoods(exclude: DateTime(2026, 11, 6));
    expect(recents.map((e) => e.name.toLowerCase()), [
      'mexican bowl',
      'banana',
    ]);
  });

  testWidgets('setup saves age, height and weight, then opens Today', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final state = SculptusState();
    await state.load();
    var done = false;
    await tester.pumpWidget(
      shadHarness(
        SetupScreen(
          state: state,
          auth: AuthController(),
          onDone: () => done = true,
        ),
      ),
    );
    await tester.enterText(find.byKey(const ValueKey('setupName')), 'Mick');
    await tester.tap(find.byKey(const ValueKey('setupContinue')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('setupAge')), '33');
    await tester.enterText(find.byKey(const ValueKey('setupFeet')), '6');
    await tester.enterText(find.byKey(const ValueKey('setupInches')), '3');
    await tester.tap(find.byKey(const ValueKey('setupContinue')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('setupWeight')), '204.3');
    await tester.tap(find.byKey(const ValueKey('setupContinue')));
    await tester.pumpAndSettle();

    expect(done, isTrue);
    expect(state.goals.age, 33);
    expect(state.goals.heightInches, 75);
    expect(state.latestWeight?.weight, 204.3);
  });

  testWidgets('the paywall shows the price, renewal terms and restore', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1179, 2556);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    final subscription = SubscriptionController(enabledOverride: true);
    await tester.pumpWidget(
      shadHarness(
        PaywallScreen(subscription: subscription, auth: AuthController()),
      ),
    );

    expect(find.text('\$4.99 a month'), findsOneWidget);
    expect(find.text('Subscribe with card'), findsOneWidget);
    expect(find.text('Check my subscription'), findsOneWidget);
    expect(find.textContaining('renews monthly'), findsOneWidget);
  });

  test('the app stays unlocked until the server enforces payment', () {
    expect(SubscriptionController().unlocked, isTrue);
    expect(SubscriptionController(enabledOverride: true).unlocked, isFalse);
  });

  testWidgets('a meal-prep batch is split into portions', (tester) async {
    tester.view.physicalSize = const Size(1179, 2556);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(shadHarness(NewMealPage(client: FakeMeals([]))));
    await tester.enterText(
      find.byKey(const ValueKey('newMealIngredients')),
      '1.2kg chicken thigh, 600g rice',
    );
    for (var i = 0; i < 5; i++) {
      await tester.tap(find.byKey(const ValueKey('portionsPlus')));
    }
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('newMealCalculate')));
    await tester.pumpAndSettle();

    expect(find.text('6'), findsOneWidget);
    expect(find.text('800'), findsOneWidget);
    expect(find.text('60'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('portionsMinus')));
    await tester.pump();
    expect(find.text('960'), findsOneWidget);
  });

  test('weigh-ins give a 7-day average, weekly change and series', () async {
    SharedPreferences.setMockInitialValues({});
    final state = SculptusState();
    await state.load();
    final today = DateTime(2026, 11, 14);
    for (var i = 0; i < 14; i++) {
      await state.setWeight(DateTime(2026, 11, 1 + i), 205 - i * 0.2);
    }
    await state.setWeight(today, 202.0);

    expect(state.weights.where((w) => _sameDay(w.date, today)).length, 1);
    expect(state.weightTrendFor(today), closeTo(202.94, 0.01));
    expect(state.weeklyWeightChange(today), closeTo(-1.46, 0.01));
    final series = state.weightSeries(today, 30);
    expect(series.length, 14);
    expect(series.last.weight, 202.0);
  });

  testWidgets('Gauge screen still shows the daily prompts', (tester) async {
    await pumpScreen(tester, (state) => DashboardScreen(state: state));

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
    await pumpScreen(tester, (state) => DiaryScreen(state: state));

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
    await pumpScreen(tester, (state) => DashboardScreen(state: state));

    await tester.tap(find.text('Log').first);
    await tester.pumpAndSettle();

    expect(find.text('Did You Workout?'), findsOneWidget);
    expect(find.text('Steps so far'), findsNothing);
    expect(find.text('Calories burned'), findsOneWidget);
  });

  testWidgets('steps dialog logs current and projected steps', (tester) async {
    await pumpScreen(tester, (state) => DashboardScreen(state: state));

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
    await pumpScreen(tester, (state) => WeightScreen(state: state));

    expect(find.text('WHOOP'), findsOneWidget);
    expect(find.text('Sync day'), findsOneWidget);
    expect(find.text('Backend'), findsOneWidget);
    expect(
      find.text('https://sculptus-backend-oae5ydvgvq-ue.a.run.app'),
      findsOneWidget,
    );
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
    await pumpScreen(tester, (state) => DashboardScreen(state: state));

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

bool _sameDay(DateTime a, DateTime b) =>
    a.year == b.year && a.month == b.month && a.day == b.day;
