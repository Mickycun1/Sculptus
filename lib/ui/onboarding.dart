part of '../main.dart';

class WelcomeScreen extends StatefulWidget {
  const WelcomeScreen({super.key, required this.auth});

  final AuthController auth;

  @override
  State<WelcomeScreen> createState() => _WelcomeScreenState();
}

class _WelcomeScreenState extends State<WelcomeScreen> {
  bool? creating;

  void _open(bool create) {
    widget.auth.clearError();
    setState(() => creating = create);
  }

  @override
  Widget build(BuildContext context) {
    final creating = this.creating;
    if (creating != null) {
      return AuthScreen(
        key: ValueKey(creating),
        auth: widget.auth,
        startCreating: creating,
        onBack: () => setState(() => this.creating = null),
      );
    }
    final theme = ShadTheme.of(context);

    Widget point(IconData icon, String title, String body) => Padding(
      padding: const EdgeInsets.only(bottom: 18),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          IconBubble(icon),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: theme.textTheme.p.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                Text(body, style: theme.textTheme.muted),
              ],
            ),
          ),
        ],
      ),
    );

    return Scaffold(
      backgroundColor: theme.colorScheme.background,
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 440),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(24, 24, 24, 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Spacer(),
                  Center(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(22),
                      child: Image.asset(
                        'assets/icon.png',
                        width: 84,
                        height: 84,
                      ),
                    ),
                  ),
                  const SizedBox(height: 18),
                  Text(
                    'Sculptus',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.h2.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Know your real calorie deficit, every day.',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.muted,
                  ),
                  const SizedBox(height: 36),
                  point(
                    LucideIcons.messageSquareText,
                    'Type your day in one message',
                    'Meals, snacks, workouts and steps, as loosely as you like.',
                  ),
                  point(
                    LucideIcons.camera,
                    'Snap your plate or your WOD',
                    'Photos of food, labels or the whiteboard count too.',
                  ),
                  point(
                    LucideIcons.scale,
                    'See the trend that matters',
                    'Your deficit, protein and 7-day weight average.',
                  ),
                  const Spacer(),
                  ShadButton(
                    key: const ValueKey('welcomeGetStarted'),
                    height: 50,
                    onPressed: () => _open(true),
                    child: const Text('Get started'),
                  ),
                  const SizedBox(height: 8),
                  ShadButton.ghost(
                    key: const ValueKey('welcomeSignIn'),
                    onPressed: () => _open(false),
                    child: const Text('Sign in'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class SetupScreen extends StatefulWidget {
  const SetupScreen({
    super.key,
    required this.state,
    required this.auth,
    required this.onDone,
  });

  final SculptusState state;
  final AuthController auth;
  final VoidCallback onDone;

  @override
  State<SetupScreen> createState() => _SetupScreenState();
}

class _SetupScreenState extends State<SetupScreen> {
  late final name = TextEditingController(
    text: widget.auth.session?.shortName == 'Athlete'
        ? ''
        : widget.auth.session?.shortName ?? '',
  );
  final age = TextEditingController();
  final feet = TextEditingController();
  final inches = TextEditingController();
  final weight = TextEditingController();
  final goal = TextEditingController();
  String sex = 'male';
  int step = 0;
  String errorMessage = '';

  @override
  void dispose() {
    for (final controller in [name, age, feet, inches, weight, goal]) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> _next() async {
    FocusScope.of(context).unfocus();
    setState(() => errorMessage = '');
    if (step == 0) {
      if (name.text.trim().isEmpty) {
        setState(() => errorMessage = 'What should we call you?');
        return;
      }
      await widget.auth.updateDisplayName(name.text);
      setState(() => step = 1);
      return;
    }
    if (step == 1) {
      final years = _readInt(age.text);
      final height = _readInt(feet.text) * 12 + _readDouble(inches.text);
      if (years < 13 || years > 100 || height < 48 || height > 96) {
        setState(
          () => errorMessage = 'Add your age and height to estimate your burn.',
        );
        return;
      }
      await widget.state.updateGoals(
        widget.state.goals.copyWith(age: years, heightInches: height, sex: sex),
      );
      setState(() => step = 2);
      return;
    }
    final today = _readDouble(weight.text);
    final target = _readDouble(goal.text);
    if (today > 50 && today < 700) {
      await widget.state.setWeight(DateTime.now(), today);
    }
    if (target > 50 && target < 700) {
      await widget.state.updateGoals(
        widget.state.goals.copyWith(targetWeight: target),
      );
    }
    widget.onDone();
  }

  @override
  Widget build(BuildContext context) {
    final theme = ShadTheme.of(context);
    const titles = ['What should we call you?', 'About you', 'Your weight'];
    const blurbs = [
      'This is how Sculptus will greet you.',
      'Used to estimate the calories you burn at rest.',
      'Your 7-day average starts today. Both are optional.',
    ];

    Widget field(
      TextEditingController controller,
      String placeholder, {
      String? trailing,
      bool decimal = false,
      Key? key,
    }) => ShadInput(
      key: key,
      controller: controller,
      placeholder: Text(placeholder),
      keyboardType: TextInputType.numberWithOptions(decimal: decimal),
      trailing: trailing == null ? null : Text(trailing),
    );

    final body = switch (step) {
      0 => ShadInput(
        key: const ValueKey('setupName'),
        controller: name,
        autofocus: true,
        placeholder: const Text('Your name'),
        leading: const Icon(LucideIcons.user, size: 16),
        onSubmitted: (_) => _next(),
      ),
      1 => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          field(age, 'Age', trailing: 'years', key: const ValueKey('setupAge')),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: field(
                  feet,
                  'Height',
                  trailing: 'ft',
                  key: const ValueKey('setupFeet'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: field(
                  inches,
                  'Inches',
                  trailing: 'in',
                  decimal: true,
                  key: const ValueKey('setupInches'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              for (final option in const ['male', 'female']) ...[
                Expanded(
                  child: option == sex
                      ? ShadButton(
                          onPressed: () {},
                          child: Text(option == 'male' ? 'M' : 'F'),
                        )
                      : ShadButton.outline(
                          onPressed: () => setState(() => sex = option),
                          child: Text(option == 'male' ? 'M' : 'F'),
                        ),
                ),
                if (option == 'male') const SizedBox(width: 8),
              ],
            ],
          ),
        ],
      ),
      _ => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          field(
            weight,
            'Weight this morning',
            trailing: 'lb',
            decimal: true,
            key: const ValueKey('setupWeight'),
          ),
          const SizedBox(height: 10),
          field(goal, 'Goal weight', trailing: 'lb', decimal: true),
        ],
      ),
    };

    return Scaffold(
      backgroundColor: theme.colorScheme.background,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 12, 24, 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  if (step > 0)
                    ShadIconButton.ghost(
                      icon: const Icon(LucideIcons.chevronLeft),
                      onPressed: () => setState(() {
                        step--;
                        errorMessage = '';
                      }),
                    )
                  else
                    const SizedBox(width: 40, height: 40),
                  const Spacer(),
                  for (var i = 0; i < 3; i++)
                    Container(
                      width: i == step ? 22 : 8,
                      height: 8,
                      margin: const EdgeInsets.symmetric(horizontal: 3),
                      decoration: BoxDecoration(
                        color: i <= step
                            ? theme.colorScheme.primary
                            : theme.colorScheme.border,
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                  const Spacer(),
                  ShadButton.link(
                    key: const ValueKey('setupSkip'),
                    onPressed: widget.onDone,
                    child: const Text('Skip'),
                  ),
                ],
              ),
              const SizedBox(height: 32),
              Text(
                titles[step],
                style: theme.textTheme.h3.copyWith(fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 6),
              Text(blurbs[step], style: theme.textTheme.muted),
              const SizedBox(height: 24),
              body,
              if (errorMessage.isNotEmpty) ...[
                const SizedBox(height: 12),
                Text(
                  errorMessage,
                  style: theme.textTheme.small.copyWith(
                    color: theme.colorScheme.destructive,
                  ),
                ),
              ],
              const Spacer(),
              ShadButton(
                key: const ValueKey('setupContinue'),
                height: 50,
                onPressed: _next,
                child: Text(step == 2 ? 'Start logging' : 'Continue'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
