import 'package:flutter/material.dart';
import 'package:edtech/app/setup_network_caller.dart';
import 'package:edtech/app/urls.dart';
import 'package:edtech/features/profile/student/data/entities/user_profile_entity.dart';
import 'package:edtech/features/profile/student/data/models/user_profile_model.dart';

class StudentProfileProvider extends ChangeNotifier {
  bool _isLoading = false;
  bool get isLoading => _isLoading;

  UserProfileModel? _profile;
  UserProfileModel? get profile => _profile;

  String? _errorMessage;
  String? get errorMessage => _errorMessage;

  void clearProfile() {
    _profile = null;
    _errorMessage = null;
    _isLoading = false;
    notifyListeners();
  }

  Future<void> fetchProfile() async {
    if (_isLoading) return;
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    final response = await getNetworkCaller().getRequest(url: Urls.profileUrl);

    if (response.isSuccess) {
      _profile = UserProfileModel.fromJson(response.responseData['data']);
    } else {
      _errorMessage = response.errorMessage;
    }

    _isLoading = false;
    notifyListeners();
  }

  void refreshProfile(UserProfileEntity updatedProfile) {
    _profile = UserProfileModel(
      id: updatedProfile.id,
      name: updatedProfile.name,
      username: updatedProfile.username,
      email: updatedProfile.email,
      phone: updatedProfile.phone,
      dob: updatedProfile.dob,
      gender: updatedProfile.gender,
      role: updatedProfile.role,
      avatarUrl: updatedProfile.avatarUrl,
      coverUrl: updatedProfile.coverUrl,
      bio: updatedProfile.bio,
      profession: updatedProfile.profession,
      country: updatedProfile.country,
      socialLinks: updatedProfile.socialLinks,
      socialPlatforms: updatedProfile.socialPlatforms,
      videos: updatedProfile.videos,
      courses: updatedProfile.courses,
    );
    notifyListeners();
  }
}
