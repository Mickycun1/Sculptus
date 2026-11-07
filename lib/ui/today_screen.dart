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
  final nameText = TextEditingController();
  bool isLogging = false;
  String errorMessage = '';
  String question = '';
  List<LoggedFood> considering = const [];
  List<LogPhoto> photos = const [];

  Future<void> _addPhoto() async {
    final source = await showShadSheet<ImageSource>(
      context: context,
      side: ShadSheetSide.bottom,
      builder: (context) => ShadSheet(
        title: const Text('Add a photo'),
        description: const Text(
          'Your plate, a food label, a screenshot of today\'s workout in '
          'Wodify, or the whiteboard. Sculptus reads it with your log.',
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              ShadButton.outline(
                onPressed: () => Navigator.of(context).pop(ImageSource.gallery),
                leading: const Icon(LucideIcons.images, size: 16),
                child: const Text('Choose a screenshot'),
              ),
              const SizedBox(height: 8),
              ShadButton.outline(
                onPressed: () => Navigator.of(context).pop(ImageSource.camera),
                leading: const Icon(LucideIcons.camera, size: 16),
                child: const Text('Take a photo'),
              ),
            ],
          ),
        ),
      ),
    );
    if (source == null) {
      return;
    }
    final picked = await ImagePicker().pickImage(
      source: source,
      maxWidth: 1600,
      maxHeight: 1600,
      imageQuality: 80,
    );
    if (picked == null) {
      return;
    }
    final bytes = await picked.readAsBytes();
    final mediaType =
        picked.mimeType ??
        (picked.name.toLowerCase().endsWith('.png')
            ? 'image/png'
            : 'image/jpeg');
    setState(() {
      photos = [
        ...photos,
        LogPhoto(bytes: bytes, mediaType: mediaType),
      ].take(3).toList();
    });
  }

  DateTime today = _dateOnly(DateTime.now());

  bool get isToday => _dateKey(today) == _dateKey(DateTime.now());

  void _goTo(DateTime day) {
    final now = _dateOnly(DateTime.now());
    final next = _dateOnly(day).isAfter(now) ? now : _dateOnly(day);
    setState(() {
      today = next;
      question = '';
      considering = const [];
      errorMessage = '';
    });
    if (widget.state.whoop.connected) {
      _syncWhoop();
    }
  }

  Future<void> _pickDate() async {
    final now = _dateOnly(DateTime.now());
    final picked = await showShadDialog<DateTime>(
      context: context,
      builder: (context) => ShadDialog(
        title: const Text('Go to a day'),
        child: ShadCalendar(
          selected: today,
          initialMonth: today,
          toMonth: now,
          selectableDayPredicate: (day) => !_dateOnly(day).isAfter(now),
          onChanged: (day) {
            if (day != null) {
              Navigator.of(context).pop(day);
            }
          },
        ),
      ),
    );
    if (picked != null) {
      _goTo(picked);
    }
  }

  Future<void> _addRecent() async {
    await showShadSheet<void>(
      context: context,
      side: ShadSheetSide.bottom,
      builder: (context) =>
          RecentsSheet(state: widget.state, auth: widget.auth, date: today),
    );
  }

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
    nameText.dispose();
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
          'Sculptus sends what you type here, and any photos you add, to '
          'Anthropic\'s Claude AI to '
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
    if ((text.isEmpty && photos.isEmpty) || isLogging) {
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
        photos: photos,
      );
      await state.applyLog(log, today);
      logText.clear();
      photos = const [];
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

  Future<void> _chooseBurn(DateTime day) async {
    final state = widget.state;
    final whoop = state
        .activitiesFor(day)
        .where(
          (entry) =>
              entry.id.startsWith('whoop-') ||
              entry.id.startsWith('log-workout-'),
        )
        .fold<int>(0, (sum, entry) => sum + entry.caloriesBurned);
    final wod = state
        .activitiesFor(day)
        .where((entry) => entry.id.startsWith('wod'))
        .fold<int>(0, (sum, entry) => sum + entry.caloriesBurned);
    final preferWod = await showShadDialog<bool>(
      context: context,
      builder: (context) => ShadDialog(
        title: const Text('Which burn counts today?'),
        description: const Text(
          'WHOOP measured your heart rate. The WOD estimate comes from the work '
          'you logged. Only one counts toward your deficit.',
        ),
        actions: [
          ShadButton.outline(
            key: const ValueKey('useWhoopBurn'),
            onPressed: () => Navigator.of(context).pop(false),
            child: Text('Tracker · ${_thousands(whoop)}'),
          ),
          ShadButton(
            key: const ValueKey('useWodBurn'),
            onPressed: () => Navigator.of(context).pop(true),
            child: Text('WOD estimate · ${_thousands(wod)}'),
          ),
        ],
      ),
    );
    if (preferWod != null) {
      await state.setPrefersWod(day, preferWod);
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
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 40),
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    GestureDetector(
                      key: const ValueKey('datePicker'),
                      onTap: _pickDate,
                      child: Row(
                        children: [
                          Text(
                            isToday ? 'Today' : _weekdays[today.weekday - 1],
                            style: theme.textTheme.h3.copyWith(
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          const SizedBox(width: 4),
                          Icon(
                            LucideIcons.chevronDown,
                            size: 18,
                            color: theme.colorScheme.mutedForeground,
                          ),
                        ],
                      ),
                    ),
                    Text(_displayDate(today), style: theme.textTheme.muted),
                  ],
                ),
              ),
              ShadIconButton.ghost(
                key: const ValueKey('previousDay'),
                icon: const Icon(LucideIcons.chevronLeft, size: 20),
                onPressed: () =>
                    _goTo(DateTime(today.year, today.month, today.day - 1)),
              ),
              ShadIconButton.ghost(
                key: const ValueKey('nextDay'),
                icon: const Icon(LucideIcons.chevronRight, size: 20),
                onPressed: isToday
                    ? null
                    : () => _goTo(
                        DateTime(today.year, today.month, today.day + 1),
                      ),
              ),
              const SizedBox(width: 4),
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
          if (widget.auth.session?.shortName == 'Athlete') ...[
            ShadCard(
              padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
              child: Row(
                children: [
                  Expanded(
                    child: ShadInput(
                      key: const ValueKey('todayNameField'),
                      controller: nameText,
                      placeholder: const Text('What should we call you?'),
                      leading: const Icon(LucideIcons.user, size: 16),
                      onSubmitted: (value) =>
                          widget.auth.updateDisplayName(value),
                    ),
                  ),
                  const SizedBox(width: 8),
                  ShadButton(
                    size: ShadButtonSize.sm,
                    onPressed: () =>
                        widget.auth.updateDisplayName(nameText.text),
                    child: const Text('Save'),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
          ],
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
                    ShadIconButton.ghost(
                      key: const ValueKey('todayAddPhoto'),
                      icon: const Icon(LucideIcons.imagePlus, size: 18),
                      onPressed: isLogging || photos.length >= 3
                          ? null
                          : _addPhoto,
                    ),
                    Expanded(
                      child: photos.isEmpty
                          ? Text(
                              'Photo of food, a label or your WOD',
                              style: theme.textTheme.muted.copyWith(
                                fontSize: 12,
                              ),
                            )
                          : Wrap(
                              spacing: 6,
                              children: [
                                for (final photo in photos)
                                  GestureDetector(
                                    onTap: () => setState(() {
                                      photos = [
                                        for (final other in photos)
                                          if (other != photo) other,
                                      ];
                                    }),
                                    child: Stack(
                                      children: [
                                        ClipRRect(
                                          borderRadius: BorderRadius.circular(
                                            8,
                                          ),
                                          child: Image.memory(
                                            Uint8List.fromList(photo.bytes),
                                            width: 40,
                                            height: 40,
                                            fit: BoxFit.cover,
                                          ),
                                        ),
                                        const Positioned(
                                          right: 2,
                                          top: 2,
                                          child: Icon(
                                            LucideIcons.circleX,
                                            size: 14,
                                            color: Colors.white,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                              ],
                            ),
                    ),
                    ShadButton.outline(
                      key: const ValueKey('todayRecents'),
                      size: ShadButtonSize.sm,
                      onPressed: isLogging ? null : _addRecent,
                      leading: const Icon(LucideIcons.history, size: 14),
                      child: const Text('Recents'),
                    ),
                    const SizedBox(width: 6),
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
                      onTap: state.hasWodAndWhoop(today)
                          ? () => _chooseBurn(today)
                          : null,
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
              if (maintenance != null) ...[
                const SizedBox(width: 4),
                BurnInfoButton(state: state, date: date),
              ],
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

class BurnInfoButton extends StatefulWidget {
  const BurnInfoButton({super.key, required this.state, required this.date});

  final SculptusState state;
  final DateTime date;

  @override
  State<BurnInfoButton> createState() => _BurnInfoButtonState();
}

class _BurnInfoButtonState extends State<BurnInfoButton> {
  final controller = ShadPopoverController();

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = ShadTheme.of(context);
    final parts = widget.state.burnBreakdownFor(widget.date);
    final steps = widget.state.stepsFor(widget.date);
    final small = theme.textTheme.small;
    final muted = theme.textTheme.muted.copyWith(fontSize: 12);

    Widget line(String label, int value, String detail) => Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: Text(label, style: small)),
              Text(_thousands(value), style: small),
            ],
          ),
          Text(detail, style: muted),
        ],
      ),
    );

    return ShadPopover(
      controller: controller,
      popover: (context) => SizedBox(
        width: 260,
        child: parts == null
            ? const SizedBox.shrink()
            : Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'How your burn is estimated',
                    style: small.copyWith(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 10),
                  line(
                    'Resting',
                    parts.resting,
                    'Mifflin-St Jeor from your ${parts.weight.toStringAsFixed(1)} lb '
                        '7-day average, height, age and sex, ×1.2 for daily living',
                  ),
                  line(
                    'Training',
                    parts.training,
                    'WHOOP or your WOD estimate, whichever counts today',
                  ),
                  line(
                    'Walking',
                    parts.walking,
                    steps > 5000
                        ? '${_thousands(steps - 5000)} steps over 5,000, at about '
                              '0.045 kcal each'
                        : 'Counts steps over 5,000',
                  ),
                  const ShadSeparator.horizontal(),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Estimated burn',
                          style: small.copyWith(fontWeight: FontWeight.w700),
                        ),
                      ),
                      Text(
                        _thousands(
                          parts.resting + parts.training + parts.walking,
                        ),
                        style: small.copyWith(fontWeight: FontWeight.w700),
                      ),
                    ],
                  ),
                ],
              ),
      ),
      child: GestureDetector(
        key: const ValueKey('burnInfo'),
        onTap: controller.toggle,
        child: Icon(
          LucideIcons.info,
          size: 14,
          color: theme.colorScheme.mutedForeground,
        ),
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
    this.onTap,
  });

  final ActivityEntry workout;
  final bool overridden;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = ShadTheme.of(context);
    final isWod = workout.id.startsWith('wod');
    final isWhoop =
        workout.id.startsWith('whoop-') ||
        workout.id.startsWith('log-workout-');
    final subtitle = [
      if (isWhoop && workout.notes.startsWith('WHOOP')) workout.notes,
      if (isWod) 'Estimated from the work',
      if (overridden)
        isWhoop
            ? 'Not counted: using your WOD estimate. Tap to change'
            : 'Not counted: using your tracker. Tap to use this instead',
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
      onTap: onTap,
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
  return Navigator.of(context).push<void>(
    MaterialPageRoute(
      builder: (context) => FoodPage(entry: entry, state: state, auth: auth),
    ),
  );
}

