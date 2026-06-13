import 'package:flutter/material.dart';

class SwipeActionWidget extends StatefulWidget {
  final Widget child;
  final Future<bool> Function()? onDelete;
  final VoidCallback? onEdit;
  final ValueNotifier<int>? resetNotifier;
  final Widget? editIcon;

  const SwipeActionWidget({
    super.key,
    required this.child,
    this.onDelete,
    this.onEdit,
    this.resetNotifier,
    this.editIcon,
  });

  @override
  State<SwipeActionWidget> createState() => _SwipeActionWidgetState();
}

class _SwipeActionWidgetState extends State<SwipeActionWidget> {
  double _offset = 0;
  bool _isDragging = false;

  static const double _threshold = 0.35;

  @override
  void initState() {
    super.initState();
    widget.resetNotifier?.addListener(_onReset);
  }

  @override
  void didUpdateWidget(SwipeActionWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.resetNotifier != oldWidget.resetNotifier) {
      oldWidget.resetNotifier?.removeListener(_onReset);
      widget.resetNotifier?.addListener(_onReset);
    }
  }

  @override
  void dispose() {
    widget.resetNotifier?.removeListener(_onReset);
    super.dispose();
  }

  void _onReset() {
    if (_offset != 0 && mounted) {
      setState(() => _offset = 0);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return LayoutBuilder(
      builder: (context, constraints) {
        final maxReveal = constraints.maxWidth * _threshold;
        final hasDelete = widget.onDelete != null;
        final hasEdit = widget.onEdit != null;

        return Stack(
          clipBehavior: Clip.hardEdge,
          children: [
            if (hasDelete)
              Positioned(
                right: 0,
                top: 0,
                bottom: 0,
                width: maxReveal,
                child: GestureDetector(
                  onTap: () async {
                    final confirmed = await widget.onDelete!();
                    if (confirmed && mounted) {
                      setState(() => _offset = 0);
                    }
                  },
                  child: Container(
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: cs.error.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(Icons.delete_outline, color: cs.error, size: 28),
                  ),
                ),
              ),
            if (hasEdit)
              Positioned(
                left: 0,
                top: 0,
                bottom: 0,
                width: maxReveal,
                child: GestureDetector(
                  onTap: () {
                    widget.onEdit!();
                    setState(() => _offset = 0);
                  },
                  child: Container(
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: cs.primary.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: widget.editIcon ?? Icon(Icons.edit, color: cs.primary, size: 28),
                  ),
                ),
              ),
            GestureDetector(
              onTap: () {
                if (_offset != 0) {
                  _onReset();
                }
              },
              onHorizontalDragStart: (_) => _isDragging = true,
              onHorizontalDragUpdate: (d) {
                setState(() {
                  _offset = (_offset + d.delta.dx).clamp(-maxReveal, maxReveal);
                });
              },
              onHorizontalDragEnd: (_) {
                _isDragging = false;
                if (_offset.abs() > maxReveal * 0.3) {
                  _offset = _offset < 0 ? -maxReveal : maxReveal;
                } else {
                  _offset = 0;
                }
                setState(() {});
              },
              child: AnimatedSlide(
                offset: Offset(_offset / constraints.maxWidth, 0),
                duration: _isDragging ? Duration.zero : const Duration(milliseconds: 200),
                curve: Curves.easeOut,
                child: widget.child,
              ),
            ),
          ],
        );
      },
    );
  }
}
