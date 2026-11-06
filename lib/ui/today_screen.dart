part of '../main.dart';

class HomeShell extends StatelessWidget {
  const HomeShell({super.key, required this.state, required this.auth});

  final SculptusState state;
  final AuthController auth;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: ShadTheme.of(context).colorScheme.background,
      body: SafeArea(
        bottom: false,
        child: TodayScreen(state: state, auth: auth),
      ),
    );
  }
}

class TodayScreen extends StatefulWidget {
  const TodayScreen({super.key, required this.state, required this.auth});

  final SculptusState state;
  final AuthController auth;

  @override
  State<TodayScreen> createState() => _TodayScreenState();
}

class _TodayScreenState extends State<TodayScreen> {
  final logText = TextEditingController();
  bool isLogging = false;
  String errorMessage = '';
  String question = '';
  List<LoggedFood> considering = const [];

  DateTime get today => _dateOnly(DateTime.now());
  String get token => widget.auth.session?.backendToken ?? '';

  @override
  void initState() {
    super.initState();
    if (widget.state.whoop.connected) {
      _syncWhoop();
    }
  }

  @override
  void dispose() {
    logText.dispose();
    super.dispose();
  }

  Future<void> _syncWhoop() async {
    try {
      final snapshot = await WhoopApiClient(
        widget.state.whoopBackendUrl,
        token: token,
      ).fetchSummary(today);
      await widget.state.applyWhoopSnapshot(snapshot);
    } on WhoopSyncException {
      // Today still works from what was typed; WHOOP fills in when reachable.
    }
  }

