import 'package:flutter/material.dart';
import 'package:edtech/app/urls.dart';
import 'package:edtech/app/setup_network_caller.dart';
import 'package:edtech/features/hub/data/entities/dashboard_entity.dart';

class MentorDashboardProvider extends ChangeNotifier {
  DashboardEntity? _dashboard;
  bool _isLoading = false;
  String? _errorMessage;

  DashboardEntity? get dashboard => _dashboard;
  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;

  Future<void> fetchDashboard() async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    final response = await getNetworkCaller().getRequest(
      url: Urls.mentorDashboardUrl,
    );

    if (response.isSuccess) {
      _dashboard = DashboardEntity.fromJson(
        response.responseData,
      );
    } else {
      _errorMessage = response.errorMessage ?? 'Failed to load dashboard';
    }

    _isLoading = false;
    notifyListeners();
  }
}