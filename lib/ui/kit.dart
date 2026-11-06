part of '../main.dart';

const _brand = Color(0xFF7A2738);
const _brandBright = Color(0xFFC4506A);
const _gold = Color(0xFFC9973F);
const _positive = Color(0xFF16A34A);

ShadThemeData sculptusTheme(Brightness brightness) {
  final dark = brightness == Brightness.dark;
  final primary = dark ? _brandBright : _brand;
  final base = ShadColorScheme.fromName('zinc', brightness: brightness);
  return ShadThemeData(
    brightness: brightness,
    colorScheme: base.copyWith(
      primary: primary,
      primaryForeground: Colors.white,
      ring: primary,
      background: dark ? const Color(0xFF0B0B0D) : const Color(0xFFF7F6F4),
      card: dark ? const Color(0xFF151518) : Colors.white,
    ),
    radius: const BorderRadius.all(Radius.circular(14)),
  );
}

String _thousands(num value) {
  final digits = value.round().abs().toString();
  final buffer = StringBuffer(value < 0 ? '-' : '');
  for (var i = 0; i < digits.length; i++) {
    if (i > 0 && (digits.length - i) % 3 == 0) {
      buffer.write(',');
    }
    buffer.write(digits[i]);
  }
  return buffer.toString();
}

String _initials(String name) {
  final parts = name
      .split(RegExp(r'[\s@.]+'))
      .where((part) => part.isNotEmpty)
      .toList();
  if (parts.isEmpty) {
    return 'S';
  }
  final first = parts.first[0];
  final second = parts.length > 1 ? parts[1][0] : '';
  return (first + second).toUpperCase();
}

const _weekdays = [
  'Monday',
  'Tuesday',
  'Wednesday',
  'Thursday',
  'Friday',
  'Saturday',
  'Sunday',
];

void showSculptusToast(BuildContext context, String message) {
  ShadSonner.of(context).show(ShadToast(description: Text(message)));
}

class InitialsAvatar extends StatelessWidget {
  const InitialsAvatar({super.key, required this.name, this.size = 40});

  final String name;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: const BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [_brandBright, _brand],
        ),
      ),
      child: Text(
        _initials(name),
        style: TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.w700,
          fontSize: size * 0.36,
        ),
      ),
    );
  }
}

class SectionLabel extends StatelessWidget {
  const SectionLabel(this.text, {super.key, this.trailing});

  final String text;
  final String? trailing;

  @override
  Widget build(BuildContext context) {
    final theme = ShadTheme.of(context);
    final style = theme.textTheme.small.copyWith(
      color: theme.colorScheme.mutedForeground,
      letterSpacing: 0.6,
      fontWeight: FontWeight.w600,
    );
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 20, 4, 8),
      child: Row(
        children: [
          Text(text.toUpperCase(), style: style),
          const Spacer(),
          if (trailing != null) Text(trailing!, style: style),
        ],
      ),
    );
  }
}

class StatTile extends StatelessWidget {
  const StatTile({
    super.key,
    required this.icon,
    required this.label,
    required this.value,
    this.color,
  });

  final IconData icon;
  final String label;
  final String value;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final theme = ShadTheme.of(context);
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: theme.colorScheme.muted,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 16, color: color ?? theme.colorScheme.primary),
            const SizedBox(height: 6),
            Text(
              value,
              style: theme.textTheme.large.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            Text(label, style: theme.textTheme.muted.copyWith(fontSize: 12)),
          ],
        ),
      ),
    );
  }
}

class ListRow extends StatelessWidget {
  const ListRow({
    super.key,
    required this.title,
    this.subtitle,
    this.leading,
    this.trailing,
    this.onTap,
  });

  final String title;
  final String? subtitle;
  final Widget? leading;
  final Widget? trailing;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = ShadTheme.of(context);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Row(
          children: [
            if (leading != null) ...[leading!, const SizedBox(width: 12)],
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: theme.textTheme.p.copyWith(
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  if (subtitle != null && subtitle!.isNotEmpty)
                    Text(
                      subtitle!,
                      style: theme.textTheme.muted.copyWith(fontSize: 13),
                    ),
                ],
              ),
            ),
            if (trailing != null) ...[const SizedBox(width: 12), trailing!],
          ],
        ),
      ),
    );
  }
}

class IconBubble extends StatelessWidget {
  const IconBubble(this.icon, {super.key, this.color});

  final IconData icon;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final theme = ShadTheme.of(context);
    final tint = color ?? theme.colorScheme.primary;
    return Container(
      width: 36,
      height: 36,
      decoration: BoxDecoration(
        color: tint.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Icon(icon, size: 18, color: tint),
    );
  }
}

Future<void> showWeighInSheet(
  BuildContext context,
  SculptusState state,
  DateTime date,
) async {
  final current = state.weights
      .where((entry) => _dateKey(entry.date) == _dateKey(date))
      .map((entry) => entry.weight)
      .firstOrNull;
  final controller = TextEditingController(
    text: current == null ? '' : _formatNumber(current),
  );
  final saved = await showShadSheet<double>(
    context: context,
    side: ShadSheetSide.bottom,
    builder: (context) => ShadSheet(
      title: const Text('Weigh in'),
      description: const Text(
        'Best first thing in the morning. Your 7-day average smooths out '
        'the daily swings.',
      ),
      actions: [
        ShadButton(
          key: const ValueKey('weighInSave'),
          onPressed: () {
            final value = double.tryParse(controller.text.trim());
            if (value != null && value > 50 && value < 700) {
              Navigator.of(context).pop(value);
            }
          },
          child: const Text('Save weight'),
        ),
      ],
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: ShadInput(
          key: const ValueKey('weighInField'),
          controller: controller,
          autofocus: true,
          placeholder: const Text('202.4'),
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          trailing: const Text('lb'),
        ),
      ),
    ),
  );
  controller.dispose();
  if (saved != null) {
    await state.setWeight(date, saved);
  }
}
