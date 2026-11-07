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
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
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
                GestureDetector(
                  key: const ValueKey('editNameButton'),
                  onTap: () => showNameSheet(context, auth),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Flexible(
                        child: Text(
                          session?.shortName ?? 'Athlete',
                          textAlign: TextAlign.center,
                          style: theme.textTheme.h3.copyWith(
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                      const SizedBox(width: 6),
                      Icon(
                        LucideIcons.pencil,
                        size: 16,
                        color: theme.colorScheme.mutedForeground,
                      ),
                    ],
                  ),
                ),
                if (session != null && !session.hasPrivateEmail)
                  Text(
                    session.email,
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

Future<void> showNameSheet(BuildContext context, AuthController auth) async {
  final current = auth.session?.shortName ?? '';
  final controller = TextEditingController(
    text: current == 'Athlete' ? '' : current,
  );
  final name = await showShadSheet<String>(
    context: context,
    side: ShadSheetSide.bottom,
    builder: (context) => ShadSheet(
      title: const Text('Your name'),
      actions: [
        ShadButton(
          onPressed: () => Navigator.of(context).pop(controller.text),
          child: const Text('Save'),
        ),
      ],
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: ShadInput(
          key: const ValueKey('nameField'),
          controller: controller,
          autofocus: true,
          placeholder: const Text('Your name'),
        ),
      ),
    ),
  );
  controller.dispose();
  if (name != null && name.trim().isNotEmpty) {
    await auth.updateDisplayName(name);
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
                      style: theme.textTheme.h4.copyWith(
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
              height: 120,
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
    final low = values.reduce(math.min) - 0.5;
    final high = values.reduce(math.max) + 0.5;
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
    final changed = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (context) => NewMealPage(client: client, existing: meal),
      ),
    );
    if (changed == true) {
      await _run(client.list);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = ShadTheme.of(context);
    final meals = this.meals;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _list(theme, meals),
        const SizedBox(height: 8),
        ShadButton.outline(
          key: const ValueKey('newMealButton'),
          onPressed: _create,
          leading: const Icon(LucideIcons.chefHat, size: 16),
          child: const Text('New meal from ingredients'),
        ),
      ],
    );
  }

  Future<void> _create() async {
    final changed = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (context) => NewMealPage(client: client)),
    );
    if (changed == true) {
      await _run(client.list);
    }
  }

  Widget _list(ShadThemeData theme, List<SavedMeal>? meals) {
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
                'Build a meal from its ingredients below, or tap any food on '
                'Today to save it. Sculptus uses these numbers whenever you '
                'mention the meal.',
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

class NewMealPage extends StatefulWidget {
  const NewMealPage({super.key, required this.client, this.existing});

  final MealsApiClient client;
  final SavedMeal? existing;

  @override
  State<NewMealPage> createState() => _NewMealPageState();
}

class _NewMealPageState extends State<NewMealPage> {
  late final name = TextEditingController(text: widget.existing?.name ?? '');
  late final ingredients = TextEditingController(
    text: widget.existing?.ingredients ?? '',
  );
  late final calories = TextEditingController(
    text: widget.existing == null ? '' : '${widget.existing!.calories}',
  );
  late final protein = TextEditingController(
    text: widget.existing == null
        ? ''
        : _formatNumber(widget.existing!.proteinGrams.roundToDouble()),
  );
  late int portions = widget.existing?.portions ?? 1;
  MealEstimate? estimate;
  bool working = false;
  bool saving = false;
  String errorMessage = '';

  bool get isEditing => widget.existing != null;

  @override
  void dispose() {
    name.dispose();
    ingredients.dispose();
    calories.dispose();
    protein.dispose();
    super.dispose();
  }

  void _setPortions(int value) {
    setState(() {
      portions = value;
      _fillFromEstimate();
    });
  }

  void _fillFromEstimate() {
    final estimate = this.estimate;
    if (estimate == null) {
      return;
    }
    calories.text = '${(estimate.calories / portions).round()}';
    protein.text = '${(estimate.proteinGrams / portions).round()}';
  }

  Future<void> _calculate() async {
    if (ingredients.text.trim().isEmpty) {
      setState(() => errorMessage = 'List what goes in it first.');
      return;
    }
    FocusScope.of(context).unfocus();
    setState(() {
      working = true;
      errorMessage = '';
    });
    try {
      final result = await widget.client.estimate(
        name.text.trim(),
        ingredients.text.trim(),
        portions: portions,
      );
      setState(() {
        estimate = result;
        if (name.text.trim().isEmpty) {
          name.text = result.name;
        }
        _fillFromEstimate();
      });
    } catch (error) {
      setState(() => errorMessage = error.toString());
    } finally {
      if (mounted) {
        setState(() => working = false);
      }
    }
  }

  Future<void> _save() async {
    final meal = SavedMeal(
      name: name.text.trim(),
      calories: _readInt(calories.text),
      proteinGrams: _readDouble(protein.text),
      ingredients: ingredients.text.trim(),
      portions: portions,
    );
    if (meal.name.isEmpty || meal.calories <= 0) {
      setState(
        () => errorMessage = 'Give it a name and calories, or tap Work it out.',
      );
      return;
    }
    setState(() => saving = true);
    try {
      final old = widget.existing;
      if (old != null && old.name.toLowerCase() != meal.name.toLowerCase()) {
        await widget.client.remove(old.name);
      }
      await widget.client.save(meal);
      if (mounted) {
        Navigator.of(context).pop(true);
      }
    } catch (error) {
      setState(() {
        saving = false;
        errorMessage = error.toString();
      });
    }
  }

  Future<void> _delete() async {
    final old = widget.existing;
    if (old == null) {
      return;
    }
    await widget.client.remove(old.name);
    if (mounted) {
      Navigator.of(context).pop(true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = ShadTheme.of(context);
    final estimate = this.estimate;
    final label = theme.textTheme.small;
    final hint = theme.textTheme.muted.copyWith(fontSize: 12);
    return Scaffold(
      backgroundColor: theme.colorScheme.background,
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 4, 16, 0),
              child: Row(
                children: [
                  ShadIconButton.ghost(
                    icon: const Icon(LucideIcons.chevronLeft),
                    onPressed: () => Navigator.of(context).pop(false),
                  ),
                  Text(
                    isEditing ? 'Edit meal' : 'New meal',
                    style: theme.textTheme.large,
                  ),
                ],
              ),
            ),
            Expanded(
              child: ListView(
                keyboardDismissBehavior:
                    ScrollViewKeyboardDismissBehavior.onDrag,
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                children: [
                  Text('Name', style: label),
                  const SizedBox(height: 6),
                  ShadInput(
                    key: const ValueKey('newMealName'),
                    controller: name,
                    placeholder: const Text('Mexican bowl'),
                    textInputAction: TextInputAction.next,
                  ),
                  const SizedBox(height: 18),
                  Text('What goes in it', style: label),
                  Text(
                    'Everything in the whole batch. Amounts help. Optional if '
                    'you know the numbers.',
                    style: hint,
                  ),
                  const SizedBox(height: 6),
                  ShadTextarea(
                    key: const ValueKey('newMealIngredients'),
                    controller: ingredients,
                    placeholder: const Text(
                      '1.2kg chicken thigh\n600g white rice (dry)\n2 cans '
                      'black beans\n1 jar salsa\n200g cheddar',
                    ),
                    minHeight: 130,
                    maxHeight: 260,
                    resizable: false,
                  ),
                  const SizedBox(height: 18),
                  Text('How many portions does it make?', style: label),
                  const SizedBox(height: 8),
                  ShadCard(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 6,
                    ),
                    child: Row(
                      children: [
                        ShadIconButton.outline(
                          key: const ValueKey('portionsMinus'),
                          icon: const Icon(LucideIcons.minus),
                          onPressed: portions > 1
                              ? () => _setPortions(portions - 1)
                              : null,
                        ),
                        Expanded(
                          child: Column(
                            children: [
                              Text(
                                '$portions',
                                key: const ValueKey('portionsValue'),
                                style: theme.textTheme.h3.copyWith(
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                              Text(
                                portions == 1 ? 'portion' : 'portions',
                                style: hint,
                              ),
                            ],
                          ),
                        ),
                        ShadIconButton.outline(
                          key: const ValueKey('portionsPlus'),
                          icon: const Icon(LucideIcons.plus),
                          onPressed: portions < 50
                              ? () => _setPortions(portions + 1)
                              : null,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  ShadButton.secondary(
                    key: const ValueKey('newMealCalculate'),
                    onPressed: working ? null : _calculate,
                    leading: working
                        ? const SizedBox.square(
                            dimension: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(LucideIcons.sparkles, size: 16),
                    child: Text(working ? 'Working it out' : 'Work it out'),
                  ),
                  const SizedBox(height: 18),
                  Text('Each portion', style: label),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      Expanded(
                        child: ShadInput(
                          key: const ValueKey('perPortionCalories'),
                          controller: calories,
                          keyboardType: TextInputType.number,
                          placeholder: const Text('Calories'),
                          trailing: const Text('kcal'),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: ShadInput(
                          key: const ValueKey('perPortionProtein'),
                          controller: protein,
                          keyboardType: TextInputType.number,
                          placeholder: const Text('Protein'),
                          trailing: const Text('g protein'),
                        ),
                      ),
                    ],
                  ),
                  if (errorMessage.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    ShadAlert.destructive(
                      icon: const Icon(LucideIcons.info),
                      description: Text(errorMessage),
                    ),
                  ],
                  if (estimate != null) ...[
                    const SizedBox(height: 14),
                    ShadCard(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Whole batch ${_thousands(estimate.calories)} kcal · '
                            '${estimate.proteinGrams.round()}g protein',
                            style: theme.textTheme.small.copyWith(
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 8),
                          for (final item in estimate.items)
                            Padding(
                              padding: const EdgeInsets.symmetric(vertical: 3),
                              child: Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      item.name,
                                      style: theme.textTheme.small,
                                    ),
                                  ),
                                  Text(
                                    _thousands(item.calories),
                                    style: hint.copyWith(fontSize: 13),
                                  ),
                                ],
                              ),
                            ),
                          if (estimate.assumption.isNotEmpty) ...[
                            const SizedBox(height: 8),
                            Text(estimate.assumption, style: hint),
                          ],
                        ],
                      ),
                    ),
                  ],
                  if (isEditing) ...[
                    const SizedBox(height: 18),
                    ShadButton.ghost(
                      onPressed: _delete,
                      foregroundColor: theme.colorScheme.destructive,
                      leading: const Icon(LucideIcons.trash2, size: 16),
                      child: const Text('Delete this meal'),
                    ),
                  ],
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
              child: SizedBox(
                width: double.infinity,
                child: ShadButton(
                  key: const ValueKey('newMealSave'),
                  height: 50,
                  onPressed: saving ? null : _save,
                  leading: const Icon(LucideIcons.bookmarkPlus, size: 18),
                  child: const Text('Save meal'),
                ),
              ),
            ),
          ],
        ),
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
