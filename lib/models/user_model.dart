class UserModel {
  final String uid;
  final String username;
  final String email;
  int studyStreakDays;
  double todayGoalHours;
  double todayStudiedHours;
  List<String> recentActivity;

  UserModel({
    required this.uid,
    required this.username,
    required this.email,
    this.studyStreakDays = 0,
    this.todayGoalHours = 3.0,
    this.todayStudiedHours = 0.0,
    List<String>? recentActivity,
  }) : recentActivity = recentActivity ?? [];

  double get todayProgress => todayGoalHours > 0
      ? (todayStudiedHours / todayGoalHours).clamp(0.0, 1.0)
      : 0.0;
}