SavedMeal? _templateFor(DiaryEntry entry, List<SavedMeal> meals) {
  final name = entry.name.trim().toLowerCase();
  for (final meal in meals) {
    if (meal.name.trim().toLowerCase() == name) {
      return meal;
    }
  }
  if (!entry.notes.toLowerCase().contains('saved meal')) {
    return null;
  }
  for (final meal in meals) {
    if (name.contains(meal.name.trim().toLowerCase())) {
      return meal;
    }
  }
  return null;
}

class FoodPage extends StatefulWidget {
  const FoodPage({
    super.key,
    required this.entry,
    required this.state,
    required this.auth,
    this.mealsClient,
  });

  final DiaryEntry entry;
  final SculptusState state;
  final AuthController auth;
  final MealsApiClient? mealsClient;

  @override
  State<FoodPage> createState() => _FoodPageState();
}

class _FoodPageState extends State<FoodPage> {
  late DiaryEntry entry = widget.entry;
  final change = TextEditingController();
  late final name = TextEditingController(text: widget.entry.name);
  SavedMeal? template;
  bool updateTemplate = false;
  bool working = false;
  bool saving = false;
  String errorMessage = '';

  MealsApiClient get client =>
      widget.mealsClient ??
      MealsApiClient(
        widget.auth.authBackendUrl,
        widget.auth.session?.backendToken ?? '',
      );

