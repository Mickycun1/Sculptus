part of '../main.dart';

class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key, required this.auth});

  final AuthController auth;

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  final name = TextEditingController();
  final email = TextEditingController();
  final password = TextEditingController();
  bool creating = false;
  bool obscure = true;

  @override
  void dispose() {
    name.dispose();
    email.dispose();
    password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    FocusScope.of(context).unfocus();
    if (creating) {
      await widget.auth.signUpWithPassword(
        name: name.text,
        email: email.text,
        password: password.text,
      );
    } else {
      await widget.auth.signInWithPassword(email.text, password.text);
    }
  }

  void _toggleMode() {
    widget.auth.clearError();
    setState(() => creating = !creating);
  }

  @override
  Widget build(BuildContext context) {
    final theme = ShadTheme.of(context);
    final auth = widget.auth;
    final dark = theme.brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: theme.colorScheme.background,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(24, 24, 24, 32),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: AutofillGroup(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Center(
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(22),
                        child: Image.asset(
                          'assets/icon.png',
                          width: 88,
                          height: 88,
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),
                    Text(
                      'Sculptus',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.h2.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Log your whole day in one message.',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.muted,
                    ),
                    const SizedBox(height: 32),
                    SignInWithAppleButton(
                      onPressed: auth.isBusy ? () {} : auth.signInWithApple,
                      style: dark
                          ? SignInWithAppleButtonStyle.white
                          : SignInWithAppleButtonStyle.black,
                      height: 50,
                      borderRadius: const BorderRadius.all(Radius.circular(14)),
                    ),
                    const SizedBox(height: 24),
                    Row(
                      children: [
                        const Expanded(child: ShadSeparator.horizontal()),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          child: Text(
                            'or use email',
                            style: theme.textTheme.muted.copyWith(fontSize: 13),
                          ),
                        ),
                        const Expanded(child: ShadSeparator.horizontal()),
                      ],
                    ),
                    const SizedBox(height: 24),
                    if (creating) ...[
                      ShadInput(
                        key: const ValueKey('authNameField'),
                        controller: name,
                        placeholder: const Text('Your name'),
                        leading: const Icon(LucideIcons.user, size: 16),
                        textInputAction: TextInputAction.next,
                        autofillHints: const [AutofillHints.name],
                      ),
                      const SizedBox(height: 12),
                    ],
                    ShadInput(
                      key: const ValueKey('authEmailField'),
                      controller: email,
                      placeholder: const Text('Email'),
                      leading: const Icon(LucideIcons.mail, size: 16),
                      keyboardType: TextInputType.emailAddress,
                      textInputAction: TextInputAction.next,
                      autofillHints: const [AutofillHints.email],
                    ),
                    const SizedBox(height: 12),
                    ShadInput(
                      key: const ValueKey('authPasswordField'),
                      controller: password,
                      placeholder: Text(
                        creating ? 'Password (8+ characters)' : 'Password',
                      ),
                      obscureText: obscure,
                      leading: const Icon(LucideIcons.lock, size: 16),
                      trailing: GestureDetector(
                        onTap: () => setState(() => obscure = !obscure),
                        child: Icon(
                          obscure ? LucideIcons.eye : LucideIcons.eyeOff,
                          size: 16,
                        ),
                      ),
                      autofillHints: [
                        creating
                            ? AutofillHints.newPassword
                            : AutofillHints.password,
                      ],
                      onSubmitted: (_) => _submit(),
                    ),
                    if (!creating)
                      Align(
                        alignment: Alignment.centerRight,
                        child: ShadButton.link(
                          size: ShadButtonSize.sm,
                          onPressed: () =>
                              showPasswordResetSheet(context, auth, email.text),
                          child: const Text('Forgot password?'),
                        ),
                      ),
                    if (auth.errorMessage.isNotEmpty) ...[
                      const SizedBox(height: 12),
                      ShadAlert.destructive(
                        icon: const Icon(LucideIcons.info),
                        description: Text(auth.errorMessage),
                      ),
                    ],
                    const SizedBox(height: 16),
                    ShadButton(
                      key: const ValueKey('authSubmitButton'),
                      height: 48,
                      onPressed: auth.isBusy ? null : _submit,
                      child: auth.isBusy
                          ? const SizedBox.square(
                              dimension: 18,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : Text(creating ? 'Create account' : 'Sign in'),
                    ),
                    const SizedBox(height: 8),
                    Center(
                      child: ShadButton.link(
                        onPressed: _toggleMode,
                        child: Text(
                          creating
                              ? 'Have an account? Sign in'
                              : 'New here? Create an account',
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    GestureDetector(
                      onTap: () => launchUrl(
                        Uri.parse(
                          'https://dynafex.ai/sculptus_privacy_policy.html',
                        ),
                        mode: LaunchMode.externalApplication,
                      ),
                      child: Text(
                        'By continuing you agree to the Privacy Policy.',
                        textAlign: TextAlign.center,
                        style: theme.textTheme.muted.copyWith(fontSize: 12),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

Future<void> showPasswordResetSheet(
  BuildContext context,
  AuthController auth,
  String initialEmail,
) async {
  auth.clearError();
  await showShadSheet<void>(
    context: context,
    side: ShadSheetSide.bottom,
    builder: (context) =>
        _PasswordResetSheet(auth: auth, initialEmail: initialEmail),
  );
}

class _PasswordResetSheet extends StatefulWidget {
  const _PasswordResetSheet({required this.auth, required this.initialEmail});

  final AuthController auth;
  final String initialEmail;

  @override
  State<_PasswordResetSheet> createState() => _PasswordResetSheetState();
}

class _PasswordResetSheetState extends State<_PasswordResetSheet> {
  late final email = TextEditingController(text: widget.initialEmail);
  final password = TextEditingController();
  String code = '';
  bool codeSent = false;

  @override
  void dispose() {
    email.dispose();
    password.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    if (await widget.auth.requestPasswordReset(email.text)) {
      setState(() => codeSent = true);
    }
  }

  Future<void> _reset() async {
    await widget.auth.resetPassword(
      email: email.text,
      code: code,
      password: password.text,
    );
    if (mounted && widget.auth.isSignedIn) {
      Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = widget.auth;
    return ListenableBuilder(
      listenable: auth,
      builder: (context, _) => ShadSheet(
        title: Text(codeSent ? 'Check your email' : 'Reset your password'),
        description: Text(
          codeSent
              ? 'If ${email.text.trim()} has an account, we sent a 6-digit '
                    'code. It expires in 15 minutes.'
              : 'We will email you a code to set a new password.',
        ),
        actions: [
          ShadButton(
            onPressed: auth.isBusy ? null : (codeSent ? _reset : _send),
            child: Text(codeSent ? 'Set password and sign in' : 'Send code'),
          ),
        ],
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (!codeSent)
                ShadInput(
                  controller: email,
                  placeholder: const Text('Email'),
                  keyboardType: TextInputType.emailAddress,
                  leading: const Icon(LucideIcons.mail, size: 16),
                )
              else ...[
                ShadInputOTP(
                  maxLength: 6,
                  keyboardType: TextInputType.number,
                  onChanged: (value) => code = value,
                  children: const [
                    ShadInputOTPGroup(
                      children: [
                        ShadInputOTPSlot(),
                        ShadInputOTPSlot(),
                        ShadInputOTPSlot(),
                      ],
                    ),
                    Icon(LucideIcons.minus, size: 16),
                    ShadInputOTPGroup(
                      children: [
                        ShadInputOTPSlot(),
                        ShadInputOTPSlot(),
                        ShadInputOTPSlot(),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                ShadInput(
                  controller: password,
                  obscureText: true,
                  placeholder: const Text('New password (8+ characters)'),
                  leading: const Icon(LucideIcons.lock, size: 16),
                ),
              ],
              if (auth.errorMessage.isNotEmpty) ...[
                const SizedBox(height: 12),
                ShadAlert.destructive(
                  icon: const Icon(LucideIcons.info),
                  description: Text(auth.errorMessage),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
