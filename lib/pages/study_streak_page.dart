import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../Services/theme_provider.dart';

class StudyStreakPage extends StatefulWidget {
  const StudyStreakPage({super.key});

  @override
  State<StudyStreakPage> createState() => _StudyStreakPageState();
}

class _StudyStreakPageState extends State<StudyStreakPage>
    with TickerProviderStateMixin {
  ThemeProvider get _t => Provider.of<ThemeProvider>(context, listen: false);
  late AnimationController _pulseController;
  late AnimationController _fadeController;
  late Animation<double> _pulseAnim;
  late Animation<double> _fadeAnim;

  // ── Month navigation ─────────────────────────────────────────────
  DateTime _calendarMonth = DateTime(DateTime.now().year, DateTime.now().month);
  Set<String> _calStudiedDays = {};
  bool _calLoading = false;

  @override
  void initState() {
    super.initState();
    _loadCalendarMonth();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat(reverse: true);

    _fadeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    )..forward();

    _pulseAnim = Tween<double>(begin: 1.0, end: 1.08).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
    _fadeAnim = CurvedAnimation(parent: _fadeController, curve: Curves.easeOut);

    // Auto update streak on page open
    _updateStreakIfStudied();
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _fadeController.dispose();
    super.dispose();
  }

  String get _uid => FirebaseAuth.instance.currentUser!.uid;
  DocumentReference get _userDoc =>
      FirebaseFirestore.instance.collection('users').doc(_uid);
  CollectionReference get _streakHistoryRef =>
      _userDoc.collection('streakHistory');

  String _todayKey() {
    final now = DateTime.now();
    return '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
  }

  String _dateKey(DateTime date) =>
      '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';

  // ── Calendar month loading ────────────────────────────────────────
  Future<void> _loadCalendarMonth() async {
    setState(() => _calLoading = true);
    try {
      final snap = await _streakHistoryRef
          .where('date',
              isGreaterThanOrEqualTo:
                  '${_calendarMonth.year}-${_calendarMonth.month.toString().padLeft(2, '0')}-01')
          .where('date',
              isLessThanOrEqualTo:
                  '${_calendarMonth.year}-${_calendarMonth.month.toString().padLeft(2, '0')}-31')
          .get();
      if (mounted) {
        setState(() {
          _calStudiedDays = snap.docs.map((d) => d.id).toSet();
          _calLoading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _calLoading = false);
    }
  }

  Future<void> _prevMonth() async {
    setState(() => _calendarMonth =
        DateTime(_calendarMonth.year, _calendarMonth.month - 1));
    await _loadCalendarMonth();
  }

  Future<void> _nextMonth() async {
    final now = DateTime.now();
    if (_calendarMonth.year == now.year && _calendarMonth.month == now.month) {
      return;
    }
    setState(() => _calendarMonth =
        DateTime(_calendarMonth.year, _calendarMonth.month + 1));
    await _loadCalendarMonth();
  }

  // ── Auto Streak System (Snapchat/Duolingo style) ──────────────────
  Future<void> _updateStreakIfStudied() async {
    try {
      final today = _todayKey();
      final now = DateTime.now();

      final userSnap = await _userDoc.get();
      final userData = userSnap.data() as Map<String, dynamic>? ?? {};
      final todayHours = (userData['todayStudiedHours'] ?? 0).toDouble();

      // Only if studied >= 1 hour
      if (todayHours < 1.0) return;

      // Check if today already recorded
      final todayDoc = await _streakHistoryRef.doc(today).get();
      if (todayDoc.exists) return;

      // Record today
      await _streakHistoryRef.doc(today).set({
        'date': today,
        'studied': true,
        'hours': todayHours,
        'recordedAt': Timestamp.now(),
      });

      final currentStreak = (userData['studyStreakDays'] ?? 0) as int;
      final lastCheckin = (userData['lastCheckinDate'] ?? '') as String;
      final longestStreak = (userData['longestStreak'] ?? 0) as int;

      final yesterday = DateTime(now.year, now.month, now.day - 1);
      final yesterdayKey = _dateKey(yesterday);

      int newStreak;
      if (lastCheckin == yesterdayKey) {
        newStreak = currentStreak + 1; // consecutive
      } else if (lastCheckin == today) {
        return; // already done
      } else {
        newStreak = 1; // streak broken
      }

      final newLongest = newStreak > longestStreak ? newStreak : longestStreak;

      await _userDoc.update({
        'studyStreakDays': newStreak,
        'lastCheckinDate': today,
        'longestStreak': newLongest,
        'totalStudyDays': FieldValue.increment(1),
      });
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final isDark = _t.isDark;
    final bg = _t.bgColor;
    final textColor = _t.textPrimary;

    return Scaffold(
      backgroundColor: bg,
      appBar: AppBar(
        flexibleSpace: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              colors: [Color(0xFF6A1B9A), Color(0xFF9C27B0)],
              begin: Alignment.centerLeft,
              end: Alignment.centerRight,
            ),
          ),
        ),
        title: const Text('Study Streak',
            style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 18)),
        iconTheme: const IconThemeData(color: Colors.white),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh, color: Colors.white),
            onPressed: _updateStreakIfStudied,
          ),
        ],
      ),
      body: StreamBuilder<DocumentSnapshot>(
        stream: _userDoc.snapshots(),
        builder: (ctx, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(
                child: CircularProgressIndicator(color: Color(0xFF7C4DFF)));
          }

          final data = snapshot.data?.data() as Map<String, dynamic>? ?? {};
          final currentStreak = data['studyStreakDays'] ?? 0;
          final longestStreak = data['longestStreak'] ?? 0;
          final totalDays = data['totalStudyDays'] ?? 0;
          final todayHours = (data['todayStudiedHours'] ?? 0).toDouble();
          final goalHours = (data['todayGoalHours'] ?? 3).toDouble();

          return FadeTransition(
            opacity: _fadeAnim,
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildStreakHeroCard(currentStreak, isDark, textColor),
                  const SizedBox(height: 16),
                  _buildTodayProgressCard(
                      isDark, textColor, todayHours, goalHours),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: _buildStatCard(
                          icon: Icons.emoji_events_outlined,
                          label: 'Longest Streak',
                          value: '$longestStreak days',
                          color: Colors.amber,
                          isDark: isDark,
                          textColor: textColor,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _buildStatCard(
                          icon: Icons.calendar_month_outlined,
                          label: 'Total Days',
                          value: '$totalDays days',
                          color: Colors.teal,
                          isDark: isDark,
                          textColor: textColor,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  _buildCalendarSection(isDark, textColor),
                  const SizedBox(height: 16),
                  _buildMilestonesSection(currentStreak, isDark, textColor),
                  const SizedBox(height: 32),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildStreakHeroCard(int streak, bool isDark, Color textColor) {
    return _buildNeuCard(
      isDark: isDark,
      child: Column(
        children: [
          const SizedBox(height: 8),
          AnimatedBuilder(
            animation: _pulseAnim,
            builder: (_, child) => Transform.scale(
              scale: streak > 0 ? _pulseAnim.value : 1.0,
              child: child,
            ),
            child: Icon(
              streak > 0 ? Icons.local_fire_department : Icons.bedtime_outlined,
              size: 72,
              color: streak > 0 ? Colors.orange : Colors.blueGrey,
            ),
          ),
          const SizedBox(height: 12),
          Text('$streak',
              style: const TextStyle(
                  color: Color(0xFF7C4DFF),
                  fontSize: 64,
                  fontWeight: FontWeight.w900,
                  height: 1)),
          const SizedBox(height: 4),
          Text('Day Streak',
              style: TextStyle(
                  color: textColor.withValues(alpha: 0.6),
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                  letterSpacing: 1.5)),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: streak > 0
                    ? [
                        Colors.orange.withValues(alpha: 0.2),
                        Colors.deepOrange.withValues(alpha: 0.1)
                      ]
                    : [
                        Colors.grey.withValues(alpha: 0.1),
                        Colors.grey.withValues(alpha: 0.05)
                      ],
              ),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                  color: streak > 0
                      ? Colors.orange.withValues(alpha: 0.4)
                      : Colors.grey.withValues(alpha: 0.3)),
            ),
            child: Text(
              streak == 0
                  ? 'Study 1+ hour to start your streak'
                  : streak < 7
                      ? 'Keep going!'
                      : streak < 30
                          ? 'You\'re on fire!'
                          : 'Unstoppable!',
              style: TextStyle(
                  color: streak > 0
                      ? Colors.orange
                      : textColor.withValues(alpha: 0.5),
                  fontSize: 13,
                  fontWeight: FontWeight.w600),
            ),
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }

  // Smart time display: exact minutes if < 1h, else hours + minutes
  String _formatTime(double hours) {
    final totalSecs = (hours * 3600).round();
    final totalMins = totalSecs ~/ 60;
    if (totalMins < 60) return '${totalMins}min';
    final h = totalMins ~/ 60;
    final m = totalMins % 60;
    return m == 0 ? '${h}h' : '${h}h ${m}min';
  }

  Widget _buildTodayProgressCard(
      bool isDark, Color textColor, double todayHours, double goalHours) {
    final progress =
        goalHours > 0 ? (todayHours / goalHours).clamp(0.0, 1.0) : 0.0;
    final percent = (progress * 100).toInt();
    final streakReady = todayHours >= 1.0;

    return _buildNeuCard(
      isDark: isDark,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                      colors: [Color(0xFF6A1B9A), Color(0xFF9C27B0)]),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.today, color: Colors.white, size: 18),
              ),
              const SizedBox(width: 10),
              Text("Today's Progress",
                  style: TextStyle(
                      color: textColor,
                      fontSize: 16,
                      fontWeight: FontWeight.bold)),
              const Spacer(),
              Text('$percent%',
                  style: const TextStyle(
                      color: Color(0xFF7C4DFF),
                      fontSize: 16,
                      fontWeight: FontWeight.bold)),
            ],
          ),
          const SizedBox(height: 14),
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: LinearProgressIndicator(
              value: progress,
              minHeight: 10,
              backgroundColor: isDark
                  ? Colors.white.withValues(alpha: 0.08)
                  : Colors.black.withValues(alpha: 0.06),
              valueColor: AlwaysStoppedAnimation<Color>(
                  streakReady ? Colors.green : const Color(0xFF7C4DFF)),
            ),
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                '${_formatTime(todayHours)} studied of ${goalHours.toStringAsFixed(0)}h goal',
                style: TextStyle(
                    color: textColor.withValues(alpha: 0.5), fontSize: 12),
              ),
              if (streakReady)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: Colors.green.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.check_circle, color: Colors.green, size: 14),
                      SizedBox(width: 4),
                      Text(
                        'Streak Active',
                        style: TextStyle(
                          color: Colors.green,
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
          const SizedBox(height: 12),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: streakReady
                  ? Colors.green.withValues(alpha: 0.08)
                  : const Color(0xFF7C4DFF).withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                  color: streakReady
                      ? Colors.green.withValues(alpha: 0.3)
                      : const Color(0xFF7C4DFF).withValues(alpha: 0.2)),
            ),
            child: Row(
              children: [
                Icon(
                    streakReady
                        ? Icons.local_fire_department
                        : Icons.hourglass_top_rounded,
                    size: 20,
                    color:
                        streakReady ? Colors.green : const Color(0xFF7C4DFF)),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    streakReady
                        ? 'Great work! Your streak is automatically maintained.'
                        : 'Study at least 1 hour today to keep your streak alive!',
                    style: TextStyle(
                      color: streakReady
                          ? Colors.green.shade700
                          : const Color(0xFF7C4DFF),
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatCard({
    required IconData icon,
    required String label,
    required String value,
    required Color color,
    required bool isDark,
    required Color textColor,
  }) {
    return _buildNeuCard(
      isDark: isDark,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: color, size: 20),
          ),
          const SizedBox(height: 10),
          Text(value,
              style: TextStyle(
                  color: textColor, fontSize: 20, fontWeight: FontWeight.bold)),
          const SizedBox(height: 2),
          Text(label,
              style: TextStyle(
                  color: textColor.withValues(alpha: 0.5), fontSize: 12)),
        ],
      ),
    );
  }

  Widget _buildCalendarSection(bool isDark, Color textColor) {
    final now = DateTime.now();
    final monthNames = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec'
    ];
    final isCurrentMonth =
        _calendarMonth.year == now.year && _calendarMonth.month == now.month;

    return _buildNeuCard(
      isDark: isDark,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.grid_view_rounded,
                  color: Color(0xFF7C4DFF), size: 18),
              const SizedBox(width: 8),
              Text('Activity Calendar',
                  style: TextStyle(
                      color: textColor,
                      fontSize: 16,
                      fontWeight: FontWeight.bold)),
              const Spacer(),
              IconButton(
                icon: const Icon(Icons.chevron_left,
                    color: Color(0xFF7C4DFF), size: 20),
                onPressed: _calLoading ? null : _prevMonth,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
              ),
              Text(
                '${monthNames[_calendarMonth.month - 1]} ${_calendarMonth.year}',
                style: const TextStyle(
                    color: Color(0xFF7C4DFF),
                    fontSize: 12,
                    fontWeight: FontWeight.w600),
              ),
              IconButton(
                icon: Icon(Icons.chevron_right,
                    color: isCurrentMonth
                        ? Colors.grey.withValues(alpha: 0.4)
                        : const Color(0xFF7C4DFF),
                    size: 20),
                onPressed: (isCurrentMonth || _calLoading) ? null : _nextMonth,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (_calLoading)
            const Center(
                child: Padding(
                    padding: EdgeInsets.all(20),
                    child: CircularProgressIndicator(color: Color(0xFF7C4DFF))))
          else
            _buildActivityGrid(_calStudiedDays, isDark, textColor),
          const SizedBox(height: 12),
          Row(
            children: [
              Container(
                width: 14,
                height: 14,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                      colors: [Color(0xFF6A1B9A), Color(0xFF9C27B0)]),
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
              const SizedBox(width: 6),
              Text('Studied',
                  style: TextStyle(
                      color: textColor.withValues(alpha: 0.6), fontSize: 12)),
              const SizedBox(width: 16),
              Container(
                width: 14,
                height: 14,
                decoration: BoxDecoration(
                  color: isDark
                      ? Colors.white.withValues(alpha: 0.06)
                      : Colors.black.withValues(alpha: 0.06),
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
              const SizedBox(width: 6),
              Text('Missed',
                  style: TextStyle(
                      color: textColor.withValues(alpha: 0.6), fontSize: 12)),
              const SizedBox(width: 16),
              Container(
                width: 14,
                height: 14,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(3),
                  border: Border.all(color: const Color(0xFF7C4DFF), width: 2),
                ),
              ),
              const SizedBox(width: 6),
              Text('Today',
                  style: TextStyle(
                      color: textColor.withValues(alpha: 0.6), fontSize: 12)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildActivityGrid(
      Set<String> studiedDays, bool isDark, Color textColor) {
    final now = DateTime.now();
    final displayMonth = _calendarMonth;
    final firstDay = DateTime(displayMonth.year, displayMonth.month, 1);
    final daysInMonth =
        DateTime(displayMonth.year, displayMonth.month + 1, 0).day;
    final startWeekday = firstDay.weekday - 1;
    const weekNames = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];
    final monthNames = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec'
    ];

    final List<int?> days = [
      ...List.filled(startWeekday, null),
      ...List.generate(daysInMonth, (i) => i + 1),
    ];
    while (days.length % 7 != 0) {
      days.add(null);
    }
    final rows = days.length ~/ 7;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '${monthNames[now.month - 1]} ${now.year}',
          style: const TextStyle(
            color: Color(0xFF7C4DFF),
            fontSize: 13,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 10),
        Row(
          children: weekNames
              .map((n) => Expanded(
                    child: Text(n,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: textColor.withValues(alpha: 0.4),
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                        )),
                  ))
              .toList(),
        ),
        const SizedBox(height: 6),
        ...List.generate(rows, (rowIndex) {
          final rowDays = days.sublist(rowIndex * 7, rowIndex * 7 + 7);
          return Padding(
            padding: const EdgeInsets.only(bottom: 5),
            child: Row(
              children: rowDays.map((day) {
                if (day == null) {
                  return const Expanded(child: SizedBox(height: 34));
                }
                final key =
                    '${displayMonth.year}-${displayMonth.month.toString().padLeft(2, '0')}-${day.toString().padLeft(2, '0')}';
                final isStudied = studiedDays.contains(key);
                final isToday = day == now.day &&
                    displayMonth.month == now.month &&
                    displayMonth.year == now.year;
                return Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 2),
                    child: Container(
                      height: 34,
                      decoration: BoxDecoration(
                        gradient: isStudied
                            ? const LinearGradient(
                                colors: [Color(0xFF6A1B9A), Color(0xFF9C27B0)])
                            : null,
                        color: isStudied
                            ? null
                            : (isDark
                                ? Colors.white.withValues(alpha: 0.06)
                                : Colors.black.withValues(alpha: 0.06)),
                        borderRadius: BorderRadius.circular(8),
                        border: isToday
                            ? Border.all(
                                color: const Color(0xFF7C4DFF), width: 2)
                            : null,
                      ),
                      child: Center(
                        child: Text(
                          '$day',
                          style: TextStyle(
                            color: isStudied
                                ? Colors.white
                                : textColor.withValues(alpha: 0.35),
                            fontSize: 11,
                            fontWeight:
                                isToday ? FontWeight.bold : FontWeight.normal,
                          ),
                        ),
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
          );
        }),
      ],
    );
  }

  Widget _buildMilestonesSection(int streak, bool isDark, Color textColor) {
    final milestones = [
      {
        'days': 3,
        'label': '3-Day Streak',
        'icon': Icons.flash_on,
        'color': Colors.blue
      },
      {
        'days': 7,
        'label': 'Week Warrior',
        'icon': Icons.star,
        'color': Colors.amber
      },
      {
        'days': 14,
        'label': '2-Week Champion',
        'icon': Icons.fitness_center,
        'color': Colors.orange
      },
      {
        'days': 30,
        'label': 'Monthly Master',
        'icon': Icons.emoji_events,
        'color': Colors.red
      },
      {
        'days': 60,
        'label': '2-Month Legend',
        'icon': Icons.workspace_premium,
        'color': Colors.purple
      },
      {
        'days': 100,
        'label': '100-Day Hero',
        'icon': Icons.military_tech,
        'color': Colors.teal
      },
    ];

    return _buildNeuCard(
      isDark: isDark,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.emoji_events,
                  color: Color(0xFF7C4DFF), size: 18),
              const SizedBox(width: 8),
              Text('Milestones',
                  style: TextStyle(
                      color: textColor,
                      fontSize: 16,
                      fontWeight: FontWeight.bold)),
            ],
          ),
          const SizedBox(height: 14),
          ...milestones.map((m) {
            final days = m['days'] as int;
            final achieved = streak >= days;
            final color = m['color'] as Color;
            return Container(
              margin: const EdgeInsets.only(bottom: 10),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                color: achieved
                    ? color.withValues(alpha: 0.12)
                    : isDark
                        ? Colors.white.withValues(alpha: 0.03)
                        : Colors.black.withValues(alpha: 0.03),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                    color: achieved
                        ? color.withValues(alpha: 0.4)
                        : Colors.transparent),
              ),
              child: Row(
                children: [
                  Icon(
                    achieved ? m['icon'] as IconData : Icons.lock_outline,
                    color: achieved ? color : Colors.grey,
                    size: 24,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(m['label'] as String,
                            style: TextStyle(
                              color: achieved
                                  ? textColor
                                  : textColor.withValues(alpha: 0.4),
                              fontWeight: FontWeight.w600,
                              fontSize: 14,
                            )),
                        Text(
                            achieved
                                ? 'Achieved!'
                                : '${days - streak} more days to go',
                            style: TextStyle(
                                color: achieved
                                    ? color
                                    : textColor.withValues(alpha: 0.3),
                                fontSize: 12)),
                      ],
                    ),
                  ),
                  if (achieved)
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: color.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.check, color: color, size: 14),
                          const SizedBox(width: 4),
                          Text(
                            'Done',
                            style: TextStyle(
                              color: color,
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    )
                  else
                    SizedBox(
                      width: 40,
                      height: 40,
                      child: CircularProgressIndicator(
                        value: (streak / days).clamp(0.0, 1.0),
                        strokeWidth: 3,
                        backgroundColor: textColor.withValues(alpha: 0.1),
                        valueColor: AlwaysStoppedAnimation<Color>(color),
                      ),
                    ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }

  Widget _buildNeuCard({required bool isDark, required Widget child}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _t.bgColor,
        borderRadius: BorderRadius.circular(20),
        boxShadow: isDark
            ? [
                BoxShadow(
                    color: Colors.black.withValues(alpha: 0.4),
                    offset: const Offset(5, 5),
                    blurRadius: 12),
                BoxShadow(
                    color: Colors.white.withValues(alpha: 0.04),
                    offset: const Offset(-5, -5),
                    blurRadius: 12),
              ]
            : [
                BoxShadow(
                    color: Colors.grey.withValues(alpha: 0.3),
                    offset: const Offset(5, 5),
                    blurRadius: 12),
                BoxShadow(
                    color: Colors.white.withValues(alpha: 0.9),
                    offset: const Offset(-5, -5),
                    blurRadius: 12),
              ],
      ),
      child: child,
    );
  }
}