  @override
  void initState() {
    super.initState();
    client.list().then((meals) {
      if (mounted) {
        setState(() => template = _templateFor(entry, meals));
      }
    }, onError: (_) {});
  }

  @override
  void dispose() {
    change.dispose();
    name.dispose();
    super.dispose();
  }

  String get _earlierChanges {
    const prefix = 'saved meal · today: ';
    return entry.notes.startsWith(prefix)
        ? entry.notes.substring(prefix.length)
        : '';
  }

  String _todayNotes(String note) {
    final earlier = _earlierChanges;
    return 'saved meal · today: ${earlier.isEmpty ? note : '$earlier, $note'}';
  }

  String _prompt(String note) {
    final template = this.template;
    if (template != null) {
      return 'Recalculate one serving of a saved meal with today\'s change. '
          'Log exactly one food named "${template.name}", nothing else.\n'
          'Saved meal: ${template.name}, ${template.calories} kcal and '
          '${_formatNumber(template.proteinGrams)}g protein per portion'
          '${template.ingredients.isEmpty ? '' : '. The whole batch is: ${template.ingredients.replaceAll('\n', ', ')}, making ${template.portions} portion(s)'}.\n'
          '${_earlierChanges.isEmpty ? '' : 'Earlier changes today, keep them: $_earlierChanges.\n'}'
          'New change: $note';
    }
    return 'Correct one food that was logged wrong. Log only the corrected '
        'food or foods, nothing else.\n'
        'Logged as: ${entry.name}, ${entry.nutrition.calories} kcal'
        '${entry.notes.isEmpty ? '' : ' (${entry.notes})'}.\n'
        'What it actually was: $note';
  }