  Future<bool> _ensureAiConsent() async {
    const consentKey = 'sculptus_ai_consent_v1';
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getBool(consentKey) ?? false) {
      return true;
    }
    if (!mounted) {
      return false;
    }
    final agreed = await showShadDialog<bool>(
      context: context,
      builder: (context) => ShadDialog(
        title: const Text('How logging works'),
        description: const Text(
          'Sculptus sends what you type here to Anthropic\'s Claude AI to '
          'estimate calories, protein, workouts, steps and weight. Anthropic '
          'does not use it to train its models. Nothing else from your '
          'account is sent.',
        ),
        actions: [
          ShadButton.outline(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Not now'),
          ),
          ShadButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Agree'),
          ),
        ],
      ),
    );
    if (agreed != true) {
      return false;
    }
    await prefs.setBool(consentKey, true);
    return true;
  }

  Future<void> _submit() async {
    final text = logText.text.trim();
    if (text.isEmpty || isLogging) {
      return;
    }
    FocusScope.of(context).unfocus();
    if (!await _ensureAiConsent()) {
      return;
    }
    setState(() {
      isLogging = true;
      errorMessage = '';
    });
    try {
      final state = widget.state;
      final log = await LogApiClient(widget.auth.authBackendUrl, token).parse(
        text,
        bodyWeightLb: state.weightTrendFor(today) ?? state.latestWeight?.weight,
      );
      await state.applyLog(log, today);
      logText.clear();
      setState(() {
        question = log.question ?? '';
        considering = log.considering;
      });
    } catch (error) {
      setState(() => errorMessage = error.toString());
    } finally {
      if (mounted) {
        setState(() => isLogging = false);
      }
    }
  }

  void _openProfile() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (context) =>
            ProfileScreen(state: widget.state, auth: widget.auth),
      ),
    );
  }

  Future<void> _ate(LoggedFood food) async {
    setState(() {
      considering = [
        for (final option in considering)
          if (option != food) option,
      ];
    });
    await widget.state.applyLog(LoggedDay(foods: [food]), today);
  }

  @override
  Widget build(BuildContext context) {
    final theme = ShadTheme.of(context);
    final state = widget.state;
    final foods = state.entriesFor(today);
    final workouts = state.activitiesFor(today);
    final eaten = state.consumedFor(today);

    return RefreshIndicator(
      onRefresh: _syncWhoop,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 40),
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _weekdays[today.weekday - 1],
                      style: theme.textTheme.h3.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    Text(_displayDate(today), style: theme.textTheme.muted),
                  ],
                ),
              ),
              GestureDetector(
                key: const ValueKey('profileButton'),
                onTap: _openProfile,
                child: InitialsAvatar(
                  name: widget.auth.session?.shortName ?? 'Sculptus',
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          BalanceCard(state: state, date: today),
          if (!state.hasProfile) ...[
            const SizedBox(height: 12),
            ShadAlert(
              icon: const Icon(LucideIcons.target),
              title: const Text('See your real deficit'),
              description: const Text(
                'Add your age and height in your profile so Sculptus can '
                'estimate what you burn.',
              ),
              trailing: ShadButton.outline(
                size: ShadButtonSize.sm,
                onPressed: _openProfile,
                child: const Text('Add'),
              ),
            ),
          ],
          const SizedBox(height: 12),
          WeightStrip(
            state: state,
            date: today,
            onOpen: _openProfile,
            onWeighIn: () => showWeighInSheet(context, state, today),
          ),
          const SizedBox(height: 12),
          ShadCard(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                ShadTextarea(
                  key: const ValueKey('todayLogField'),
                  controller: logText,
                  placeholder: const Text(
                    'What did you eat or do? Paste your WOD too.',
                  ),
                  minHeight: 72,
                  maxHeight: 220,
                  resizable: false,
                  decoration: const ShadDecoration(
                    border: ShadBorder.none,
                    focusedBorder: ShadBorder.none,
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Icon(
                      LucideIcons.sparkles,
                      size: 14,
                      color: theme.colorScheme.mutedForeground,
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        'Meals, workouts, steps, weight',
                        style: theme.textTheme.muted.copyWith(fontSize: 12),
                      ),
                    ),
                    ShadButton(
                      key: const ValueKey('todayLogSend'),
                      size: ShadButtonSize.sm,
                      onPressed: isLogging ? null : _submit,
                      leading: isLogging
                          ? const SizedBox.square(
                              dimension: 14,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Icon(LucideIcons.arrowUp, size: 16),
                      child: Text(isLogging ? 'Reading' : 'Log it'),
                    ),
                  ],
                ),
              ],
            ),
          ),
          if (errorMessage.isNotEmpty) ...[
            const SizedBox(height: 12),
            ShadAlert.destructive(
              icon: const Icon(LucideIcons.info),
              description: Text(errorMessage),
            ),
          ],
          if (question.isNotEmpty) ...[
            const SizedBox(height: 12),
            ShadAlert(
              icon: const Icon(LucideIcons.messageCircleQuestion),
              title: const Text('Quick question'),
              description: Text(question),
              trailing: ShadIconButton.ghost(
                icon: const Icon(LucideIcons.x, size: 16),
                onPressed: () => setState(() => question = ''),
              ),
            ),
          ],
          if (considering.isNotEmpty) ...[
            const SectionLabel('If you add'),
            ConsideringPanel(
              options: considering,
              balance: state.balanceFor(today),
              hasMaintenance: state.maintenanceFor(today) != null,
              onAte: _ate,
            ),
          ],
          if (workouts.isNotEmpty) ...[
            const SectionLabel('Training'),
            ShadCard(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
              child: Column(
                children: [
                  for (final workout in workouts)
                    WorkoutRow(
                      workout: workout,
                      overridden: state.isActivityOverridden(workout),
                    ),
                ],
              ),
            ),
          ],
          SectionLabel(
            'Food',
            trailing: foods.isEmpty
                ? null
                : '${foods.length} items · ${_thousands(eaten.calories)} kcal',
          ),
          if (foods.isEmpty)
            ShadCard(
              child: Text(
                'Nothing logged yet. Type your meals above, as loosely as you '
                'like.',
                style: theme.textTheme.muted,
              ),
            )
          else
            ShadCard(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
              child: Column(
                children: [
                  for (final entry in foods)
                    Dismissible(
                      key: ValueKey(entry.id),
                      direction: DismissDirection.endToStart,
                      onDismissed: (_) => state.deleteEntry(entry.id),
                      background: Container(
                        alignment: Alignment.centerRight,
                        padding: const EdgeInsets.only(right: 8),
                        child: Icon(
                          LucideIcons.trash2,
                          color: theme.colorScheme.destructive,
                        ),
                      ),
                      child: ListRow(
                        title: entry.name,
                        subtitle: entry.notes,
                        trailing: Text(
                          _thousands(entry.nutrition.calories),
                          style: theme.textTheme.p.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        onTap: () => showFoodSheet(
                          context,
                          entry: entry,
                          state: state,
                          auth: widget.auth,
                        ),
                      ),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class BalanceCard extends StatelessWidget {
  const BalanceCard({super.key, required this.state, required this.date});

  final SculptusState state;
  final DateTime date;

  @override
  Widget build(BuildContext context) {
    final theme = ShadTheme.of(context);
    final eaten = state.consumedFor(date);
    final maintenance = state.maintenanceFor(date);
    final balance = state.balanceFor(date);
    final steps = state.stepsFor(date);
    final training = state.activityBurnFor(date);
    final label = maintenance == null
        ? (balance >= 0 ? 'calories left' : 'calories over')
        : (balance >= 0 ? 'calorie deficit' : 'calorie surplus');
    final budget = maintenance ?? (eaten.calories + balance);
    final progress = budget <= 0
        ? 0.0
        : (eaten.calories / budget).clamp(0.0, 1.0).toDouble();

    return ShadCard(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Flexible(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    _thousands(balance.abs()),
                    style: theme.textTheme.h1Large.copyWith(
                      fontWeight: FontWeight.w800,
                      height: 1,
                      color: balance >= 0
                          ? theme.colorScheme.foreground
                          : theme.colorScheme.destructive,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Flexible(
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Text(label, style: theme.textTheme.muted),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          ShadProgress(value: progress, minHeight: 8),
          const SizedBox(height: 8),
          Row(
            children: [
              Text(
                'Eaten ${_thousands(eaten.calories)}',
                style: theme.textTheme.small,
              ),
              const Spacer(),
              Text(
                maintenance == null
                    ? 'Budget ${_thousands(budget)}'
                    : '~${_thousands(maintenance)} burned',
                style: theme.textTheme.small,
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              StatTile(
                icon: LucideIcons.beef,
                label: 'protein',
                value: '${eaten.protein.round()}g',
              ),
              const SizedBox(width: 8),
              StatTile(
                icon: LucideIcons.footprints,
                label: 'steps',
                value: _thousands(steps),
              ),
              const SizedBox(width: 8),
              StatTile(
                icon: LucideIcons.flame,
                label: 'training',
                value: _thousands(training),
                color: _gold,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class WeightStrip extends StatelessWidget {
  const WeightStrip({
    super.key,
    required this.state,
    required this.date,
    required this.onOpen,
    required this.onWeighIn,
  });

  final SculptusState state;
  final DateTime date;
  final VoidCallback onOpen;
  final VoidCallback onWeighIn;

  @override
  Widget build(BuildContext context) {
    final theme = ShadTheme.of(context);
    final trend = state.weightTrendFor(date);
    final change = state.weeklyWeightChange(date);
    final weighedToday = state.weights.any(
      (entry) => _dateKey(entry.date) == _dateKey(date),
    );

    return ShadCard(
      padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
      child: InkWell(
        onTap: onOpen,
        child: Row(
          children: [
            const IconBubble(LucideIcons.scale),
            const SizedBox(width: 12),
            Expanded(
              child: trend == null
                  ? Text(
                      'Log a weigh-in to start your trend',
                      style: theme.textTheme.p,
                    )
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${trend.toStringAsFixed(1)} lb',
                          style: theme.textTheme.large.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        Text(
                          change == null
                              ? '7-day average'
                              : '7-day average · ${change <= 0 ? '' : '+'}'
                                    '${change.toStringAsFixed(1)} this week',
                          style: theme.textTheme.muted.copyWith(fontSize: 12),
                        ),
                      ],
                    ),
            ),
            ShadButton.outline(
              key: const ValueKey('weighInButton'),
              size: ShadButtonSize.sm,
              onPressed: onWeighIn,
              leading: Icon(
                weighedToday ? LucideIcons.check : LucideIcons.plus,
                size: 14,
              ),
              child: Text(weighedToday ? 'Weighed' : 'Weigh in'),
            ),
          ],
        ),
      ),
    );
  }
}

class WorkoutRow extends StatelessWidget {
  const WorkoutRow({
    super.key,
    required this.workout,
    required this.overridden,
  });

  final ActivityEntry workout;
  final bool overridden;

  @override
  Widget build(BuildContext context) {
    final theme = ShadTheme.of(context);
    final isWod = workout.id.startsWith('wod-');
    final isWhoop = workout.id.startsWith('whoop-');
    final subtitle = [
      if (isWod) 'Estimated from the work',
      if (isWhoop && overridden) 'Not counted: using your WOD estimate',
      if (workout.minutes > 0) '${workout.minutes} min',
      if (isWod && workout.notes.isNotEmpty) workout.notes,
    ].join(' · ');
    return ListRow(
      leading: IconBubble(
        isWhoop ? LucideIcons.watch : LucideIcons.dumbbell,
        color: _gold,
      ),
      title: workout.name,
      subtitle: subtitle,
      trailing: Text(
        '-${_thousands(workout.caloriesBurned)}',
        style: theme.textTheme.p.copyWith(
          fontWeight: FontWeight.w600,
          decoration: overridden ? TextDecoration.lineThrough : null,
          color: overridden ? theme.colorScheme.mutedForeground : null,
        ),
      ),
    );
  }
}

class ConsideringPanel extends StatelessWidget {
  const ConsideringPanel({
    super.key,
    required this.options,
    required this.balance,
    required this.hasMaintenance,
    required this.onAte,
  });

  final List<LoggedFood> options;
  final int balance;
  final bool hasMaintenance;
  final ValueChanged<LoggedFood> onAte;

  @override
  Widget build(BuildContext context) {
    return ShadCard(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
      child: Column(
        children: [
          for (final food in options)
            ListRow(
              leading: const IconBubble(LucideIcons.utensils),
              title: food.name,
              subtitle: _afterText(food),
              trailing: ShadButton.secondary(
                size: ShadButtonSize.sm,
                onPressed: () => onAte(food),
                child: const Text('Ate it'),
              ),
            ),
        ],
      ),
    );
  }

  String _afterText(LoggedFood food) {
    final after = balance - food.calories;
    final protein = food.proteinGrams > 0
        ? ' · ${_formatNumber(food.proteinGrams.roundToDouble())}g protein'
        : '';
    final label = hasMaintenance
        ? (after >= 0 ? 'deficit ${after.abs()}' : 'surplus ${after.abs()}')
        : (after >= 0 ? '${after.abs()} left' : '${after.abs()} over');
    return '+${food.calories}$protein · $label';
  }
}

Future<void> showFoodSheet(
  BuildContext context, {
  required DiaryEntry entry,
  required SculptusState state,
  required AuthController auth,
}) {
  return showShadSheet<void>(
    context: context,
    side: ShadSheetSide.bottom,
    builder: (context) => FoodSheet(entry: entry, state: state, auth: auth),
  );
}

class FoodSheet extends StatefulWidget {
  const FoodSheet({
    super.key,
    required this.entry,
    required this.state,
    required this.auth,
  });

  final DiaryEntry entry;
  final SculptusState state;
  final AuthController auth;

  @override
  State<FoodSheet> createState() => _FoodSheetState();
}

class _FoodSheetState extends State<FoodSheet> {
  late final name = TextEditingController(text: widget.entry.name);
  late final calories = TextEditingController(
    text: '${widget.entry.nutrition.calories}',
  );
  late final protein = TextEditingController(
    text: _formatNumber(widget.entry.nutrition.protein.roundToDouble()),
  );
  bool saving = false;

  @override
  void dispose() {
    name.dispose();
    calories.dispose();
    protein.dispose();
    super.dispose();
  }

  Future<void> _saveMeal() async {
    final meal = SavedMeal(
      name: name.text.trim(),
      calories: _readInt(calories.text),
      proteinGrams: _readDouble(protein.text),
    );
    if (meal.name.isEmpty) {
      return;
    }
    setState(() => saving = true);
    final navigator = Navigator.of(context);
    final messenger = ShadSonner.of(context);
    try {
      await MealsApiClient(
        widget.auth.authBackendUrl,
        widget.auth.session?.backendToken ?? '',
      ).save(meal);
      navigator.pop();
      messenger.show(
        ShadToast(
          title: Text('Saved ${meal.name}'),
          description: Text(
            'It counts as ${_thousands(meal.calories)} kcal whenever you '
            'mention it.',
          ),
        ),
      );
    } catch (error) {
      setState(() => saving = false);
      messenger.show(ShadToast.destructive(description: Text('$error')));
    }
  }

  Future<void> _delete() async {
    await widget.state.deleteEntry(widget.entry.id);
    if (mounted) {
      Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = ShadTheme.of(context);
    final entry = widget.entry;
    return ShadSheet(
      title: Text(entry.name),
      description: entry.notes.isEmpty ? null : Text(entry.notes),
      actions: [
        ShadButton(
          key: const ValueKey('foodSaveMeal'),
          onPressed: saving ? null : _saveMeal,
          leading: const Icon(LucideIcons.bookmarkPlus, size: 16),
          child: const Text('Save as my meal'),
        ),
        ShadButton.ghost(
          onPressed: _delete,
          foregroundColor: theme.colorScheme.destructive,
          leading: const Icon(LucideIcons.trash2, size: 16),
          child: const Text('Remove from today'),
        ),
      ],
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                StatTile(
                  icon: LucideIcons.flame,
                  label: 'calories',
                  value: _thousands(entry.nutrition.calories),
                  color: _gold,
                ),
                const SizedBox(width: 8),
                StatTile(
                  icon: LucideIcons.beef,
                  label: 'protein',
                  value: '${entry.nutrition.protein.round()}g',
                ),
              ],
            ),
            const SizedBox(height: 20),
            Text(
              'Save it as one of your meals',
              style: theme.textTheme.p.copyWith(fontWeight: FontWeight.w600),
            ),
            Text(
              'Name it the way you type it and fix the numbers. Sculptus '
              'will use them exactly from now on.',
              style: theme.textTheme.muted.copyWith(fontSize: 13),
            ),
            const SizedBox(height: 12),
            ShadInput(
              key: const ValueKey('mealName'),
              controller: name,
              placeholder: const Text('Mexican bowl'),
              leading: const Icon(LucideIcons.utensils, size: 16),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: ShadInput(
                    key: const ValueKey('mealCalories'),
                    controller: calories,
                    keyboardType: TextInputType.number,
                    trailing: const Text('kcal'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: ShadInput(
                    key: const ValueKey('mealProtein'),
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
    );
  }
}
