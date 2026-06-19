import 'package:edtech/app/app_colors.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:edtech/global/core/constants/sizes.dart';
import 'package:edtech/global/core/constants/images/images.dart';

import 'package:edtech/app/app_routes.dart';
import 'package:edtech/global/core/widgets/app_back_button.dart';

class AdsManagerScreen extends StatefulWidget {
  const AdsManagerScreen({super.key});
  static const String name = '/ads-manager';

  @override
  State<AdsManagerScreen> createState() => _AdsManagerScreenState();
}

class _AdsManagerScreenState extends State<AdsManagerScreen> {
  String _selectedFilter = 'All';

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = cs.brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        elevation: 0,
        backgroundColor: Colors.transparent,
        scrolledUnderElevation: 0,
        leading: const Padding(
          padding: EdgeInsets.only(left: 16.0),
          child: AppBackButton(),
        ),
        title: Text(
          'Ads Manager',
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.w700,
            color: cs.onSurface,
          ),
        ),
        centerTitle: true,
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 16.0),
            child: GestureDetector(
              onTap: () => Navigator.pushNamed(context, AppRoutes.adsCreate),
              child: Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: AppColors.themeColor,
                  shape: BoxShape.circle,
                ),
                child: Icon(Icons.add, color: Colors.white, size: 20),
              ),
            ),
          )
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            const SizedBox(height: 16),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: AppSizes.horizontalPadding),
                child: Row(
                  children: [
                    Expanded(
                      child: _buildSummaryCard(
                        iconPath: Images.adAccount,
                        iconBg: const Color(0xFFEA580C).withValues(alpha: 0.1),
                        iconColor: const Color(0xFFEA580C),
                        value: '02',
                        label: 'Active Ads',
                        isDark: isDark,
                        cs: cs,
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: _buildSummaryCard(
                        iconPath: Images.totalImpression,
                        iconBg: const Color(0xFF16A34A).withValues(alpha: 0.1),
                        iconColor: const Color(0xFF16A34A),
                        value: '14,280',
                        label: 'Total Impression',
                        isDark: isDark,
                        cs: cs,
                      ),
                    ),
                  ],
                ),
              ),
            const SizedBox(height: 20),

            Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSizes.horizontalPadding),
              child: Row(
                children: [
                  _buildFilterChip('All', cs, isDark),
                  const SizedBox(width: 8),
                  _buildFilterChip('Active', cs, isDark),
                  const SizedBox(width: 8),
                  _buildFilterChip('Completed', cs, isDark),
                ],
              ),
            ),
            const SizedBox(height: 16),
            Expanded(
              child: ListView(
                physics: const BouncingScrollPhysics(),
                padding: const EdgeInsets.symmetric(horizontal: AppSizes.horizontalPadding),
                children: [
                  _AdCampaignCard(
                    title: 'Learn Python in 30 days',
                    subtitle: 'Poster ad · Started 22 May',
                    iconPath: Images.bookAds,
                    iconColor: AppColors.themeColor,
                    iconBg: AppColors.themeColor.withValues(alpha: 0.1),
                    spentAmount: 4200,
                    totalBudget: 6900,
                    viewsCount: 12600,
                    isActiveBadgeVisible: true,
                    isDark: isDark,
                    cs: cs,
                  ),
                  const SizedBox(height: 12),
                  _AdCampaignCard(
                    title: 'Learn Python in 30 days',
                    subtitle: '15s Video ad · Started 22 May',
                    icon: Icons.play_circle_outline,
                    iconColor: const Color(0xFFEA580C),
                    iconBg: const Color(0xFFEA580C).withValues(alpha: 0.1),
                    spentAmount: 4500,
                    totalBudget: 4500,
                    viewsCount: 26300,
                    isActiveBadgeVisible: false,
                    isDark: isDark,
                    cs: cs,
                  ),
                  const SizedBox(height: 12),
                  _AdCampaignCard(
                    title: 'Learn Python in 30 days',
                    subtitle: '30s Video ad · Started 22 May',
                    icon: Icons.play_circle_outline,
                    iconColor: const Color(0xFFEA580C),
                    iconBg: const Color(0xFFEA580C).withValues(alpha: 0.1),
                    spentAmount: 4500,
                    totalBudget: 4500,
                    viewsCount: 26300,
                    isActiveBadgeVisible: false,
                    isDark: isDark,
                    cs: cs,
                  ),
                  const SizedBox(height: 16),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFilterChip(String label, ColorScheme cs, bool isDark) {
    final isSelected = _selectedFilter == label;
    return ChoiceChip(
      label: Text(label),
      selected: isSelected,
      onSelected: (selected) {
        if (selected) setState(() => _selectedFilter = label);
      },
      labelStyle: TextStyle(
        fontSize: 13,
        fontWeight: FontWeight.w700,
        color: isSelected ? Colors.white : cs.onSurface.withValues(alpha: 0.7),
      ),
      selectedColor: AppColors.themeColor,
      backgroundColor: isDark ? cs.surfaceContainerHighest : Colors.white,
      elevation: 0,
      pressElevation: 0,
      side: BorderSide(
        color: isSelected
            ? AppColors.themeColor
            : cs.outlineVariant,
      ),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppSizes.radiusLg2)),
      showCheckmark: false,
    );
  }

  Widget _buildSummaryCard({
    String? iconPath,
    IconData? icon,
    double? iconSize,
    required Color iconBg,
    required Color iconColor,
    required String value,
    required String label,
    required bool isDark,
    required ColorScheme cs,
  }) {
    return Container(
      padding: const EdgeInsets.fromLTRB(8, 8, 8, 6),
      decoration: BoxDecoration(
        color: isDark ? cs.surfaceContainerLow : Colors.white,
        borderRadius: BorderRadius.circular(AppSizes.radiusMd),
        border: Border.all(
          color: isDark ? cs.outlineVariant : AppColors.border,
        ),
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 20,
            backgroundColor: isDark ? cs.surfaceContainerHighest : iconBg,
            child: iconPath != null
                ? SvgPicture.asset(iconPath, width: iconSize ?? 20, height: iconSize ?? 20, colorFilter: ColorFilter.mode(iconColor, BlendMode.srcIn))
                : Icon(icon, color: iconColor, size: iconSize ?? 20),
              ),
              const SizedBox(width: 8),
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  value,
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.w800,
                    color: cs.onSurface,
                  ),
                ),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(
                    label,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      color: cs.onSurface.withValues(alpha: 0.6),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _AdCampaignCard extends StatelessWidget {
  final String title;
  final String subtitle;
  final String? iconPath;
  final IconData? icon;
  final Color iconColor;
  final Color iconBg;
  final int spentAmount;
  final int totalBudget;
  final int viewsCount;
  final bool isActiveBadgeVisible;
  final bool isDark;
  final ColorScheme cs;

  const _AdCampaignCard({
    required this.title,
    required this.subtitle,
    this.iconPath,
    this.icon,
    required this.iconColor,
    required this.iconBg,
    required this.spentAmount,
    required this.totalBudget,
    required this.viewsCount,
    required this.isActiveBadgeVisible,
    required this.isDark,
    required this.cs,
  });

  @override
  Widget build(BuildContext context) {
    final int remainingBudget = totalBudget - spentAmount;
    final bool isCompleted = remainingBudget == 0;
    final Color progressAccentColor = isCompleted ? const Color(0xFF22C55E) : AppColors.themeColor;
    final Color budgetTextColor = isCompleted ? const Color(0xFFEF4444) : AppColors.themeColor;

    return Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: isDark ? cs.surfaceContainerLow : Colors.white,
            borderRadius: BorderRadius.circular(AppSizes.radiusMd),
            border: Border.all(
              color: isDark ? cs.outlineVariant : AppColors.border,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Container(
                    width: 48,
                    height: 48,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: iconBg,
                      shape: BoxShape.circle,
                    ),
                    child: iconPath != null
                        ? SvgPicture.asset(iconPath!, width: 20, height: 20, colorFilter: ColorFilter.mode(iconColor, BlendMode.srcIn))
                        : Icon(icon, color: iconColor, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: cs.onSurface,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      style: TextStyle(
                        fontSize: 12,
                        color: cs.onSurface.withValues(alpha: 0.5),
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
              if (isActiveBadgeVisible)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                  decoration: BoxDecoration(
                    color: isDark
                        ? AppColors.themeColor.withValues(alpha: 0.18)
                        : const Color(0xFFEFF5FB),
                    borderRadius: BorderRadius.circular(AppSizes.radiusMd),
                    border: Border.all(
                      color: isDark
                          ? AppColors.themeColor.withValues(alpha: 0.4)
                          : const Color(0xFFACCDEC),
                      width: 0.5,
                    ),
                  ),
                  child: Text(
                    'Active',
                    style: TextStyle(
                      color: AppColors.themeColor,
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Budget Spent',
                style: TextStyle(
                  fontSize: 12,
                  color: cs.onSurface.withValues(alpha: 0.6),
                  fontWeight: FontWeight.w600,
                ),
              ),
              Text(
                '৳$spentAmount of ৳$totalBudget',
                style: TextStyle(
                  fontSize: 12,
                  color: isDark ? Colors.white70 : cs.onSurface.withValues(alpha: 0.7),
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          SliderTheme(
            data: SliderTheme.of(context).copyWith(
              activeTrackColor: progressAccentColor,
              inactiveTrackColor: cs.outlineVariant,
              thumbColor: Colors.white,
              trackHeight: 6,
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6, elevation: 2),
              overlayShape: SliderComponentShape.noOverlay,
            ),
            child: Slider(
              value: spentAmount.toDouble(),
              min: 0,
              max: totalBudget.toDouble() > 0 ? totalBudget.toDouble() : 1.0,
              onChanged: null,
            ),
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                '৳$remainingBudget left',
                style: TextStyle(
                  fontSize: 12,
                  color: budgetTextColor,
                  fontWeight: FontWeight.w700,
                ),
              ),
              Text(
                'Views : $viewsCount',
                style: TextStyle(
                  fontSize: 12,
                  color: cs.onSurface.withValues(alpha: 0.6),
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          )
        ],
      ),
    );
  }
}