  Future<void> _apply() async {
    final note = change.text.trim();
    if (note.isEmpty || working) {
      return;
    }
    FocusScope.of(context).unfocus();
    setState(() {
      working = true;
      errorMessage = '';
    });
    final sonner = ShadSonner.of(context);
    final before = entry.nutrition.calories;
    try {
      final log = await LogApiClient(
        widget.auth.authBackendUrl,
        widget.auth.session?.backendToken ?? '',
      ).parse(_prompt(note));
      if (log.foods.isEmpty) {
        setState(
          () => errorMessage = 'Could not work that out. Add a bit more.',
        );
        return;
      }
      final template = this.template;
      final foods = template == null
          ? log.foods
          : [
              LoggedFood(
                name: template.name,
                calories: log.foods.fold(0, (sum, food) => sum + food.calories),
                caloriesLow: 0,
                caloriesHigh: 0,
                proteinGrams: log.foods.fold(
                  0.0,
                  (sum, food) => sum + food.proteinGrams,
                ),
                assumption: _todayNotes(note),
              ),
            ];
      final oldIds = {for (final item in widget.state.entries) item.id};
      await widget.state.deleteEntry(entry.id);
      await widget.state.applyLog(LoggedDay(foods: foods), entry.date);
      final added = widget.state.entries
          .where((item) => !oldIds.contains(item.id))
          .toList();
      if (template != null && updateTemplate && added.isNotEmpty) {
        final updated = SavedMeal(
          name: template.name,
          calories: added.first.nutrition.calories,
          proteinGrams: added.first.nutrition.protein,
          ingredients: [
            if (template.ingredients.isNotEmpty) template.ingredients,
            template.portions > 1 ? 'Each portion: $note' : note,
          ].join('\n'),
          portions: template.portions,
        );
        await client.save(updated);
        this.template = updated;
      }
      final after = added.fold<int>(
        0,
        (sum, item) => sum + item.nutrition.calories,
      );
      setState(() {
        if (added.isNotEmpty) {
          entry = added.first;
          name.text = entry.name;
        }
        change.clear();
      });
      sonner.show(
        ShadToast(
          title: Text(
            template != null && updateTemplate
                ? 'Updated today and your saved ${template.name}'
                : 'Updated',
          ),
          description: Text(
            '${_thousands(before)} kcal is now ${_thousands(after)} kcal.',
          ),
        ),
      );
    } catch (error) {
      setState(() => errorMessage = error.toString());
    } finally {
      if (mounted) {
        setState(() => working = false);
      }
    }
  }

