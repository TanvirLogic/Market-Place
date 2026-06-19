import 'package:flutter/material.dart';

class CourseExpandableContainer extends StatelessWidget {
  final String title;
  final Widget child;
  final bool isDark;
  final ColorScheme cs;

  const CourseExpandableContainer({
    super.key,
    required this.title,
    required this.child,
    required this.isDark,
    required this.cs,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: isDark ? cs.surfaceContainerLow : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isDark ? cs.outlineVariant : const Color(0xFFEFEFF0),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
            decoration: BoxDecoration(
              color: isDark ? cs.surfaceContainerHighest : const Color(0xFFF9F9F9),
              borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
            ),
            child: Text(
              title,
              style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                    fontWeight: FontWeight.w500,
                    fontSize: 16,
                    color: cs.onSurface,
                  ),
            ),
          ),
          Divider(
            height: 1,
            color: cs.outlineVariant,
          ),
          Padding(padding: const EdgeInsets.all(16), child: child),
        ],
      ),
    );
  }
}
