import 'package:flutter/material.dart';

class ManageModuleDescription extends StatelessWidget {
  final String title;
  final String text;

  const ManageModuleDescription({
    super.key,
    required this.title,
    required this.text,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: cs.onSurface,
            ),
          ),
          const SizedBox(height: 4),
          text.isNotEmpty
              ? Text(
                  text,
                  style: TextStyle(
                    fontSize: 13,
                    color: cs.onSurface.withValues(alpha: 0.6),
                    height: 1.4,
                  ),
                )
              : RichText(
                  text: TextSpan(
                    text: "No $title provided",
                    style: TextStyle(
                      fontSize: 13,
                      color: cs.onSurface.withValues(alpha: 0.4),
                      height: 1.4,
                    ),
                  ),
                ),
        ],
      ),
    );
  }
}