  Future<void> _saveAsMeal() async {
    final meal = SavedMeal(
      name: name.text.trim(),
      calories: entry.nutrition.calories,
      proteinGrams: entry.nutrition.protein,
    );
    if (meal.name.isEmpty) {
      return;
    }
    setState(() => saving = true);
    final sonner = ShadSonner.of(context);
    try {
      await client.save(meal);
      setState(() => template = meal);
      sonner.show(
        ShadToast(
          title: Text('Saved ${meal.name}'),
          description: const Text('Add it again any time from Recents.'),
        ),
      );
    } catch (error) {
      sonner.show(ShadToast.destructive(description: Text('$error')));
    } finally {
      if (mounted) {
        setState(() => saving = false);
      }
    }
  }

  Future<void> _remove() async {
    await widget.state.deleteEntry(entry.id);
    if (mounted) {
      Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = ShadTheme.of(context);
    final template = this.template;
    final hint = theme.textTheme.muted.copyWith(fontSize: 12);
    final ingredients =
        template?.ingredients
            .split(RegExp(r'[\n,]+'))
            .map((line) => line.trim())
            .where((line) => line.isNotEmpty)
            .toList() ??
        const <String>[];
    return Scaffold(
      backgroundColor: theme.colorScheme.background,
      body: SafeArea(
        child: ListView(
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
          children: [
            Row(
              children: [
                ShadIconButton.ghost(
                  icon: const Icon(LucideIcons.chevronLeft),
                  onPressed: () => Navigator.of(context).pop(),
                ),
                Expanded(
                  child: Text(
                    template == null ? entry.name : 'Today\'s ${template.name}',
                    style: theme.textTheme.large,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            if (entry.notes.isNotEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(4, 0, 4, 8),
                child: Text(entry.notes, style: theme.textTheme.muted),
              ),
            const SizedBox(height: 8),
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
            if (template != null && ingredients.isNotEmpty) ...[
              const SectionLabel('In your saved meal'),
              ShadCard(
                padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (final line in ingredients)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 2),
                        child: Text(line, style: theme.textTheme.small),
                      ),
                    if (template.portions > 1)
                      Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: Text(
                          'Makes ${template.portions} portions. This is one.',
                          style: hint,
                        ),
                      ),
                  ],
                ),
              ),
            ],
            SectionLabel(
              template != null
                  ? 'Change today\'s'
                  : 'Not right? Say what it was',
            ),
            ShadInput(
              key: const ValueKey('foodChange'),
              controller: change,
              placeholder: Text(
                template != null
                    ? 'Add 15g honey, swap whey for Greek yogurt'
                    : 'It was Greek yogurt with sriracha, not mayo',
              ),
              onSubmitted: (_) => _apply(),
            ),
            if (template != null)
              Padding(
                padding: const EdgeInsets.only(top: 10),
                child: Row(
                  children: [
                    ShadSwitch(
                      key: const ValueKey('updateTemplate'),
                      value: updateTemplate,
                      onChanged: (value) =>
                          setState(() => updateTemplate = value),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Also update my saved ${template.name}',
                        style: theme.textTheme.small,
                      ),
                    ),
                  ],
                ),
              ),
            if (errorMessage.isNotEmpty) ...[
              const SizedBox(height: 10),
              ShadAlert.destructive(
                icon: const Icon(LucideIcons.info),
                description: Text(errorMessage),
              ),
            ],
            const SizedBox(height: 12),
            ShadButton(
              key: const ValueKey('foodApply'),
              height: 46,
              onPressed: working ? null : _apply,
              leading: working
                  ? const SizedBox.square(
                      dimension: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(LucideIcons.refreshCw, size: 16),
              child: Text(working ? 'Working it out' : 'Update'),
            ),
            if (template == null) ...[
              const SectionLabel('Keep it as one of your meals'),
              ShadInput(
                key: const ValueKey('mealName'),
                controller: name,
                placeholder: const Text('Name it the way you type it'),
                leading: const Icon(LucideIcons.utensils, size: 16),
              ),
              const SizedBox(height: 8),
              ShadButton.outline(
                key: const ValueKey('foodSaveMeal'),
                onPressed: saving ? null : _saveAsMeal,
                leading: const Icon(LucideIcons.bookmarkPlus, size: 16),
                child: const Text('Save as my meal'),
              ),
            ],
            const SizedBox(height: 24),
            ShadButton.ghost(
              onPressed: _remove,
              foregroundColor: theme.colorScheme.destructive,
              leading: const Icon(LucideIcons.trash2, size: 16),
              child: const Text('Remove from this day'),
            ),
          ],
        ),
      ),
    );
  }
}

