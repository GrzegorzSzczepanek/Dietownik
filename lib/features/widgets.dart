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
          color: AppColors.bg,
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
                    color: selected ? AppColors.onAccent : AppColors.muted)),
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

/// Hero zone from the mockups: tinted block with a rounded bottom (32 px) that
/// extends under the status bar.
class HeroZone extends StatelessWidget {
  const HeroZone({super.key, required this.child, this.bottom = 24});
  final Widget child;
  final double bottom;

  @override
  Widget build(BuildContext context) => Container(
        width: double.infinity,
        decoration: BoxDecoration(
          color: AppColors.hero,
          borderRadius: const BorderRadius.vertical(bottom: Radius.circular(32)),
        ),
        padding: EdgeInsets.fromLTRB(20, MediaQuery.of(context).padding.top, 20, bottom),
        child: child,
      );
}

/// Back arrow + Bricolage title row used inside [HeroZone] (52 px tall).
class HeroBackHeader extends StatelessWidget {
  const HeroBackHeader(this.title, {super.key, this.actions = const [], this.size = 28});
  final String title;
  final List<Widget> actions;
  final double size;

  @override
  Widget build(BuildContext context) => SizedBox(
        height: 52,
        child: Row(children: [
          Transform.translate(
            offset: const Offset(-12, 0),
            child: IconButton(tooltip: 'Wróć', icon: const Icon(Icons.arrow_back), onPressed: () => Navigator.maybePop(context)),
          ),
          Expanded(child: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: display(size))),
          ...actions,
        ]),
      );
}

/// Line-separated list row: title 17/700 (or 16/600), subtitle 14, optional trailing.
class NavRow extends StatelessWidget {
  const NavRow({
    super.key,
    required this.title,
    this.subtitle,
    this.subtitleColor,
    this.leading,
    this.trailing,
    this.onTap,
    this.topLine = true,
    this.bottomLine = false,
    this.minHeight = 64,
    this.bold = false,
  });
  final String title;
  final String? subtitle;
  final Color? subtitleColor;
  final Widget? leading, trailing;
  final VoidCallback? onTap;
  final bool topLine, bottomLine, bold;
  final double minHeight;

  @override
  Widget build(BuildContext context) => InkWell(
        onTap: onTap,
        child: Container(
          constraints: BoxConstraints(minHeight: minHeight),
          decoration: BoxDecoration(
            border: Border(
              top: topLine ? BorderSide(color: AppColors.line) : BorderSide.none,
              bottom: bottomLine ? BorderSide(color: AppColors.line) : BorderSide.none,
            ),
          ),
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Row(children: [
            if (leading != null) ...[leading!, const SizedBox(width: 14)],
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.center, children: [
                Text(title, style: fig(bold ? 17 : 16, weight: bold ? 700 : 600)),
                if (subtitle != null)
                  Text(subtitle!, style: fig(14, weight: subtitleColor != null ? 600 : 400, color: subtitleColor ?? AppColors.text2, height: 20 / 14)),
              ]),
            ),
            if (trailing != null) trailing!,
            if (trailing == null && onTap != null) Icon(Icons.chevron_right, color: AppColors.text2),
          ]),
        ),
      );
}

/// White rounded field used on hero zones: leading widget, input, trailing actions.
class HeroField extends StatelessWidget {
  const HeroField({super.key, required this.controller, required this.hint, this.leading, this.actions = const [], this.onSubmitted, this.keyboardType});
  final TextEditingController controller;
  final String hint;
  final Widget? leading;
  final List<Widget> actions;
  final ValueChanged<String>? onSubmitted;
  final TextInputType? keyboardType;

  @override
  Widget build(BuildContext context) => Container(
        height: 56,
        decoration: BoxDecoration(color: AppColors.bg, borderRadius: BorderRadius.circular(16)),
        padding: const EdgeInsets.fromLTRB(16, 0, 6, 0),
        child: Row(children: [
          if (leading != null) ...[leading!, const SizedBox(width: 10)],
          Expanded(
            child: TextField(
              controller: controller,
              keyboardType: keyboardType,
              textInputAction: TextInputAction.done,
              onSubmitted: onSubmitted,
              style: fig(16, weight: 500),
              decoration: InputDecoration(
                hintText: hint,
                filled: false,
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                contentPadding: EdgeInsets.zero,
              ),
            ),
          ),
          ...actions,
        ]),
      );
}

/// Small accent square button (44 px, radius 12) for [HeroField] actions.
class AccentSquareButton extends StatelessWidget {
  const AccentSquareButton({super.key, required this.onTap, this.icon, this.label, required this.semantics});
  final VoidCallback onTap;
  final IconData? icon;
  final String? label;
  final String semantics;

  @override
  Widget build(BuildContext context) => Semantics(
        button: true,
        label: semantics,
        child: GestureDetector(
          onTap: onTap,
          child: Container(
            height: 44,
            width: label == null ? 44 : null,
            padding: label == null ? null : const EdgeInsets.symmetric(horizontal: 16),
            decoration: BoxDecoration(color: AppColors.accent, borderRadius: BorderRadius.circular(12)),
            alignment: Alignment.center,
            child: label != null
                ? Text(label!, style: fig(15, weight: 700, color: AppColors.onAccent))
                : Icon(icon, color: AppColors.onAccent),
          ),
        ),
      );
}
