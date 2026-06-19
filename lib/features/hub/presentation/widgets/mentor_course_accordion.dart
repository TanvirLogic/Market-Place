import 'package:edtech/global/core/constants/sizes.dart';
import 'package:edtech/app/app_colors.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import '../../../../../global/core/constants/images/images.dart';
import '../../../../../app/app_routes.dart';
import '../../../../../global/core/widgets/auth_button.dart';

class CourseAccordion extends StatelessWidget {
  final String id;
  final int courseId;
  final String title;
  final int videosCount;
  final int resourcesCount;
  final int studentsCount;
  final bool isExpanded;
  final ValueChanged<bool> onExpansionChanged;
  final String? grossAmount;
  final String? platformFee;
  final String? netEarnings;
  CourseAccordion({
    required this.id,
    required this.courseId,
    required this.title,
    required this.videosCount,
    required this.resourcesCount,
    required this.studentsCount,
    required this.isExpanded,
    required this.onExpansionChanged,
    this.grossAmount,
    this.platformFee,
    this.netEarnings,
  }) : super(key: ValueKey(id));
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = cs.brightness == Brightness.dark;
    final hasContent = grossAmount != null;
    final header = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          title,
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w600,
            color: cs.onSurface,
          ),
        ),
        const SizedBox(height: 6),
        MetaBadgeRow(
          videosCount: videosCount,
          resourcesCount: resourcesCount,
          studentsCount: studentsCount,
        ),
      ],
    );
    if (!hasContent) {
      return Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: isDark ? cs.surfaceContainerLow : Colors.white,
          borderRadius: BorderRadius.circular(AppSizes.radiusSm),
          border: Border.all(color: cs.outlineVariant),
        ),
        child: header,
      );
    }
    return Container(
      decoration: BoxDecoration(
        color: isDark ? cs.surfaceContainerLow : Colors.white,
        borderRadius: BorderRadius.circular(AppSizes.radiusSm),
        border: Border.all(color: cs.outlineVariant),
      ),
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          key: ValueKey('${id}_$isExpanded'),
          initiallyExpanded: isExpanded,
          onExpansionChanged: onExpansionChanged,
          tilePadding: const EdgeInsets.all(12),
          childrenPadding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
          collapsedShape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppSizes.radiusSm),
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppSizes.radiusSm),
          ),
          collapsedIconColor: cs.onSurface.withValues(alpha: 0.6),
          iconColor: cs.onSurface.withValues(alpha: 0.6),
          title: header,
          children: [
            ExpandedCourseContent(
              courseId: courseId,
              grossAmount: grossAmount!,
              platformFee: platformFee,
              netEarnings: netEarnings,
              isDark: isDark,
              cs: cs,
            ),
          ],
        ),
      ),
    );
  }
}

class MetaBadgeRow extends StatelessWidget {
  final int videosCount;
  final int resourcesCount;
  final int studentsCount;
  const MetaBadgeRow({
    super.key,
    required this.videosCount,
    required this.resourcesCount,
    required this.studentsCount,
  });
  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        MetaBadge(
          icon: SvgPicture.asset(
            Images.videoIcon,
            width: 16,
            height: 16,
            colorFilter: ColorFilter.mode(
              Theme.of(context).colorScheme.onSurface,
              BlendMode.srcIn,
            ),
          ),
          label: '$videosCount Video',
        ),
        const SizedBox(width: 8),
        MetaBadge(
          icon: SvgPicture.asset(
            Images.resource,
            width: 16,
            height: 16,
            colorFilter: ColorFilter.mode(
              Theme.of(context).colorScheme.onSurface,
              BlendMode.srcIn,
            ),
          ),
          label: '${resourcesCount.toString().padLeft(2, '0')} Resource',
        ),
        const SizedBox(width: 8),
        MetaBadge(
          icon: SvgPicture.asset(
            Images.totalStudent,
            width: 16,
            height: 16,
            colorFilter: ColorFilter.mode(
              Theme.of(context).colorScheme.onSurface,
              BlendMode.srcIn,
            ),
          ),
          label: '$studentsCount Students',
        ),
      ],
    );
  }
}

class MetaBadge extends StatelessWidget {
  final Widget icon;
  final String label;
  const MetaBadge({super.key, required this.icon, required this.label});
  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        icon,
        const SizedBox(width: 2),
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            color: Theme.of(context).colorScheme.onSurface,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}

class ExpandedCourseContent extends StatelessWidget {
  final int courseId;
  final String grossAmount;
  final String? platformFee;
  final String? netEarnings;
  final bool isDark;
  final ColorScheme cs;
  const ExpandedCourseContent({
    super.key,
    required this.courseId,
    required this.grossAmount,
    required this.platformFee,
    required this.netEarnings,
    required this.isDark,
    required this.cs,
  });
  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: isDark ? cs.surfaceContainerHighest : AppColors.surface,
            borderRadius: BorderRadius.circular(AppSizes.radiusSm),
            border: Border.all(
              color: isDark ? cs.outlineVariant : AppColors.border,
            ),
          ),
          child: Column(
            children: [
              FinancialRow(
                label: 'Gross Amount',
                value: grossAmount,
                valueColor: cs.onSurface,
              ),
              if (platformFee != null) ...[
                const SizedBox(height: 12),
                FinancialRow(
                  label: 'Platform Fee (25%)',
                  value: platformFee!,
                  valueColor: cs.onSurface,
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: Divider(
                    height: 1,
                    thickness: 0.5,
                    color: cs.onSurface.withValues(alpha: 0.2),
                  ),
                ),
              ],
              if (netEarnings != null) ...[
                FinancialRow(
                  label: 'Net Earnings',
                  value: netEarnings!,
                  valueColor: AppColors.themeColor,
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 12),
        AuthButton(
          text: 'Manage Module',
          onPressed: () => Navigator.pushNamed(context, AppRoutes.manageModule, arguments: {'courseId': courseId}),
          height: 44,
          borderRadius: 22,
        ),
      ],
    );
  }
}

class FinancialRow extends StatelessWidget {
  final String label;
  final String value;
  final Color valueColor;
  const FinancialRow({
    super.key,
    required this.label,
    required this.value,
    required this.valueColor,
  });
  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 13,
            color: Theme.of(context).colorScheme.onSurface,
            fontWeight: FontWeight.w500,
          ),
        ),
        Text(
          value,
          style: TextStyle(
            fontSize: 13,
            color: valueColor,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }
}