class RecentsSheet extends StatefulWidget {
  const RecentsSheet({
    super.key,
    required this.state,
    required this.auth,
    required this.date,
    this.mealsClient,
  });

  final SculptusState state;
  final AuthController auth;
  final DateTime date;
  final MealsApiClient? mealsClient;

  @override
  State<RecentsSheet> createState() => _RecentsSheetState();
}

class _RecentsSheetState extends State<RecentsSheet> {
  List<SavedMeal> meals = const [];
  final added = <String>{};

  @override
  void initState() {
    super.initState();
    final client =
        widget.mealsClient ??
        MealsApiClient(
          widget.auth.authBackendUrl,
          widget.auth.session?.backendToken ?? '',
        );
    client.list().then((result) {
      if (mounted) {
        setState(() => meals = result);
      }
    }, onError: (_) {});
  }

  Future<void> _add(
    String name,
    int calories,
    double protein,
    String note,
  ) async {
    await widget.state.applyLog(
      LoggedDay(
        foods: [
          LoggedFood(
            name: name,
            calories: calories,
            caloriesLow: 0,
            caloriesHigh: 0,
            proteinGrams: protein,
            assumption: note,
          ),
        ],
      ),
      widget.date,
    );
    setState(() => added.add(name.toLowerCase()));
  }

  Widget _row(
    String name,
    int calories,
    double protein,
    String note,
    IconData icon,
  ) {
    final theme = ShadTheme.of(context);
    final done = added.contains(name.toLowerCase());
    return ListRow(
      leading: IconBubble(icon),
      title: name,
      subtitle: '${_thousands(calories)} kcal · ${protein.round()}g protein',
      trailing: done
          ? Icon(LucideIcons.check, size: 18, color: theme.colorScheme.primary)
          : const Icon(LucideIcons.plus, size: 18),
      onTap: done ? null : () => _add(name, calories, protein, note),
    );
  }

  @override
  Widget build(BuildContext context) {
    final recents = widget.state.recentFoods(exclude: widget.date);
    return ShadSheet(
      title: const Text('Add again'),
      description: const Text('Tap to add it to this day. No typing needed.'),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.6,
        ),
        child: ListView(
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          shrinkWrap: true,
          children: [
            if (meals.isNotEmpty) ...[
              const SectionLabel('My meals'),
              for (final meal in meals)
                _row(
                  meal.name,
                  meal.calories,
                  meal.proteinGrams,
                  'saved meal',
                  LucideIcons.utensils,
                ),
            ],
            const SectionLabel('Recent'),
            if (recents.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Text(
                  'Foods you log show up here so you can add them again in one tap.',
                  style: ShadTheme.of(context).textTheme.muted,
                ),
              ),
            for (final entry in recents)
              _row(
                entry.name,
                entry.nutrition.calories,
                entry.nutrition.protein,
                entry.notes,
                LucideIcons.history,
              ),
          ],
        ),
      ),
    );
  }
}
