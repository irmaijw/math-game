import 'package:flutter/material.dart';

class CircularControl extends StatelessWidget {
  const CircularControl(
      {super.key,
      required this.label,
      required this.icon,
      required this.onPressed,
      this.active = false});
  final String label;
  final IconData icon;
  final VoidCallback? onPressed;
  final bool active;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return TextButton(
      style: TextButton.styleFrom(
        fixedSize: const Size(92, 92),
        padding: const EdgeInsets.all(8),
        shape: const CircleBorder(),
        backgroundColor: active ? colors.primary : colors.secondaryContainer,
        foregroundColor:
            active ? colors.onPrimary : colors.onSecondaryContainer,
        disabledBackgroundColor: colors.surfaceContainerHighest,
      ),
      onPressed: onPressed,
      child: FittedBox(
          fit: BoxFit.scaleDown,
          child: SizedBox(
              width: 70,
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Icon(icon, size: 25),
                const SizedBox(height: 4),
                Text(label,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                        fontSize: 11, fontWeight: FontWeight.w600)),
              ]))),
    );
  }
}
