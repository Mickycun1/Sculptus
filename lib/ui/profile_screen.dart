part of '../main.dart';

class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key, required this.state, required this.auth});

  final SculptusState state;
  final AuthController auth;

  @override
  Widget build(BuildContext context) {
    final theme = ShadTheme.of(context);
    return Scaffold(
      backgroundColor: theme.colorScheme.background,
      body: SafeArea(
        bottom: false,
        child: ListenableBuilder(
          listenable: Listenable.merge([state, auth]),
          builder: (context, _) {
            final session = auth.session;
            return ListView(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 40),
              children: [
                Row(
                  children: [
                    ShadIconButton.ghost(
                      icon: const Icon(LucideIcons.chevronLeft),
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                    Text('Profile', style: theme.textTheme.large),
                  ],
                ),
                const SizedBox(height: 12),
                Center(
                  child: InitialsAvatar(
                    name: session?.shortName ?? 'Sculptus',
                    size: 84,
                  ),
                ),
                const SizedBox(height: 14),
                Text(
                  session?.shortName ?? 'Athlete',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.h3.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
                if ((session?.email ?? '').isNotEmpty &&
                    session?.email != session?.shortName)
                  Text(
                    session!.email,
                    textAlign: TextAlign.center,
                    style: theme.textTheme.muted,
                  ),
                const SizedBox(height: 8),
                Center(
                  child: ShadBadge.outline(
                    child: Text(
                      session?.provider == 'apple'
                          ? 'Signed in with Apple'
                          : 'Signed in with email',
                    ),
                  ),
                ),
                const SectionLabel('Weight'),
                WeightCard(state: state),
                const SectionLabel('About you'),
                BodyCard(state: state),
                const SectionLabel('My meals'),
                MyMealsCard(auth: auth),
                const SectionLabel('Connections'),
                ConnectionsCard(state: state, auth: auth),
                const SectionLabel('Account'),
                AccountCard(state: state, auth: auth),
                const SizedBox(height: 24),
                Text(
                  'Sculptus by Dynafex',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.muted.copyWith(fontSize: 12),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class WeightCard extends StatelessWidget {
  const WeightCard({super.key, required this.state});

  final SculptusState state;

  @override
  Widget build(BuildContext context) {
    final theme = ShadTheme.of(context);
    final today = _dateOnly(DateTime.now());
    final trend = state.weightTrendFor(today);
    final change = state.weeklyWeightChange(today);
    final series = state.weightSeries(today, 30);
    final goal = state.goals.targetWeight;
    final changeColor = change == null
        ? theme.colorScheme.mutedForeground
        : (change <= 0 ? _positive : theme.colorScheme.destructive);

    return ShadCard(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      trend == null ? 'No weigh-ins' : trend.toStringAsFixed(1),
                      style: theme.textTheme.h2.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    Text(
                      trend == null
                          ? 'Weigh in to start your trend'
                          : 'lb · 7-day average',
                      style: theme.textTheme.muted,
                    ),
                  ],
                ),
              ),
              if (change != null)
                Row(
                  children: [
                    Icon(
                      change <= 0
                          ? LucideIcons.trendingDown
                          : LucideIcons.trendingUp,
                      size: 16,
                      color: changeColor,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      '${change <= 0 ? '' : '+'}${change.toStringAsFixed(1)} lb/wk',
                      style: theme.textTheme.small.copyWith(color: changeColor),
                    ),
                  ],
                ),
            ],
          ),
          const SizedBox(height: 16),
          if (series.length >= 2)
            SizedBox(
              height: 150,
              child: CustomPaint(
                size: Size.infinite,
                painter: WeightTrendPainter(
                  series: series,
                  goal: goal > 0 ? goal : null,
                  line: theme.colorScheme.primary,
                  dot: theme.colorScheme.mutedForeground,
                  grid: theme.colorScheme.border,
                  label: TextStyle(
                    color: theme.colorScheme.mutedForeground,
                    fontSize: 10,
                    fontFamily: theme.textTheme.family,
                  ),
                ),
              ),
            )
          else
            Text(
              'Weigh in a couple of mornings and your trend line appears '
              'here, with each day\'s weight and the 7-day average.',
              style: theme.textTheme.muted.copyWith(fontSize: 13),
            ),
          const SizedBox(height: 12),
          Row(
            children: [
              if (trend != null && goal > 0)
                Expanded(
                  child: Text(
                    trend > goal
                        ? '${(trend - goal).toStringAsFixed(1)} lb to your '
                              '${_formatNumber(goal)} lb goal'
                        : 'At or below your ${_formatNumber(goal)} lb goal',
                    style: theme.textTheme.small,
                  ),
                )
              else
                const Spacer(),
              ShadButton(
                size: ShadButtonSize.sm,
                onPressed: () => showWeighInSheet(context, state, today),
                leading: const Icon(LucideIcons.plus, size: 14),
                child: const Text('Weigh in'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class WeightTrendPainter extends CustomPainter {
  WeightTrendPainter({
    required this.series,
    required this.goal,
    required this.line,
    required this.dot,
    required this.grid,
    required this.label,
  });

  final List<({DateTime date, double weight, double average})> series;
  final double? goal;
  final Color line;
  final Color dot;
  final Color grid;
  final TextStyle label;

  @override
  void paint(Canvas canvas, Size size) {
    final values = [
      for (final point in series) ...[point.weight, point.average],
    ];
    var low = values.reduce(math.min) - 1;
    var high = values.reduce(math.max) + 1;
    if (goal != null && goal! > low - 6 && goal! < high + 6) {
      low = math.min(low, goal! - 0.5);
      high = math.max(high, goal! + 0.5);
    }
    const left = 0.0;
    const right = 32.0;
    final width = size.width - left - right;
    final height = size.height - 8;
    int dayIndex(DateTime date) => DateTime.utc(date.year, date.month, date.day)
        .difference(
          DateTime.utc(
            series.first.date.year,
            series.first.date.month,
            series.first.date.day,
          ),
        )
        .inDays;
    final first = series.first.date;
    final span = math.max(1, dayIndex(series.last.date));

    Offset at(DateTime date, double value) => Offset(
      left + width * dayIndex(date) / span,
      4 + height * (1 - (value - low) / (high - low)),
    );

    final gridPaint = Paint()
      ..color = grid
      ..strokeWidth = 1;
    for (final value in [high, (high + low) / 2, low]) {
      final y = at(first, value).dy;
      canvas.drawLine(Offset(left, y), Offset(left + width, y), gridPaint);
      final text = TextPainter(
        text: TextSpan(text: value.toStringAsFixed(0), style: label),
        textDirection: TextDirection.ltr,
      )..layout();
      text.paint(canvas, Offset(left + width + 6, y - text.height / 2));
    }

    if (goal != null && goal! >= low && goal! <= high) {
      final y = at(first, goal!).dy;
      final goalPaint = Paint()
        ..color = _positive.withValues(alpha: 0.6)
        ..strokeWidth = 1.5;
      for (var x = left; x < left + width; x += 8) {
        canvas.drawLine(Offset(x, y), Offset(x + 4, y), goalPaint);
      }
    }

    final dotPaint = Paint()..color = dot.withValues(alpha: 0.5);
    for (final point in series) {
      canvas.drawCircle(at(point.date, point.weight), 3, dotPaint);
    }

    final path = Path();
    for (var i = 0; i < series.length; i++) {
      final offset = at(series[i].date, series[i].average);
      if (i == 0) {
        path.moveTo(offset.dx, offset.dy);
      } else {
        path.lineTo(offset.dx, offset.dy);
      }
    }
    canvas.drawPath(
      path,
      Paint()
        ..color = line
        ..strokeWidth = 2.5
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );
    canvas.drawCircle(
      at(series.last.date, series.last.average),
      4.5,
      Paint()..color = line,
    );
  }

  @override
  bool shouldRepaint(WeightTrendPainter oldDelegate) =>
      oldDelegate.series != series || oldDelegate.line != line;
}

class BodyCard extends StatelessWidget {
  const BodyCard({super.key, required this.state});

  final SculptusState state;

  @override
  Widget build(BuildContext context) {
    final theme = ShadTheme.of(context);
    final goals = state.goals;
    String height() {
      if (goals.heightInches <= 0) {
        return 'Not set';
      }
      final feet = goals.heightInches ~/ 12;
      final inches = _formatNumber(goals.heightInches - feet * 12);
      return '$feet\' $inches"';
    }

    Widget row(IconData icon, String label, String value) => ListRow(
      leading: IconBubble(icon),
      title: label,
      trailing: Text(value, style: theme.textTheme.muted),
    );

    return ShadCard(
      padding: const EdgeInsets.fromLTRB(14, 4, 14, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          row(
            LucideIcons.calendar,
            'Age',
            goals.age > 0 ? '${goals.age}' : 'Not set',
          ),
          row(LucideIcons.ruler, 'Height', height()),
          row(
            LucideIcons.user,
            'Sex',
            goals.sex == 'female' ? 'Female' : 'Male',
          ),
          row(
            LucideIcons.target,
            'Goal weight',
            goals.targetWeight > 0
                ? '${_formatNumber(goals.targetWeight)} lb'
                : 'Not set',
          ),
          const SizedBox(height: 4),
          ShadButton.outline(
            key: const ValueKey('editBodyButton'),
            onPressed: () => showBodySheet(context, state),
            child: const Text('Edit'),
          ),
        ],
      ),
    );
  }
}

Future<void> showBodySheet(BuildContext context, SculptusState state) async {
  final goals = state.goals;
  final age = TextEditingController(text: goals.age > 0 ? '${goals.age}' : '');
  final feet = TextEditingController(
    text: goals.heightInches > 0 ? '${goals.heightInches ~/ 12}' : '',
  );
  final inches = TextEditingController(
    text: goals.heightInches > 0
        ? _formatNumber(goals.heightInches - (goals.heightInches ~/ 12) * 12)
        : '',
  );
  final goal = TextEditingController(
    text: goals.targetWeight > 0 ? _formatNumber(goals.targetWeight) : '',
  );
  var sex = goals.sex;
  final saved = await showShadSheet<bool>(
    context: context,
    side: ShadSheetSide.bottom,
    builder: (context) => StatefulBuilder(
      builder: (context, setSheetState) => ShadSheet(
        title: const Text('About you'),
        description: const Text(
          'Used to estimate what you burn at rest. It stays on this phone.',
        ),
        actions: [
          ShadButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Save'),
          ),
        ],
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Column(
            children: [
              ShadInput(
                key: const ValueKey('profileAge'),
                controller: age,
                keyboardType: TextInputType.number,
                placeholder: const Text('Age'),
                trailing: const Text('years'),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: ShadInput(
                      key: const ValueKey('profileFeet'),
                      controller: feet,
                      keyboardType: TextInputType.number,
                      placeholder: const Text('Feet'),
                      trailing: const Text('ft'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: ShadInput(
                      key: const ValueKey('profileInches'),
                      controller: inches,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      placeholder: const Text('Inches'),
                      trailing: const Text('in'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              ShadInput(
                controller: goal,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                placeholder: const Text('Goal weight'),
                trailing: const Text('lb'),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  for (final option in const ['male', 'female']) ...[
                    Expanded(
                      child: option == sex
                          ? ShadButton(
                              onPressed: () {},
                              child: Text(option == 'male' ? 'Male' : 'Female'),
                            )
                          : ShadButton.outline(
                              onPressed: () =>
                                  setSheetState(() => sex = option),
                              child: Text(option == 'male' ? 'Male' : 'Female'),
                            ),
                    ),
                    if (option == 'male') const SizedBox(width: 8),
                  ],
                ],
              ),
            ],
          ),
        ),
      ),
    ),
  );
  if (saved == true) {
    await state.updateGoals(
      goals.copyWith(
        age: _readInt(age.text),
        heightInches: _readInt(feet.text) * 12 + _readDouble(inches.text),
        sex: sex,
        targetWeight: _readDouble(goal.text, goals.targetWeight),
      ),
    );
  }
  age.dispose();
  feet.dispose();
  inches.dispose();
  goal.dispose();
}

class MyMealsCard extends StatefulWidget {
  const MyMealsCard({super.key, required this.auth, this.client});

  final AuthController auth;
  final MealsApiClient? client;

  @override
  State<MyMealsCard> createState() => _MyMealsCardState();
}

class _MyMealsCardState extends State<MyMealsCard> {
  List<SavedMeal>? meals;
  String errorMessage = '';

  MealsApiClient get client =>
      widget.client ??
      MealsApiClient(
        widget.auth.authBackendUrl,
        widget.auth.session?.backendToken ?? '',
      );

  @override
  void initState() {
    super.initState();
    _run(client.list);
  }

  Future<void> _run(Future<List<SavedMeal>> Function() action) async {
    try {
      final result = await action();
      if (mounted) {
        setState(() {
          meals = result;
          errorMessage = '';
        });
      }
    } catch (error) {
      if (mounted) {
        setState(() => errorMessage = error.toString());
      }
    }
  }

  Future<void> _edit(SavedMeal meal) async {
    final name = TextEditingController(text: meal.name);
    final calories = TextEditingController(text: '${meal.calories}');
    final protein = TextEditingController(
      text: _formatNumber(meal.proteinGrams.roundToDouble()),
    );
    final action = await showShadSheet<String>(
      context: context,
      side: ShadSheetSide.bottom,
      builder: (context) => ShadSheet(
        title: Text(meal.name),
        description: const Text('Sculptus uses these numbers exactly.'),
        actions: [
          ShadButton(
            onPressed: () => Navigator.of(context).pop('save'),
            child: const Text('Save'),
          ),
          ShadButton.ghost(
            onPressed: () => Navigator.of(context).pop('delete'),
            foregroundColor: ShadTheme.of(context).colorScheme.destructive,
            leading: const Icon(LucideIcons.trash2, size: 16),
            child: const Text('Forget this meal'),
          ),
        ],
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Column(
            children: [
              ShadInput(controller: name, placeholder: const Text('Name')),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: ShadInput(
                      controller: calories,
                      keyboardType: TextInputType.number,
                      trailing: const Text('kcal'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: ShadInput(
                      controller: protein,
                      keyboardType: TextInputType.number,
                      trailing: const Text('g protein'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
    final edited = SavedMeal(
      name: name.text.trim(),
      calories: _readInt(calories.text),
      proteinGrams: _readDouble(protein.text),
    );
    name.dispose();
    calories.dispose();
    protein.dispose();
    if (action == 'delete') {
      await _run(() => client.remove(meal.name));
    } else if (action == 'save' && edited.name.isNotEmpty) {
      await _run(() async {
        if (edited.name.toLowerCase() != meal.name.toLowerCase()) {
          await client.remove(meal.name);
        }
        return client.save(edited);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = ShadTheme.of(context);
    final meals = this.meals;
    return ShadCard(
      padding: const EdgeInsets.fromLTRB(14, 4, 14, 4),
      child: errorMessage.isNotEmpty
          ? Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Text(errorMessage, style: theme.textTheme.muted),
            )
          : meals == null
          ? const Padding(
              padding: EdgeInsets.all(16),
              child: Center(
                child: SizedBox.square(
                  dimension: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            )
          : meals.isEmpty
          ? Padding(
              padding: const EdgeInsets.symmetric(vertical: 14),
              child: Text(
                'Tap any food on Today and save it with its real numbers. '
                'Sculptus will use them whenever you mention it.',
                style: theme.textTheme.muted.copyWith(fontSize: 13),
              ),
            )
          : Column(
              children: [
                for (final meal in meals)
                  ListRow(
                    leading: const IconBubble(LucideIcons.utensils),
                    title: meal.name,
                    subtitle:
                        '${_thousands(meal.calories)} kcal · '
                        '${_formatNumber(meal.proteinGrams.roundToDouble())}g protein',
                    trailing: Icon(
                      LucideIcons.chevronRight,
                      size: 16,
                      color: theme.colorScheme.mutedForeground,
                    ),
                    onTap: () => _edit(meal),
                  ),
              ],
            ),
    );
  }
}

class ConnectionsCard extends StatelessWidget {
  const ConnectionsCard({super.key, required this.state, required this.auth});

  final SculptusState state;
  final AuthController auth;

  Future<void> _connectWhoop(BuildContext context) async {
    final sonner = ShadSonner.of(context);
    try {
      final url = await WhoopApiClient(
        state.whoopBackendUrl,
        token: auth.session?.backendToken ?? '',
      ).authorizationUrl();
      await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
    } catch (error) {
      sonner.show(ShadToast.destructive(description: Text('$error')));
    }
  }

  void _explainWodify(BuildContext context) {
    showShadDialog<void>(
      context: context,
      builder: (context) => ShadDialog(
        title: const Text('Your WOD, in the log'),
        description: const Text(
          'Wodify only gives API access to gyms, not athletes. So paste or '
          'type the WOD and your result into the log, for example "5 rounds: '
          '400m run, 15 thrusters at 95 lb, finished 18:40". Sculptus '
          'estimates the burn from the actual work for your weight, and uses '
          'it instead of WHOOP for that day.',
        ),
        actions: [
          ShadButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Got it'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = ShadTheme.of(context);
    final connected = state.whoop.connected;
    return ShadCard(
      padding: const EdgeInsets.fromLTRB(14, 4, 14, 4),
      child: Column(
        children: [
          ListRow(
            leading: const IconBubble(LucideIcons.watch, color: _gold),
            title: 'WHOOP',
            subtitle: connected
                ? 'Workouts and steps sync on refresh'
                : 'Import workouts and steps',
            trailing: connected
                ? const ShadBadge.secondary(child: Text('Connected'))
                : ShadButton.outline(
                    size: ShadButtonSize.sm,
                    onPressed: () => _connectWhoop(context),
                    child: const Text('Connect'),
                  ),
          ),
          ListRow(
            leading: const IconBubble(LucideIcons.dumbbell, color: _gold),
            title: 'WOD burn estimate',
            subtitle: 'Paste your Wodify workout into the log',
            trailing: Icon(
              LucideIcons.info,
              size: 16,
              color: theme.colorScheme.mutedForeground,
            ),
            onTap: () => _explainWodify(context),
          ),
        ],
      ),
    );
  }
}

class AccountCard extends StatelessWidget {
  const AccountCard({super.key, required this.state, required this.auth});

  final SculptusState state;
  final AuthController auth;

  Future<void> _delete(BuildContext context) async {
    final navigator = Navigator.of(context);
    final sonner = ShadSonner.of(context);
    final confirmed = await showShadDialog<bool>(
      context: context,
      builder: (context) => ShadDialog.alert(
        title: const Text('Delete your account?'),
        description: const Text(
          'This permanently deletes your Sculptus account and saved meals, '
          'disconnects WHOOP, and erases everything logged on this phone.',
        ),
        actions: [
          ShadButton.outline(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          ShadButton.destructive(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true) {
      return;
    }
    if (await auth.deleteAccount()) {
      await state.clearAll();
      navigator.popUntil((route) => route.isFirst);
    } else {
      sonner.show(ShadToast.destructive(description: Text(auth.errorMessage)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = ShadTheme.of(context);
    return ShadCard(
      padding: const EdgeInsets.fromLTRB(14, 4, 14, 4),
      child: Column(
        children: [
          ListRow(
            leading: const IconBubble(LucideIcons.shieldCheck),
            title: 'Privacy policy',
            trailing: Icon(
              LucideIcons.externalLink,
              size: 16,
              color: theme.colorScheme.mutedForeground,
            ),
            onTap: () => launchUrl(
              Uri.parse('https://dynafex.ai/sculptus_privacy_policy.html'),
              mode: LaunchMode.externalApplication,
            ),
          ),
          ListRow(
            leading: const IconBubble(LucideIcons.logOut),
            title: 'Sign out',
            onTap: () async {
              Navigator.of(context).popUntil((route) => route.isFirst);
              await auth.signOut();
            },
          ),
          ListRow(
            leading: IconBubble(
              LucideIcons.trash2,
              color: theme.colorScheme.destructive,
            ),
            title: 'Delete account',
            onTap: () => _delete(context),
          ),
        ],
      ),
    );
  }
}
