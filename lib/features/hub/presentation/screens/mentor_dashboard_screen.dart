import 'package:edtech/global/core/constants/sizes.dart';
import 'package:edtech/features/hub/providers/mentor_dashboard_provider.dart';
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
  String? _expandedCourseId;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<MentorProfileProvider>().fetchProfile();
      context.read<MentorDashboardProvider>().fetchDashboard();
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
    final dashboard = context.watch<MentorDashboardProvider>().dashboard;
    final stats = dashboard?.stats;

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
          padding: const EdgeInsets.symmetric(
            horizontal: AppSizes.horizontalPadding,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 8),
              GreetingSection(
                name: context.watch<MentorProfileProvider>().profile?.name,
              ),
              const SizedBox(height: 24),
              const BalanceBanner(balance: '\u09F332,688'),
              const SizedBox(height: 16),
              MetricsGrid(
                totalCourses: stats?.totalCourses,
                totalEnrollments: stats?.totalEnrollments,
                totalReviews: stats?.totalReviews,
                avgRating: stats?.avgRating,
              ),
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
              if (dashboard != null && dashboard.courses.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 32),
                  child: Center(
                    child: Text(
                      'No courses yet',
                      style: TextStyle(
                        color: Theme.of(context)
                            .colorScheme
                            .onSurface
                            .withValues(alpha: 0.5),
                      ),
                    ),
                  ),
                )
              else
                ...?dashboard?.courses.map((course) {
                  final id = 'course_${course.id}';
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 16),
                    child: CourseAccordion(
                      id: id,
                      courseId: course.id,
                      title: course.title,
                      videosCount: stats?.totalLessons ?? 0,
                      resourcesCount: stats?.totalResources ?? 0,
                      studentsCount: course.totalEnrollments,
                      isExpanded: _expandedCourseId == id,
                      onExpansionChanged: (expanded) =>
                          _onExpansionChanged(id, expanded),
                      grossAmount: '\u09F3500.00',
                      platformFee: '-\u09F3125.00',
                      netEarnings: '+\u09F3375.00',
                    ),
                  );
                }),
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }
}