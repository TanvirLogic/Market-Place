import 'package:edtech/app/app_colors.dart';
import 'package:edtech/global/core/widgets/cancel_button.dart';
import 'package:flutter/material.dart';
import 'package:edtech/global/core/constants/sizes.dart';

import 'package:edtech/global/core/widgets/app_back_button.dart';
import 'package:edtech/global/core/widgets/auth_button.dart';
import 'package:edtech/global/core/widgets/upload_zone.dart';

enum AdsType { poster, video }

class AdsCreateScreen extends StatefulWidget {
  const AdsCreateScreen({super.key});
  static const String name = '/ads-create';

  @override
  State<AdsCreateScreen> createState() => _AdsCreateScreenState();
}

class _AdsCreateScreenState extends State<AdsCreateScreen> {
  final _titleController = TextEditingController();
  final _ctaController = TextEditingController();
  AdsType _selectedAdsType = AdsType.poster;
  double _budgetAmount = 6900.0;

  @override
  void dispose() {
    _titleController.dispose();
    _ctaController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = cs.brightness == Brightness.dark;
    final int estimatedImpressions = (_budgetAmount * 3).toInt();

    return Scaffold(
      appBar: AppBar(
        elevation: 0,
        backgroundColor: Colors.transparent,
        scrolledUnderElevation: 0,
        leading: const Padding(
          padding: EdgeInsets.only(left: 16),
          child: AppBackButton(),
        ),
        title: Text(
          'Ads Create',
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.w700,
            color: cs.onSurface,
          ),
        ),
        centerTitle: true,
      ),
      body: SafeArea(
        child: GestureDetector(
          onTap: () => FocusScope.of(context).unfocus(),
          child: Column(
            children: [
              Expanded(
                child: SingleChildScrollView(
                  physics: const BouncingScrollPhysics(),
                  padding: const EdgeInsets.symmetric(horizontal: AppSizes.horizontalPadding),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const SizedBox(height: 16),
                      _buildLabel('Title', cs),
                      _AdsTextField(
                        controller: _titleController,
                        hintText: 'Enter your ad title',
                      ),
                      const SizedBox(height: 20),
                      _buildLabel('Ads Type', cs),
                      Row(
                        children: [
                          _buildTypeChip('Poster', AdsType.poster, cs, isDark),
                          const SizedBox(width: 12),
                          _buildTypeChip('Video', AdsType.video, cs, isDark),
                        ],
                      ),
                      const SizedBox(height: 20),
                      if (_selectedAdsType == AdsType.poster) ...[
                        _buildLabel('Poster', cs),
                        _buildPosterPicker(isDark, cs),
                      ] else ...[
                        _buildLabel('Upload Video', cs),
                        Padding(
                          padding: const EdgeInsets.only(bottom: 12.0),
                          child: Text(
                            'Video length can be upto 30 seconds',
                            style: TextStyle(
                              fontSize: 13,
                              color: AppColors.themeColor,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                        UploadZone(cs: cs, isDark: isDark),
                      ],
                      const SizedBox(height: 20),
                      _buildLabel('Call to Action', cs),
                      _AdsTextField(
                        controller: _ctaController,
                        hintText: 'Your target link',
                      ),
                      const SizedBox(height: 24),
                      _buildBudgetCalculatorCard(isDark, cs, estimatedImpressions),
                      const SizedBox(height: 32),
                    ],
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(AppSizes.horizontalPadding, 12.0, AppSizes.horizontalPadding, 16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    AuthButton(
                      text: 'Pay & Publish',
                      onPressed: () {},
                      height: 50,
                      borderRadius: 25,
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      height: 50,
                      child: CancelButton(
                        onPressed: () => Navigator.maybePop(context),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildLabel(String text, ColorScheme cs) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8.0),
      child: RichText(
        text: TextSpan(
          text: text,
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: cs.onSurface.withValues(alpha: 0.6),
          ),
          children: const [
            TextSpan(
              text: ' *',
              style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTypeChip(String label, AdsType type, ColorScheme cs, bool isDark) {
    final isSelected = _selectedAdsType == type;
    return ChoiceChip(
      label: Text(label),
      selected: isSelected,
      onSelected: (selected) {
        if (selected) setState(() => _selectedAdsType = type);
      },
      labelStyle: TextStyle(
        fontSize: 13,
        fontWeight: FontWeight.w700,
        color: isSelected ? Colors.white : cs.onSurface.withValues(alpha: 0.7),
      ),
      selectedColor: AppColors.themeColor,
      backgroundColor: Colors.transparent,
      elevation: 0,
      pressElevation: 0,
      side: BorderSide(
        color: isSelected
            ? AppColors.themeColor
            : cs.outlineVariant,
        width: 1,
      ),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppSizes.radiusLg2)),
      showCheckmark: false,
    );
  }

  Widget _buildPosterPicker(bool isDark, ColorScheme cs) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(AppSizes.radiusMd),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            'Upload poster',
            style: TextStyle(
              fontSize: 14,
              color: cs.onSurface.withValues(alpha: 0.6),
              fontWeight: FontWeight.w500,
            ),
          ),
          GestureDetector(
            onTap: () {},
            child: Text(
              'Choose',
              style: TextStyle(
                fontSize: 14,
                color: AppColors.themeColor,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBudgetCalculatorCard(
      bool isDark, ColorScheme cs, int estimatedImpressions) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: isDark ? cs.surfaceContainerLow : Colors.white,
        borderRadius: BorderRadius.circular(AppSizes.radiusMd),
        border: Border.all(
          color: isDark ? cs.outlineVariant : AppColors.border,
        ),
      ),
      child: Column(
        children: [
          Text(
            'Estimated Impression: $estimatedImpressions times',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: cs.onSurface.withValues(alpha: 0.6),
            ),
          ),
          const SizedBox(height: 10),
          Text(
            '৳${_budgetAmount.toInt()}',
            style: TextStyle(
              fontSize: 32,
              fontWeight: FontWeight.w800,
              color: AppColors.themeColor,
            ),
          ),
          const SizedBox(height: 16),
          SliderTheme(
            data: SliderTheme.of(context).copyWith(
              activeTrackColor: AppColors.themeColor,
              inactiveTrackColor: cs.outlineVariant,
              thumbColor: Colors.white,
              overlayColor: AppColors.themeColor.withValues(alpha: 0.12),
              trackHeight: 6,
              thumbShape:
                  const RoundSliderThumbShape(enabledThumbRadius: 10, elevation: 3),
            ),
            child: Slider(
              value: _budgetAmount,
              min: 100.0,
              max: 10000.0,
              onChanged: (value) => setState(() => _budgetAmount = value),
            ),
          ),
          const SizedBox(height: 4),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                '৳100',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: cs.onSurface.withValues(alpha: 0.5),
                ),
              ),
              Text(
                '৳10000',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: cs.onSurface.withValues(alpha: 0.5),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _AdsTextField extends StatelessWidget {
  final TextEditingController controller;
  final String hintText;

  const _AdsTextField({
    required this.controller,
    required this.hintText,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = cs.brightness == Brightness.dark;

    return TextField(
      controller: controller,
      style: TextStyle(
        fontSize: 14,
        color: cs.onSurface,
      ),
      decoration: InputDecoration(
        hintText: hintText,
        hintStyle: TextStyle(
          color: cs.onSurface.withValues(alpha: 0.5),
          fontSize: 14,
          fontWeight: FontWeight.w400,
        ),
        fillColor: isDark ? cs.surfaceContainerHighest : Colors.white,
        filled: true,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppSizes.radiusDef),
          borderSide: BorderSide(
            color: isDark ? cs.outlineVariant : AppColors.border,
          ),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppSizes.radiusDef),
          borderSide: BorderSide(
            color: isDark ? cs.outlineVariant : AppColors.border,
          ),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppSizes.radiusDef),
          borderSide: BorderSide(color: AppColors.themeColor, width: 1),
        ),
      ),
    );
  }
}
