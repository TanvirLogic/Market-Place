import '../../data/entities/user_profile_entity.dart';

class UserProfileModel extends UserProfileEntity {
  const UserProfileModel({
    required super.id,
    required super.name,
    required super.username,
    required super.email,
    super.phone,
    super.dob,
    super.gender,
    required super.role,
    super.avatarUrl,
    super.coverUrl,
    super.bio,
    super.profession,
    super.country,
    required super.socialLinks,
    required super.socialPlatforms,
    required super.videos,
    required super.courses,
  });

  factory UserProfileModel.fromJson(Map<String, dynamic> json) {
    // ── Parse profile section ──
    final profile = json['profile'] as Map<String, dynamic>? ?? json;

    // ── Parse social platforms ──
    final platforms =
        (json['social_platforms'] as List<dynamic>?)
            ?.map((e) => e.toString())
            .toList() ??
        <String>[];

    // ── Parse videos ──
    final videosList =
        (json['videos'] as List<dynamic>?)
            ?.map(
              (v) => ProfileVideo(
                video: v['video']?.toString() ?? '',
                title: v['title']?.toString() ?? '',
              ),
            )
            .toList() ??
        <ProfileVideo>[];

    // ── Parse courses ──
    final coursesList =
        (json['courses'] as List<dynamic>?)
            ?.map(
              (c) => ProfileCourse(
                id: c['id'] is int
                    ? c['id'] as int
                    : int.tryParse(c['id']?.toString() ?? '0') ?? 0,
                image: c['image']?.toString() ?? '',
                title: c['title']?.toString() ?? '',
                by: c['by']?.toString() ?? '',
              ),
            )
            .toList() ??
        <ProfileCourse>[];

    // ── Parse social links from profile (now a list of {platform, url} objects) ──
    final socialLinksList =
        (profile['socialLinks'] as List<dynamic>?)
            ?.map((e) => SocialLink.fromJson(e as Map<String, dynamic>))
            .toList() ??
        <SocialLink>[];

    // ── Parse DOB ──
    DateTime? parsedDob;
    if (profile['dob'] != null && profile['dob'].toString().isNotEmpty) {
      parsedDob = DateTime.tryParse(profile['dob'].toString());
    }

    String normalizeRole(dynamic role) {
      if (role == null) return '';
      if (role == 0 || role == '0' || role == 'STUDENT') return 'STUDENT';
      if (role == 1 || role == '1' || role == 'MENTOR') return 'MENTOR';
      return role.toString();
    }

    return UserProfileModel(
      id: profile['id'] is int
          ? profile['id'] as int
          : int.tryParse(profile['id']?.toString() ?? '0') ?? 0,
      name: profile['name']?.toString() ?? '',
      username: profile['username']?.toString() ?? '',
      email: profile['email']?.toString() ?? '',
      phone: profile['phone']?.toString(),
      dob: parsedDob,
      gender: profile['gender'] is int ? profile['gender'] as int : null,
      role: normalizeRole(profile['role']),
      avatarUrl: profile['avatarUrl']?.toString(),
      coverUrl: profile['coverUrl']?.toString(),
      bio: profile['bio']?.toString(),
      profession: profile['profession']?.toString(),
      country: profile['country']?.toString(),
      socialLinks: socialLinksList,
      socialPlatforms: platforms,
      videos: videosList,
      courses: coursesList,
    );
  }
}
