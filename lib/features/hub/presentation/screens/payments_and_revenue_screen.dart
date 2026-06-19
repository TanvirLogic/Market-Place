import 'package:edtech/app/app_colors.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:edtech/global/core/constants/sizes.dart';

import 'package:edtech/global/core/widgets/app_back_button.dart';

class PaymentsAndRevenueScreen extends StatelessWidget {
  const PaymentsAndRevenueScreen({super.key});
  static const String name = '/payments-and-revenue';

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = cs.brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        leading: const Padding(
          padding: EdgeInsets.only(left: 16),
          child: AppBackButton(),
        ),
        title: Text(
          'Payments & Revenue',
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.w500,
            color: cs.onSurface,
          ),
        ),
        centerTitle: true,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          physics: const BouncingScrollPhysics(),
          padding: const EdgeInsets.symmetric(horizontal: AppSizes.horizontalPadding),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: _MetricCard(
                      label: 'Total In',
                      amount: '৳9640',
                      iconPath: 'assets/images/revenue_icons/total_in.svg',
                      iconColor: AppColors.themeColor,
                      cs: cs,
                      isDark: isDark,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: _MetricCard(
                      label: 'Total Out',
                      amount: '৳7400',
                      iconPath: 'assets/images/revenue_icons/total_out.svg',
                      iconColor: const Color(0xFFEF4444),
                      cs: cs,
                      isDark: isDark,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              const _FilterPillRow(),
              const SizedBox(height: 24),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Recent Activity',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w500,
                      color: cs.onSurface,
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: AppColors.themeColor,
                      borderRadius: BorderRadius.circular(AppSizes.radiusLg2),
                    ),
                    child: Row(
                      children: [
                        Text(
                          'This Month',
                          style: const TextStyle(fontSize: 12, color: Colors.white, fontWeight: FontWeight.w500),
                        ),
                        const SizedBox(width: 4),
                        const Icon(Icons.keyboard_arrow_down_rounded, color: Colors.white, size: 16),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              _TransactionCard(
                title: 'Intro to Python',
                subtitle: 'Bkash · 24 May',
                amount: '+৳3500.00',
                status: 'Completed',
                isPositive: true,
                iconPath: 'assets/images/revenue_icons/book_icon.svg',
                iconBg: AppColors.themeColor.withValues(alpha: 0.1),
                iconColor: AppColors.themeColor,
              ),
              const SizedBox(height: 12),
              _TransactionCard(
                title: 'Ad payment',
                subtitle: 'Rocket · 25 May',
                amount: '-৳4500.00',
                status: 'Completed',
                isPositive: false,
                iconPath: 'assets/images/revenue_icons/ad_account.svg',
                iconBg: const Color(0xFFEA580C).withValues(alpha: 0.1),
                iconColor: const Color(0xFFEA580C),
              ),
              const SizedBox(height: 12),
              _TransactionCard(
                title: 'Withdraw',
                subtitle: 'Bank Transfer · 27 May',
                amount: '-৳2950.00',
                status: 'Completed',
                isPositive: false,
                iconPath: 'assets/images/revenue_icons/withdraw.svg',
                iconBg: const Color(0xFFEF4444).withValues(alpha: 0.1),
                iconColor: const Color(0xFFEF4444),
              ),
              const SizedBox(height: 12),
              _TransactionCard(
                title: 'Revenue',
                subtitle: 'Wallet · 31 May',
                amount: '+৳6140.00',
                status: 'Completed',
                isPositive: true,
                iconPath: 'assets/images/revenue_icons/total_in.svg',
                iconBg: const Color(0xFF10B981).withValues(alpha: 0.1),
                iconColor: const Color(0xFF10B981),
              ),
              const SizedBox(height: 12),
              _TransactionCard(
                title: 'Withdraw',
                subtitle: 'Bank Transfer · 27 May',
                amount: '-৳4000.00',
                status: 'Pending',
                isPositive: false,
                iconPath: 'assets/images/revenue_icons/withdraw.svg',
                iconBg: const Color(0xFFEF4444).withValues(alpha: 0.1),
                iconColor: const Color(0xFFEF4444),
              ),
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }
}

class _MetricCard extends StatelessWidget {
  final String label;
  final String amount;
  final String iconPath;
  final Color iconColor;
  final ColorScheme cs;
  final bool isDark;

  const _MetricCard({
    required this.label,
    required this.amount,
    required this.iconPath,
    required this.iconColor,
    required this.cs,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? cs.surfaceContainerLow : Colors.white,
        borderRadius: BorderRadius.circular(AppSizes.radiusLg),
        border: Border.all(
          color: isDark ? cs.outlineVariant : AppColors.border,
        ),
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 22,
            backgroundColor: iconColor.withValues(alpha: 0.1),
            child: SvgPicture.asset(
              iconPath,
              width: 20,
              height: 20,
              colorFilter: ColorFilter.mode(iconColor, BlendMode.srcIn),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  amount,
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w500,
                    color: cs.onSurface,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 12,
                    color: cs.onSurface.withValues(alpha: 0.6),
                    fontWeight: FontWeight.w500,
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

class _FilterPillRow extends StatefulWidget {
  const _FilterPillRow();

  @override
  State<_FilterPillRow> createState() => _FilterPillRowState();
}

class _FilterPillRowState extends State<_FilterPillRow> {
  final List<String> _categories = ['All', 'Purchase', 'Ads', 'Withdraw', 'Revenue'];
  int _selectedIndex = 0;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return SizedBox(
      height: 36,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        physics: const BouncingScrollPhysics(),
        itemCount: _categories.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final isSelected = _selectedIndex == index;
          return GestureDetector(
            onTap: () => setState(() => _selectedIndex = index),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              decoration: BoxDecoration(
                color: isSelected
                    ? AppColors.themeColor
                    : cs.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(18),
                border: Border.all(
                  color: isSelected
                      ? AppColors.themeColor
                      : cs.outlineVariant,
                ),
              ),
              child: Text(
                _categories[index],
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  color: isSelected ? Colors.white : cs.onSurface.withValues(alpha: 0.7),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _TransactionCard extends StatelessWidget {
  final String title;
  final String subtitle;
  final String amount;
  final String status;
  final bool isPositive;
  final String iconPath;
  final Color iconBg;
  final Color iconColor;

  const _TransactionCard({
    required this.title,
    required this.subtitle,
    required this.amount,
    required this.status,
    required this.isPositive,
    required this.iconPath,
    required this.iconBg,
    required this.iconColor,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = cs.brightness == Brightness.dark;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? cs.surfaceContainerLow : Colors.white,
        borderRadius: BorderRadius.circular(AppSizes.radiusMd),
        border: Border.all(
          color: isDark ? cs.outlineVariant : AppColors.border,
        ),
      ),
      child: _TransactionTile(
        title: title,
        subtitle: subtitle,
        amount: amount,
        status: status,
        isPositive: isPositive,
        iconPath: iconPath,
        iconBg: iconBg,
        iconColor: iconColor,
      ),
    );
  }
}

class _TransactionTile extends StatelessWidget {
  final String title;
  final String subtitle;
  final String amount;
  final String status;
  final bool isPositive;
  final String iconPath;
  final Color iconBg;
  final Color iconColor;

  const _TransactionTile({
    required this.title,
    required this.subtitle,
    required this.amount,
    required this.status,
    required this.isPositive,
    required this.iconPath,
    required this.iconBg,
    required this.iconColor,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = cs.brightness == Brightness.dark;

    return Row(
      children: [
        CircleAvatar(
          radius: 24,
          backgroundColor: isDark ? cs.surfaceContainerHighest : iconBg,
          child: SvgPicture.asset(
            iconPath,
            width: 22,
            height: 22,
            colorFilter: ColorFilter.mode(iconColor, BlendMode.srcIn),
          ),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w500,
                  color: cs.onSurface,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                subtitle,
                style: TextStyle(
                  fontSize: 12,
                  color: cs.onSurface.withValues(alpha: 0.5),
                  fontWeight: FontWeight.w400,
                ),
              ),
            ],
          ),
        ),
        Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              amount,
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w500,
                color: isPositive ? const Color(0xFF10B981) : const Color(0xFFEF4444),
              ),
            ),
            const SizedBox(height: 4),
            Text(
              status,
              style: TextStyle(
                fontSize: 11,
                color: status == 'Pending' ? const Color(0xFFF59E0B) : cs.onSurface.withValues(alpha: 0.5),
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ],
    );
  }
}
