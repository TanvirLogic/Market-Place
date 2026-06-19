import 'package:edtech/app/app_colors.dart';
import 'package:edtech/global/core/constants/sizes.dart';
import 'package:edtech/global/core/services/toast_service.dart';
import 'package:edtech/global/core/widgets/app_alert_dialog.dart';
import 'package:edtech/features/courses/data/entities/review_entity.dart';
import 'package:edtech/features/courses/providers/course_detail_provider.dart';
import 'package:edtech/features/auth/data/models/auth_controller.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

class CourseReviewsTabView extends StatefulWidget {
  final List<ReviewEntity> reviews;
  final bool isDark;
  final ColorScheme cs;
  final int courseId;

  const CourseReviewsTabView({
    super.key,
    required this.reviews,
    required this.isDark,
    required this.cs,
    required this.courseId,
  });

  @override
  State<CourseReviewsTabView> createState() => _CourseReviewsTabViewState();
}

class _CourseReviewsTabViewState extends State<CourseReviewsTabView> {
  final TextEditingController _reviewController = TextEditingController();
  bool _alreadyReviewed = false;
  String? _errorText;

  @override
  void dispose() {
    _reviewController.dispose();
    super.dispose();
  }

  int? get _currentUserId => int.tryParse(AuthController.userModel?.id ?? '');

  Future<void> _submitReview() async {
    final text = _reviewController.text.trim();
    if (text.isEmpty) return;

    final provider = context.read<CourseDetailProvider>();
    final result = await provider.submitReview(
      courseId: widget.courseId,
      rating: 5,
      comment: text,
    );

    if (!mounted) return;

    if (result != null && result.containsKey('_error')) {
      ToastService.showError(result['_error'] as String? ?? 'Failed to submit review');
      setState(() {
        _errorText = result['_error'] as String?;
        _alreadyReviewed = _errorText?.contains('already reviewed') ?? false;
      });
    } else {
      ToastService.showSuccess('Review submitted successfully');
      _reviewController.clear();
      setState(() {
        _errorText = null;
      });
    }
  }

  Future<void> _editReview(ReviewEntity review) async {
    final controller = TextEditingController(text: review.comment);
    final newComment = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Edit Review'),
        content: TextField(
          controller: controller,
          maxLines: 3,
          decoration: const InputDecoration(
            hintText: 'Update your review...',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    controller.dispose();

    if (newComment == null || newComment.isEmpty || newComment == review.comment) return;
    if (!mounted) return;

    final provider = context.read<CourseDetailProvider>();
    final result = await provider.updateReview(reviewId: review.id, comment: newComment);
    if (!mounted) return;

    if (result != null && result.containsKey('_error')) {
      ToastService.showError(result['_error'] as String? ?? 'Failed to update review');
    } else {
      ToastService.showSuccess('Review updated successfully');
    }
  }

  Future<void> _deleteReview(ReviewEntity review) async {
    final confirmed = await AppAlertDialog.show(
      context: context,
      title: 'Delete Review',
      content: 'Are you sure you want to delete your review?',
      confirmText: 'Delete',
    );

    if (!mounted || confirmed != true) return;

    final provider = context.read<CourseDetailProvider>();
    final result = await provider.deleteReview(review.id);
    if (!mounted) return;

    if (result != null && result.containsKey('_error')) {
      ToastService.showError(result['_error'] as String? ?? 'Failed to delete review');
    } else {
      ToastService.showSuccess('Review deleted successfully');
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = widget.isDark;
    final cs = widget.cs;

    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _reviewController,
                textInputAction: TextInputAction.done,
                maxLines: 3,
                minLines: 1,
                enabled: !_alreadyReviewed,
                style: TextStyle(
                  fontSize: 14,
                  color: cs.onSurface,
                ),
                decoration: InputDecoration(
                  hintText: _alreadyReviewed ? 'You have already reviewed' : 'Write a review...',
                  hintStyle: TextStyle(
                    color: _alreadyReviewed
                        ? cs.error.withValues(alpha: 0.6)
                        : cs.onSurface.withValues(alpha: 0.4),
                    fontSize: 14,
                  ),
                  border: InputBorder.none,
                  contentPadding: const EdgeInsets.only(left: 12),
                ),
              ),
            ),
            const SizedBox(width: 8),
            GestureDetector(
              onTap: _alreadyReviewed ? null : _submitReview,
              child: Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: _alreadyReviewed
                      ? cs.outlineVariant
                      : AppColors.themeColor,
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.send_rounded,
                  color: _alreadyReviewed ? cs.onSurface.withValues(alpha: 0.3) : Colors.white,
                  size: 18,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 20),
        if (widget.reviews.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 32),
            child: Center(
              child: Text(
                'No reviews yet',
                style: TextStyle(color: cs.onSurface.withValues(alpha: 0.5)),
              ),
            ),
          )
        else
          ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: widget.reviews.length,
            separatorBuilder: (_, _) => const SizedBox(height: 16),
            itemBuilder: (context, index) {
              final review = widget.reviews[index];
              return ReviewCardItem(
                name: review.userName,
                timeAgo: _formatDate(review.createdAt),
                rating: review.rating,
                comment: review.comment,
                imageUrl: review.userAvatarUrl ?? '',
                isDark: isDark,
                cs: cs,
                isOwnReview: _currentUserId != null && review.userId == _currentUserId,
                onEdit: () => _editReview(review),
                onDelete: () => _deleteReview(review),
              );
            },
          ),
      ],
    );
  }

  String _formatDate(String isoDate) {
    try {
      final date = DateTime.parse(isoDate);
      final diff = DateTime.now().difference(date);
      if (diff.inDays < 1) return 'Today';
      if (diff.inDays == 1) return 'Yesterday';
      if (diff.inDays < 7) return '${diff.inDays}d ago';
      return '${diff.inDays ~/ 7}w ago';
    } catch (_) {
      return '';
    }
  }
}

