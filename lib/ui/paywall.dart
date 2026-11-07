part of '../main.dart';

class SubscriptionController extends ChangeNotifier
    with WidgetsBindingObserver {
  SubscriptionController({this.enabledOverride}) {
    WidgetsBinding.instance.addObserver(this);
  }

  final bool? enabledOverride;
  bool loaded = false;
  bool enforced = false;
  bool active = false;
  bool exempt = false;
  bool busy = false;
  String errorMessage = '';
  AuthController? _auth;
  String? _userId;

  bool get enabled => enabledOverride ?? enforced;

  bool get unlocked => !enabled || active || exempt;

  String get priceLabel => '\$4.99';

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && _auth != null && !unlocked) {
      refresh();
    }
  }

  Future<void> start(AuthController auth) async {
    final session = auth.session;
    if (session == null || _userId == session.userId) {
      return;
    }
    _auth = auth;
    _userId = session.userId;
    await refresh();
  }

  Future<void> refresh() async {
    final auth = _auth;
    if (auth == null) {
      return;
    }
    try {
      final json = await AuthBackendClient(auth.authBackendUrl).sendJson(
        'GET',
        '/api/subscription',
        const {},
        token: auth.session?.backendToken ?? '',
      );
      enforced = json['enforced'] == true;
      active = json['active'] == true;
      exempt = json['exempt'] == true;
      if (active) {
        errorMessage = '';
      }
    } catch (_) {
      enforced = false;
    }
    loaded = true;
    notifyListeners();
  }

  Future<void> subscribe() => _openBilling('/api/billing/checkout');

  Future<void> manage() => _openBilling('/api/billing/portal');

  Future<void> _openBilling(String path) async {
    final auth = _auth;
    if (auth == null || busy) {
      return;
    }
    busy = true;
    errorMessage = '';
    notifyListeners();
    try {
      final json = await AuthBackendClient(auth.authBackendUrl).sendJson(
        'POST',
        path,
        const {},
        token: auth.session?.backendToken ?? '',
      );
      final url = json['url'] as String? ?? '';
      if (url.isEmpty) {
        throw const AuthException('Payments are not available right now.');
      }
      await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
    } catch (error) {
      errorMessage = error.toString();
    } finally {
      busy = false;
      notifyListeners();
    }
  }

  Future<void> reset() async {
    _auth = null;
    _userId = null;
    enforced = false;
    active = false;
    exempt = false;
    loaded = false;
    notifyListeners();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }
}

class PaywallScreen extends StatelessWidget {
  const PaywallScreen({
    super.key,
    required this.subscription,
    required this.auth,
  });

  final SubscriptionController subscription;
  final AuthController auth;

  @override
  Widget build(BuildContext context) {
    final theme = ShadTheme.of(context);
    final muted = theme.textTheme.muted.copyWith(fontSize: 12);

    Widget point(IconData icon, String text) => Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: [
          Icon(icon, size: 18, color: theme.colorScheme.primary),
          const SizedBox(width: 12),
          Expanded(child: Text(text, style: theme.textTheme.p)),
        ],
      ),
    );

    return Scaffold(
      backgroundColor: theme.colorScheme.background,
      body: SafeArea(
        child: ListenableBuilder(
          listenable: subscription,
          builder: (context, _) => ListView(
            padding: const EdgeInsets.fromLTRB(24, 32, 24, 24),
            children: [
              Center(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(20),
                  child: Image.asset('assets/icon.png', width: 72, height: 72),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'Unlock Sculptus',
                textAlign: TextAlign.center,
                style: theme.textTheme.h3.copyWith(fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 6),
              Text(
                'Everything you need to hit your goal weight.',
                textAlign: TextAlign.center,
                style: theme.textTheme.muted,
              ),
              const SizedBox(height: 28),
              point(
                LucideIcons.sparkles,
                'Log meals and workouts in one message',
              ),
              point(
                LucideIcons.camera,
                'Photos of your plate, labels and WODs',
              ),
              point(LucideIcons.chefHat, 'Saved meals and batch meal prep'),
              point(LucideIcons.scale, 'Your real deficit and weight trend'),
              const SizedBox(height: 20),
              ShadCard(
                padding: const EdgeInsets.all(18),
                child: Column(
                  children: [
                    Text(
                      '${subscription.priceLabel} a month',
                      style: theme.textTheme.h4.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text('Cancel anytime.', style: muted),
                  ],
                ),
              ),
              if (subscription.errorMessage.isNotEmpty) ...[
                const SizedBox(height: 12),
                ShadAlert.destructive(
                  icon: const Icon(LucideIcons.info),
                  description: Text(subscription.errorMessage),
                ),
              ],
              const SizedBox(height: 16),
              ShadButton(
                key: const ValueKey('paywallSubscribe'),
                height: 50,
                onPressed: subscription.busy ? null : subscription.subscribe,
                child: subscription.busy
                    ? const SizedBox.square(
                        dimension: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Text('Subscribe with card'),
              ),
              const SizedBox(height: 6),
              ShadButton.ghost(
                key: const ValueKey('paywallCheckAgain'),
                onPressed: subscription.busy ? null : subscription.refresh,
                child: const Text('Check my subscription'),
              ),
              const SizedBox(height: 12),
              Text(
                'Secure checkout by Stripe opens in your browser. Your '
                'subscription renews monthly at ${subscription.priceLabel} '
                'until you cancel, which you can do anytime from Profile, '
                'Manage subscription.',
                textAlign: TextAlign.center,
                style: muted,
              ),
              const SizedBox(height: 10),
              Wrap(
                alignment: WrapAlignment.center,
                children: [
                  ShadButton.link(
                    size: ShadButtonSize.sm,
                    onPressed: () => launchUrl(
                      Uri.parse('https://dynafex.ai/sculptus_terms.html'),
                      mode: LaunchMode.externalApplication,
                    ),
                    child: const Text('Terms'),
                  ),
                  ShadButton.link(
                    size: ShadButtonSize.sm,
                    onPressed: () => launchUrl(
                      Uri.parse(
                        'https://dynafex.ai/sculptus_privacy_policy.html',
                      ),
                      mode: LaunchMode.externalApplication,
                    ),
                    child: const Text('Privacy'),
                  ),
                  ShadButton.link(
                    size: ShadButtonSize.sm,
                    onPressed: auth.signOut,
                    child: const Text('Sign out'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
