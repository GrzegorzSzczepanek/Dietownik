import 'package:flutter/material.dart';

import '../core/theme.dart';

class SectionCard extends StatelessWidget {
  const SectionCard({super.key, required this.child, this.padding = const EdgeInsets.all(20), this.border});
  final Widget child;
  final EdgeInsets padding;
  final Color? border;

  @override
  // Material (not a coloured DecoratedBox) so ListTile/SwitchListTile inside can paint ink.
  Widget build(BuildContext context) => SizedBox(
        width: double.infinity,
        child: Material(
          color: Colors.white,
          clipBehavior: Clip.antiAlias,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
            side: BorderSide(color: border ?? AppColors.border, width: border == null ? 1 : 1.5),
          ),
          child: Padding(padding: padding, child: child),
        ),
      );
}

class Pill extends StatelessWidget {
  const Pill(this.text, {super.key, this.bg, this.fg});
  final String text;
  final Color? bg;
  final Color? fg;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(color: bg ?? AppColors.hero, borderRadius: BorderRadius.circular(99)),
        child: Text(text, style: fig(13, weight: 600, color: fg ?? AppColors.accentDeep)),
      );
}

/// Thin rounded progress bar on the hero track color.
class ProgressBar extends StatelessWidget {
  const ProgressBar(this.fraction, {super.key, this.color, this.height = 10});
  final double fraction;
  final Color? color;
  final double height;

  @override
  Widget build(BuildContext context) => ClipRRect(
        borderRadius: BorderRadius.circular(99),
        child: LinearProgressIndicator(
          value: fraction.clamp(0.0, 1.0).toDouble(),
          minHeight: height,
          backgroundColor: AppColors.track,
          valueColor: AlwaysStoppedAnimation(color ?? AppColors.accent),
        ),
      );
}

class Initial extends StatelessWidget {
  const Initial(this.name, {super.key, this.green = false});
  final String name;
  final bool green;

  @override
  Widget build(BuildContext context) => Container(
        width: 48,
        height: 48,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: green ? AppColors.greenSoft : AppColors.chip,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Text(name.isEmpty ? '?' : name[0].toUpperCase(),
            style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w800,
                color: green ? AppColors.green : AppColors.ink)),
      );
}

/// Section heading: Figtree 16/700, sentence case (no CAPS, no letter spacing).
class Eyebrow extends StatelessWidget {
  const Eyebrow(this.text, {super.key});
  final String text;
  @override
  Widget build(BuildContext context) => Text(text, style: fig(16, weight: 700));
}

/// Lokalnie | API switch used per AI task.
class EngineToggle extends StatelessWidget {
  const EngineToggle({
    super.key,
    required this.api,
    required this.onChanged,
    this.localLabel = 'Lokalnie',
    this.apiLabel = 'API',
  });
  final bool api;
  final ValueChanged<bool> onChanged;
  final String localLabel;
  final String apiLabel;

  @override
  Widget build(BuildContext context) {
    Widget seg(String label, bool selected, Color color, VoidCallback onTap) => GestureDetector(
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 11),
            decoration: BoxDecoration(
                color: selected ? color : Colors.transparent,
                borderRadius: BorderRadius.circular(10)),
            child: Text(label,
                style: TextStyle(
                    fontWeight: FontWeight.w700,
                    color: selected ? Colors.white : AppColors.muted)),
          ),
        );
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(color: AppColors.chip, borderRadius: BorderRadius.circular(14)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        seg(localLabel, !api, AppColors.green, () => onChanged(false)),
        seg(apiLabel, api, AppColors.blue, () => onChanged(true)),
      ]),
    );
  }
}

void showError(BuildContext context, Object e) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(e.toString()), behavior: SnackBarBehavior.floating));
}