class ReviewCardItem extends StatelessWidget {
  final String name;
  final String timeAgo;
  final int rating;
  final String comment;
  final String imageUrl;
  final bool isDark;
  final ColorScheme cs;
  final bool isOwnReview;
  final VoidCallback? onEdit;
  final VoidCallback? onDelete;

  const ReviewCardItem({
    super.key,
    required this.name,
    required this.timeAgo,
    required this.rating,
    required this.comment,
    required this.imageUrl,
    required this.isDark,
    required this.cs,
    this.isOwnReview = false,
    this.onEdit,
    this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final cs = this.cs;

    return GestureDetector(
      onLongPress: isOwnReview
          ? () {
              final overlay = Overlay.of(context);
              late OverlayEntry entry;
              entry = OverlayEntry(
                builder: (context) => _ReviewActionPopup(
                  onEdit: () {
                    entry.remove();
                    onEdit?.call();
                  },
                  onDelete: () {
                    entry.remove();
                    onDelete?.call();
                  },
                  onDismiss: () => entry.remove(),
                ),
              );
              overlay.insert(entry);
            }
          : null,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: isDark ? cs.surfaceContainerLow : Colors.white,
          borderRadius: BorderRadius.circular(AppSizes.radiusMd),
          border: Border.all(
          color: Theme.of(context).brightness == Brightness.dark
              ? Theme.of(context).colorScheme.outlineVariant
              : AppColors.border,
        ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                CircleAvatar(
                  radius: 22,
                  backgroundColor: cs.outlineVariant,
                  backgroundImage: imageUrl.isNotEmpty
                      ? CachedNetworkImageProvider(imageUrl)
                      : null,
                  child: imageUrl.isEmpty
                      ? Icon(Icons.person, color: cs.onSurface.withValues(alpha: 0.4))
                      : null,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        name,
                        style: TextStyle(
                          fontWeight: FontWeight.w500,
                          fontSize: 15,
                          color: cs.onSurface,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: List.generate(5, (starIndex) {
                          return Padding(
                            padding: const EdgeInsets.only(right: 2.0),
                            child: Icon(
                              Icons.star_rounded,
                              size: 16,
                              color: starIndex < rating
                                  ? const Color(0xFFFBBF24)
                                  : cs.outlineVariant,
                            ),
                          );
                        }),
                      ),
                    ],
                  ),
                ),
                Text(
                  timeAgo,
                  style: TextStyle(
                    color: cs.onSurface.withValues(alpha: 0.5),
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              comment,
              style: TextStyle(
                color: cs.onSurface.withValues(alpha: 0.7),
                fontSize: 13.5,
                height: 1.45,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ReviewActionPopup extends StatelessWidget {
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final VoidCallback onDismiss;

  const _ReviewActionPopup({
    required this.onEdit,
    required this.onDelete,
    required this.onDismiss,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onDismiss,
      child: Container(color: Colors.black26, child: Center(
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 40),
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.edit_outlined),
                title: const Text('Edit'),
                onTap: onEdit,
              ),
              ListTile(
                leading: Icon(Icons.delete_outline, color: Colors.red.shade400),
                title: Text('Delete', style: TextStyle(color: Colors.red.shade400)),
                onTap: onDelete,
              ),
            ],
          ),
        ),
      )),
    );
  }
}
