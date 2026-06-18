/// A single social link entry with platform and URL.
class SocialLink {
  final String platform;
  final String url;

  const SocialLink({required this.platform, required this.url});

  factory SocialLink.fromJson(Map<String, dynamic> json) {
    return SocialLink(
      platform: json['platform']?.toString() ?? '',
      url: json['url']?.toString() ?? '',
    );
  }

  Map<String, dynamic> toJson() => {'platform': platform, 'url': url};
}

/// A single video item from the profile API response.
class ProfileVideo {
  final String image;
  final String video;
  final String title;

  const ProfileVideo({this.image = '', required this.video, required this.title});
}

/// A single course item from the profile API response.
class ProfileCourse {
  final int id;
  final String image;
  final String title;
  final String by;
  final String progress;

  const ProfileCourse({
    required this.id,
    required this.image,
    required this.title,
    required this.by,
    this.progress = '',
  });
}

/// Full student profile returned by the `profile/me` endpoint.
class UserProfileEntity {
  final int id;
  final String name;
  final String username;
  final String email;
  final String? phone;
  final DateTime? dob;
  final int? gender;
  final String role;
  final String? avatarUrl;
  final String? coverUrl;
  final String? bio;
  final String? profession;
  final String? country;
  final List<SocialLink> socialLinks;
  final List<String> socialPlatforms;
  final List<ProfileVideo> videos;
  final List<ProfileCourse> courses;

  const UserProfileEntity({
    required this.id,
    required this.name,
    required this.username,
    required this.email,
    this.phone,
    this.dob,
    this.gender,
    required this.role,
    this.avatarUrl,
    this.coverUrl,
    this.bio,
    this.profession,
    this.country,
    required this.socialLinks,
    required this.socialPlatforms,
    required this.videos,
    required this.courses,
  });

  /// Returns a copy of this entity with the given fields replaced.
  UserProfileEntity copyWith({
    int? id,
    String? name,
    String? username,
    String? email,
    String? phone,
    DateTime? dob,
    int? gender,
    String? role,
    String? avatarUrl,
    String? coverUrl,
    String? bio,
    String? profession,
    String? country,
    List<SocialLink>? socialLinks,
    List<String>? socialPlatforms,
    List<ProfileVideo>? videos,
    List<ProfileCourse>? courses,
  }) {
    return UserProfileEntity(
      id: id ?? this.id,
      name: name ?? this.name,
      username: username ?? this.username,
      email: email ?? this.email,
      phone: phone ?? this.phone,
      dob: dob ?? this.dob,
      gender: gender ?? this.gender,
      role: role ?? this.role,
      avatarUrl: avatarUrl ?? this.avatarUrl,
      coverUrl: coverUrl ?? this.coverUrl,
      bio: bio ?? this.bio,
      profession: profession ?? this.profession,
      country: country ?? this.country,
      socialLinks: socialLinks ?? this.socialLinks,
      socialPlatforms: socialPlatforms ?? this.socialPlatforms,
      videos: videos ?? this.videos,
      courses: courses ?? this.courses,
    );
  }

  /// Convenience: number of videos in the profile.
  int get videoCount => videos.length;

  /// Convenience: number of courses in the profile.
  int get courseCount => courses.length;
}
