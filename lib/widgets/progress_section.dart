import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../Services/theme_provider.dart';
import '../models/user_model.dart';

/// Displays today's study progress with live per-second updates.
///
/// Combines the saved hours from Firestore with an in-memory live
/// counter so the display updates every second without waiting for
/// a Firestore write.
class ProgressSection extends StatelessWidget {
  final UserModel user;

  /// Live seconds counted since the last Firestore save.
  /// Passed down from DashboardPage so both widgets share the
  /// same source of truth.
  final int liveSeconds;

  const ProgressSection({
    super.key,
    required this.user,
    required this.liveSeconds,
  });

  // ── Converts hours to a human-readable string ─────────────────────
  // Uses seconds-based arithmetic to avoid floating-point rounding
  // errors (e.g. 0.35 * 60 = 20.999... rounds to 20 instead of 21).
  String _formatTime(double hours) {
    final totalSecs = (hours * 3600).round();
    final totalMins = totalSecs ~/ 60;
    if (totalMins < 60) return '${totalMins}min';
    final h = totalMins ~/ 60;
    final m = totalMins % 60;
    return m == 0 ? '${h}h' : '${h}h ${m}min';
  }

  @override
  Widget build(BuildContext context) {
    final t = Provider.of<ThemeProvider>(context);

    return StreamBuilder<DocumentSnapshot>(
      stream: FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .snapshots(),
      builder: (ctx, snap) {
        final data = snap.data?.data() as Map<String, dynamic>? ?? {};

        // Saved hours from Firestore
        final savedHours = (data['todayStudiedHours'] ?? 0).toDouble();
        final goalHours = (data['todayGoalHours'] ?? 3).toDouble();

        // Add live in-memory seconds on top of saved hours so the
        // display updates every second without a Firestore round-trip.
        final liveHours = liveSeconds / 3600.0;
        final totalHours = savedHours + liveHours;

        final progress =
            goalHours > 0 ? (totalHours / goalHours).clamp(0.0, 1.0) : 0.0;
        final percent = (progress * 100).toInt();
        final goalReached = totalHours >= goalHours;

        return Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: t.cardColor,
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(
                  color: t.shadowDark,
                  offset: const Offset(5, 5),
                  blurRadius: 12),
              BoxShadow(
                  color: t.shadowLight,
                  offset: const Offset(-5, -5),
                  blurRadius: 12),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.bar_chart_rounded,
                      color: Color(0xFF7C4DFF), size: 20),
                  const SizedBox(width: 8),
                  Text('Study Analytics',
                      style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: t.textPrimary)),
                ],
              ),
              const SizedBox(height: 14),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text("Today's Progress",
                      style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: t.textPrimary)),
                  Text('$percent%',
                      style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                          color: goalReached
                              ? Colors.green
                              : const Color(0xFF7C4DFF))),
                ],
              ),
              const SizedBox(height: 8),
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: LinearProgressIndicator(
                  value: progress,
                  minHeight: 10,
                  backgroundColor:
                      const Color(0xFF7C4DFF).withValues(alpha: 0.1),
                  valueColor: AlwaysStoppedAnimation<Color>(
                    goalReached ? Colors.green : const Color(0xFF7C4DFF),
                  ),
                ),
              ),
              const SizedBox(height: 6),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    '${_formatTime(totalHours)} of '
                    '${goalHours.toStringAsFixed(0)}h goal',
                    style: TextStyle(fontSize: 11, color: t.textSecondary),
                  ),
                  if (goalReached)
                    const Row(
                      children: [
                        Icon(Icons.check_circle, color: Colors.green, size: 12),
                        SizedBox(width: 4),
                        Text('Goal reached!',
                            style: TextStyle(
                                fontSize: 11,
                                color: Colors.green,
                                fontWeight: FontWeight.w600)),
                      ],
                    ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }
}
