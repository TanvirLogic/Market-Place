import 'package:flutter/material.dart';
import 'package:edtech/app/setup_network_caller.dart';
import 'package:edtech/app/urls.dart';
import 'package:edtech/features/profile/shared/models/social_link_param.dart';
import 'package:edtech/features/profile/student/data/models/user_profile_model.dart';
import 'package:edtech/global/core/services/toast_service.dart';

class EditProfileProvider extends ChangeNotifier {
  bool _isLoading = false;
  bool get isLoading => _isLoading;

  String? _errorMessage;
  String? get errorMessage => _errorMessage;

  bool _isSuccess = false;
  bool get isSuccess => _isSuccess;

  UserProfileModel? _updatedProfile;
  UserProfileModel? get updatedProfile => _updatedProfile;

  Future<void> updateProfile({
    String? name,
    String? username,
    String? profession,
    String? dob,
    String? bio,
    String? country,
    String? phone,
    int? gender,
    List<SocialLinkParam>? socialLinks,
  }) async {
    _isLoading = true;
    _isSuccess = false;
    _errorMessage = null;
    notifyListeners();

    final body = <String, dynamic>{};
    if (name != null) body['name'] = name;
    if (username != null) body['username'] = username;
    if (profession != null) body['profession'] = profession;
    if (dob != null) body['dob'] = dob;
    if (bio != null) body['bio'] = bio;
    if (country != null) body['country'] = country;
    if (phone != null) body['phone'] = phone;
    if (gender != null) body['gender'] = gender;
    if (socialLinks != null) {
      body['socialLinks'] = socialLinks
          .map((s) => {'platform': s.platform, 'url': s.url})
          .toList();
    }

    final response = await getNetworkCaller().putRequest(
      url: Urls.profileUpdateUrl,
      body: body,
    );

    if (response.isSuccess) {
      _isSuccess = true;
      _updatedProfile = UserProfileModel.fromJson(response.responseData['data']);
      ToastService.showSuccess('Profile updated successfully!');
    } else {
      _errorMessage = response.errorMessage;
      ToastService.showError(response.errorMessage ?? 'Failed to update profile');
    }

    _isLoading = false;
    notifyListeners();
  }

  void resetSuccess() {
    _isSuccess = false;
    notifyListeners();
  }
}
