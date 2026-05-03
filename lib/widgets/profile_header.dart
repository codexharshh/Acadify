import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../Services/theme_provider.dart';
import '../models/user_model.dart';

class ProfileHeader extends StatelessWidget {
  final UserModel user;
  const ProfileHeader({super.key, required this.user});

  Future<void> _showGoalDialog(
      BuildContext context, ThemeProvider t, double currentGoal) async {
    final controller =
        TextEditingController(text: currentGoal.toStringAsFixed(0));

    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: t.cardColor,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                    colors: [Color(0xFF6A1B9A), Color(0xFF9C27B0)]),
                borderRadius: BorderRadius.circular(10),
              ),
              child:
                  const Icon(Icons.flag_rounded, color: Colors.white, size: 18),
            ),
            const SizedBox(width: 10),
            Text('Set Daily Goal',
                style: TextStyle(
                    color: t.textPrimary,
                    fontWeight: FontWeight.bold,
                    fontSize: 16)),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('How many hours do you want to study daily?',
                style: TextStyle(color: t.textSecondary, fontSize: 13)),
            const SizedBox(height: 16),
            TextField(
              controller: controller,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              autofocus: true,
              style: TextStyle(
                  color: t.textPrimary,
                  fontSize: 20,
                  fontWeight: FontWeight.bold),
              textAlign: TextAlign.center,
              decoration: InputDecoration(
                suffixText: 'hours',
                suffixStyle: TextStyle(color: t.textSecondary, fontSize: 14),
                border:
                    OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide:
                      const BorderSide(color: Color(0xFF7C4DFF), width: 2),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide:
                      BorderSide(color: t.textSecondary.withValues(alpha: 0.3)),
                ),
              ),
            ),
            const SizedBox(height: 12),
            // Quick select chips
            Text('Quick select:',
                style: TextStyle(color: t.textSecondary, fontSize: 12)),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children: [1, 2, 3, 4, 5, 6].map((h) {
                return GestureDetector(
                  onTap: () => controller.text = '$h',
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                    decoration: BoxDecoration(
                      color: const Color(0xFF7C4DFF).withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                          color:
                              const Color(0xFF7C4DFF).withValues(alpha: 0.3)),
                    ),
                    child: Text('${h}h',
                        style: const TextStyle(
                            color: Color(0xFF7C4DFF),
                            fontSize: 13,
                            fontWeight: FontWeight.w600)),
                  ),
                );
              }).toList(),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('Cancel', style: TextStyle(color: t.textSecondary)),
          ),
          ElevatedButton(
            onPressed: () async {
              final val = double.tryParse(controller.text.trim());
              if (val == null || val <= 0 || val > 24) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Enter a valid hours (1–24)'),
                    backgroundColor: Colors.red,
                    behavior: SnackBarBehavior.floating,
                  ),
                );
                return;
              }
              await FirebaseFirestore.instance
                  .collection('users')
                  .doc(user.uid)
                  .update({'todayGoalHours': val});
              if (ctx.mounted) Navigator.pop(ctx);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF7C4DFF),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10)),
            ),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    controller.dispose();
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
        final streak = data['studyStreakDays'] ?? 0;
        final goalHours = (data['todayGoalHours'] ?? 3).toDouble();

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
          child: Row(
            children: [
              // Avatar
              Container(
                width: 52,
                height: 52,
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    colors: [Color(0xFF6A1B9A), Color(0xFF9C27B0)],
                  ),
                  shape: BoxShape.circle,
                ),
                child: Center(
                  child: Text(
                    user.username.isNotEmpty
                        ? user.username[0].toUpperCase()
                        : 'S',
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 22,
                        fontWeight: FontWeight.bold),
                  ),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(user.username,
                        style: TextStyle(
                            color: t.textPrimary,
                            fontSize: 16,
                            fontWeight: FontWeight.bold)),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        // Streak
                        const Icon(Icons.local_fire_department,
                            color: Colors.orange, size: 14),
                        const SizedBox(width: 4),
                        Text('$streak Day Streak',
                            style: TextStyle(
                                color: t.textSecondary, fontSize: 12)),
                        const SizedBox(width: 12),
                        // ── Goal — tappable to edit ──
                        GestureDetector(
                          onTap: () => _showGoalDialog(context, t, goalHours),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: const Color(0xFF7C4DFF)
                                  .withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(
                                  color: const Color(0xFF7C4DFF)
                                      .withValues(alpha: 0.3)),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(Icons.flag_outlined,
                                    color: Color(0xFF7C4DFF), size: 12),
                                const SizedBox(width: 4),
                                Text('Goal: ${goalHours.toStringAsFixed(0)}h',
                                    style: const TextStyle(
                                        color: Color(0xFF7C4DFF),
                                        fontSize: 12,
                                        fontWeight: FontWeight.w600)),
                                const SizedBox(width: 4),
                                const Icon(Icons.edit,
                                    color: Color(0xFF7C4DFF), size: 10),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
