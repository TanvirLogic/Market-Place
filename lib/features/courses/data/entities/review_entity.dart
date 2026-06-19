class ReviewEntity {
  final int id;
  final int rating;
  final String comment;
  final String createdAt;
  final String userName;
  final String? userAvatarUrl;
  final int? userId;

  const ReviewEntity({
    required this.id,
    required this.rating,
    required this.comment,
    required this.createdAt,
    required this.userName,
    this.userAvatarUrl,
    this.userId,
  });
}
