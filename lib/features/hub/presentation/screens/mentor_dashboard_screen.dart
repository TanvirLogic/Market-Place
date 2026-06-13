import 'package:edtech/global/core/constants/sizes.dart';
import 'package:edtech/features/profile/mentor/providers/mentor_profile_provider.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:edtech/global/core/widgets/app_back_button.dart';
import '../widgets/mentor_balance_banner.dart';
import '../widgets/mentor_course_accordion.dart';
import '../widgets/mentor_greeting_section.dart';
import '../widgets/mentor_metrics_grid.dart';

class MentorDashboardScreen extends StatefulWidget {
  const MentorDashboardScreen({super.key});
  static const String name = '/mentor-dashboard';

  @override
  State<MentorDashboardScreen> createState() => _MentorDashboardScreenState();
}

class _MentorDashboardScreenState extends State<MentorDashboardScreen> {
  String? _expandedCourseId = 'course_1';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<MentorProfileProvider>().fetchProfile();
    });
  }

  void _onExpansionChanged(String id, bool isExpanded) {
    setState(() {
      if (isExpanded) {
        _expandedCourseId = id;
      } else if (_expandedCourseId == id) {
        _expandedCourseId = null;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
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
          'Dashboard',
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.w700,
            color: Theme.of(context).colorScheme.onSurface,
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
              GreetingSection(
                name: context.watch<MentorProfileProvider>().profile?.name,
              ),
              const SizedBox(height: 24),
              const BalanceBanner(balance: '৳32,688'),
              const SizedBox(height: 16),
              const MetricsGrid(),
              const SizedBox(height: 28),
              Text(
                'Course Manager',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: Theme.of(context).colorScheme.primary,
                ),
              ),
              const SizedBox(height: 16),
              CourseAccordion(
                id: 'course_1',
                title: 'Complete Flutter Development',
                videosCount: 25,
                resourcesCount: 8,
                studentsCount: 50,
                isExpanded: _expandedCourseId == 'course_1',
                onExpansionChanged: (expanded) =>
                    _onExpansionChanged('course_1', expanded),
                grossAmount: '৳500.00',
                platformFee: '-৳125.00',
                netEarnings: '+৳375.00',
              ),
              const SizedBox(height: 12),
              CourseAccordion(
                id: 'course_2',
                title: 'Python for Data Science',
                videosCount: 25,
                resourcesCount: 8,
                studentsCount: 50,
                isExpanded: _expandedCourseId == 'course_2',
                onExpansionChanged: (expanded) =>
                    _onExpansionChanged('course_2', expanded),
              ),
              const SizedBox(height: 12),
              CourseAccordion(
                id: 'course_3',
                title: 'Ad Impression Revenue',
                videosCount: 25,
                resourcesCount: 8,
                studentsCount: 50,
                isExpanded: _expandedCourseId == 'course_3',
                onExpansionChanged: (expanded) =>
                    _onExpansionChanged('course_3', expanded),
              ),
              const SizedBox(height: 12),
              CourseAccordion(
                id: 'course_4',
                title: 'Ad Impression Revenue',
                videosCount: 25,
                resourcesCount: 8,
                studentsCount: 50,
                isExpanded: _expandedCourseId == 'course_4',
                onExpansionChanged: (expanded) =>
                    _onExpansionChanged('course_4', expanded),
              ),
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }
}
