import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../Services/theme_provider.dart';
import '../Services/streak_service.dart';

class ProgressAnalyticsPage extends StatefulWidget {
  const ProgressAnalyticsPage({super.key});

  @override
  State<ProgressAnalyticsPage> createState() => _ProgressAnalyticsPageState();
}

class _ProgressAnalyticsPageState extends State<ProgressAnalyticsPage>
    with TickerProviderStateMixin {
  ThemeProvider get _t => Provider.of<ThemeProvider>(context, listen: false);
  late AnimationController _fadeController;
  late Animation<double> _fadeAnim;

  // Data holders
  int _totalTasks = 0;
  int _completedTasks = 0;
  int _totalNotes = 0;
  int _currentStreak = 0;
  int _totalStudyDays = 0;
  double _goalHours = 3;

  Map<String, int> _notesByType = {};
  List<Map<String, dynamic>> _weeklyHours = [];
  Set<String> _studiedDays = {};

  bool _isLoading = true;

  // ── Month navigation ──────────────────────────────────────────────
  DateTime _calendarMonth = DateTime(DateTime.now().year, DateTime.now().month);
  bool _calendarLoading = false;

  @override
  void initState() {
    super.initState();
    _fadeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    )..forward();
    _fadeAnim = CurvedAnimation(parent: _fadeController, curve: Curves.easeOut);
    _loadData();
  }

  @override
  void dispose() {
    _fadeController.dispose();
    super.dispose();
  }

  String get _uid => FirebaseAuth.instance.currentUser!.uid;

  Future<void> _loadData() async {
    try {
      final userDoc =
          await FirebaseFirestore.instance.collection('users').doc(_uid).get();
      final userData = userDoc.data() ?? {};

      // Tasks
      final tasksSnap = await FirebaseFirestore.instance
          .collection('users')
          .doc(_uid)
          .collection('tasks')
          .get();
      int total = tasksSnap.docs.length;
      int completed =
          tasksSnap.docs.where((d) => d['completed'] == true).length;

      // Notes
      final notesSnap = await FirebaseFirestore.instance
          .collection('users')
          .doc(_uid)
          .collection('notes')
          .get();

      Map<String, int> byType = {'text': 0, 'photo': 0, 'pdf': 0};
      for (final doc in notesSnap.docs) {
        final data = doc.data();
        final type = (data['type'] ?? 'text').toString();
        byType[type] = (byType[type] ?? 0) + 1;
      }

      final goalH = (userData['todayGoalHours'] ?? 3).toDouble();

      // ── Real weekly data from studyLogs ───────────────────────────
      final now = DateTime.now();
      final weekStart = now.subtract(const Duration(days: 6));
      final realLogs =
          await StreakService().getStudyLogsForRange(weekStart, now);

      List<Map<String, dynamic>> weekly = [];
      for (int i = 6; i >= 0; i--) {
        final day = now.subtract(Duration(days: i));
        final key =
            '${day.year}-${day.month.toString().padLeft(2, '0')}-${day.day.toString().padLeft(2, '0')}';
        final dayHours = realLogs[key] ?? 0.0;
        weekly.add({
          'day': _dayName(day.weekday),
          'studied': dayHours > 0,
          'hours': dayHours,
        });
      }

      // ── Real calendar data from streakHistory ─────────────────────
      final calStudied = await StreakService()
          .getStudiedDaysForMonth(_calendarMonth.year, _calendarMonth.month);

      if (mounted) {
        setState(() {
          _totalTasks = total;
          _completedTasks = completed;
          _totalNotes = notesSnap.docs.length;
          _currentStreak = userData['studyStreakDays'] ?? 0;
          _totalStudyDays = userData['totalStudyDays'] ?? 0;
          _goalHours = goalH;
          _notesByType = byType;
          _weeklyHours = weekly;
          _studiedDays = calStudied;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // ── Month navigation ──────────────────────────────────────────────
  Future<void> _goToPrevMonth() async {
    setState(() {
      _calendarMonth = DateTime(_calendarMonth.year, _calendarMonth.month - 1);
      _calendarLoading = true;
    });
    await _loadCalendarMonth();
  }

  Future<void> _goToNextMonth() async {
    final now = DateTime.now();
    if (_calendarMonth.year == now.year && _calendarMonth.month == now.month) {
      return;
    }
    setState(() {
      _calendarMonth = DateTime(_calendarMonth.year, _calendarMonth.month + 1);
      _calendarLoading = true;
    });
    await _loadCalendarMonth();
  }

  Future<void> _loadCalendarMonth() async {
    try {
      final studied = await StreakService()
          .getStudiedDaysForMonth(_calendarMonth.year, _calendarMonth.month);
      if (mounted) {
        setState(() {
          _studiedDays = studied;
          _calendarLoading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _calendarLoading = false);
    }
  }

  String _dayName(int weekday) {
    const days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    return days[weekday - 1];
  }

  // Overall score calculation
  int get _overallScore {
    int score = 0;
    if (_totalTasks > 0) {
      score += ((_completedTasks / _totalTasks) * 30).round();
    }
    score += (_currentStreak * 2).clamp(0, 30);
    score += (_totalNotes * 2).clamp(0, 20);
    score += (_totalStudyDays * 2).clamp(0, 20);
    return score.clamp(0, 100);
  }

  String get _scoreGrade {
    final s = _overallScore;
    if (s >= 90) return 'A+';
    if (s >= 80) return 'A';
    if (s >= 70) return 'B+';
    if (s >= 60) return 'B';
    if (s >= 50) return 'C';
    return 'D';
  }

  Color get _scoreColor {
    final s = _overallScore;
    if (s >= 80) return Colors.green;
    if (s >= 60) return Colors.orange;
    return Colors.red;
  }

  String get _scoreMessage {
    final taskRate = _totalTasks > 0 ? _completedTasks / _totalTasks : 0.0;
    if (_currentStreak >= 7 && taskRate >= 0.7) {
      return 'Outstanding! You are crushing your goals!';
    }
    if (_currentStreak >= 5) return 'Great consistency! Keep studying daily.';
    if (taskRate >= 0.8) {
      return 'Excellent task completion! Build your streak now.';
    }
    if (taskRate >= 0.5) return 'Improve by completing more tasks each day.';
    if (_totalNotes < 3) return 'Add more notes to boost your score.';
    if (_currentStreak == 0) return 'Start your streak — check in daily!';
    return 'Try maintaining your streak and completing tasks.';
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

  double get _weeklyTotalHours =>
      _weeklyHours.fold(0.0, (total, d) => total + (d['hours'] as double));

  double get _weeklyAvgHours {
    final studiedDays =
        _weeklyHours.where((d) => (d['studied'] as bool)).length;
    return studiedDays > 0 ? _weeklyTotalHours / studiedDays : 0.0;
  }

  Map<String, dynamic>? get _bestStudyDay {
    if (_weeklyHours.isEmpty) return null;
    final studied =
        _weeklyHours.where((d) => (d['hours'] as double) > 0).toList();
    if (studied.isEmpty) return null;
    studied
        .sort((a, b) => (b['hours'] as double).compareTo(a['hours'] as double));
    return studied.first;
  }

  String get _taskMessage {
    final rate = _totalTasks > 0 ? _completedTasks / _totalTasks : 0.0;
    if (rate >= 0.9) {
      return 'Excellent! You are completing almost all your tasks!';
    }
    if (rate >= 0.7) return 'Great job! Keep finishing those remaining tasks.';
    if (rate >= 0.5) return 'Try finishing more tasks to boost productivity.';
    if (rate > 0) return 'Low completion — focus on finishing pending tasks.';
    return 'Start completing tasks to improve your score!';
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
        title: const Text(
          'Progress Analytics',
          style: TextStyle(
              color: Colors.white, fontWeight: FontWeight.bold, fontSize: 18),
        ),
        iconTheme: const IconThemeData(color: Colors.white),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh, color: Colors.white),
            onPressed: () {
              setState(() => _isLoading = true);
              _loadData();
            },
          ),
        ],
      ),
      body: _isLoading
          ? const Center(
              child: CircularProgressIndicator(color: Color(0xFF7C4DFF)))
          : FadeTransition(
              opacity: _fadeAnim,
              child: RefreshIndicator(
                color: const Color(0xFF7C4DFF),
                onRefresh: _loadData,
                child: SingleChildScrollView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildOverallScoreCard(isDark, textColor),
                      const SizedBox(height: 16),
                      _buildQuickStats(isDark, textColor),
                      const SizedBox(height: 16),
                      if (_weeklyHours.any((d) => d['studied'] == true))
                        _buildWeeklyChart(isDark, textColor)
                      else
                        _buildEmptyCard(
                          isDark: isDark,
                          icon: Icons.bar_chart_rounded,
                          title: 'No Activity This Week',
                          message:
                              'Start studying to see your weekly activity chart.',
                          color: const Color(0xFF7C4DFF),
                        ),
                      const SizedBox(height: 16),
                      if (_totalTasks > 0)
                        _buildTasksCard(isDark, textColor)
                      else
                        _buildEmptyCard(
                          isDark: isDark,
                          icon: Icons.task_alt,
                          title: 'No Tasks Yet',
                          message:
                              'Add tasks in Study Planner to track your completion rate.',
                          color: Colors.teal,
                        ),
                      const SizedBox(height: 16),
                      if (_totalNotes > 0)
                        _buildNotesBreakdown(isDark, textColor)
                      else
                        _buildEmptyCard(
                          isDark: isDark,
                          icon: Icons.note_alt_outlined,
                          title: 'No Notes Yet',
                          message:
                              'Add notes in Notes Manager to see your subject breakdown.',
                          color: const Color(0xFF7C4DFF),
                        ),
                      const SizedBox(height: 16),
                      _buildWeeklyGoalCard(isDark, textColor),
                      const SizedBox(height: 16),
                      _buildBestDayCard(isDark, textColor),
                      const SizedBox(height: 16),
                      _buildHeatmapCard(isDark, textColor),
                      const SizedBox(height: 32),
                    ],
                  ),
                ),
              ),
            ),
    );
  }

  // ── Empty State Card ───────────────────────────────────────────────
  Widget _buildEmptyCard({
    required bool isDark,
    required IconData icon,
    required String title,
    required String message,
    required Color color,
  }) {
    return _buildNeuCard(
      isDark: isDark,
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: color, size: 24),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: TextStyle(
                        color: _t.textPrimary,
                        fontSize: 14,
                        fontWeight: FontWeight.bold)),
                const SizedBox(height: 4),
                Text(message,
                    style: TextStyle(
                        color: _t.textPrimary.withValues(alpha: 0.5),
                        fontSize: 12,
                        height: 1.4)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── Overall Score ──────────────────────────────────────────────────
  Widget _buildOverallScoreCard(bool isDark, Color textColor) {
    // Performance label with Icon instead of emoji
    Widget performanceLabel() {
      if (_overallScore >= 80) {
        return Row(
          children: [
            const Icon(Icons.emoji_events_rounded,
                color: Colors.amber, size: 15),
            const SizedBox(width: 4),
            Text('Excellent performance!',
                style: TextStyle(
                    color: textColor.withValues(alpha: 0.6), fontSize: 13)),
          ],
        );
      } else if (_overallScore >= 60) {
        return Row(
          children: [
            const Icon(Icons.trending_up_rounded, color: Colors.blue, size: 15),
            const SizedBox(width: 4),
            Text('Good progress, keep going!',
                style: TextStyle(
                    color: textColor.withValues(alpha: 0.6), fontSize: 13)),
          ],
        );
      } else {
        return Row(
          children: [
            const Icon(Icons.fitness_center_rounded,
                color: Colors.orange, size: 15),
            const SizedBox(width: 4),
            Text('Room for improvement!',
                style: TextStyle(
                    color: textColor.withValues(alpha: 0.6), fontSize: 13)),
          ],
        );
      }
    }

    return _buildNeuCard(
      isDark: isDark,
      child: Row(
        children: [
          SizedBox(
            width: 110,
            height: 110,
            child: Stack(
              alignment: Alignment.center,
              children: [
                SizedBox(
                  width: 110,
                  height: 110,
                  child: CircularProgressIndicator(
                    value: _overallScore / 100,
                    strokeWidth: 10,
                    backgroundColor: isDark
                        ? Colors.white.withValues(alpha: 0.08)
                        : Colors.black.withValues(alpha: 0.06),
                    valueColor: AlwaysStoppedAnimation<Color>(_scoreColor),
                  ),
                ),
                Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      '$_overallScore',
                      style: TextStyle(
                        color: _scoreColor,
                        fontSize: 28,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    Text(
                      _scoreGrade,
                      style: TextStyle(
                        color: _scoreColor,
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 20),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Overall Score',
                  style: TextStyle(
                    color: textColor,
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 6),
                performanceLabel(),
                const SizedBox(height: 8),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: _scoreColor.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(10),
                    border:
                        Border.all(color: _scoreColor.withValues(alpha: 0.3)),
                  ),
                  child: Text(
                    _scoreMessage,
                    style: TextStyle(
                        color: _scoreColor,
                        fontSize: 12,
                        fontWeight: FontWeight.w600),
                    textAlign: TextAlign.center,
                  ),
                ),
                const SizedBox(height: 12),
                _buildScoreRow(
                    'Tasks',
                    (_totalTasks > 0
                        ? (_completedTasks / _totalTasks * 30).round()
                        : 0),
                    30,
                    Colors.teal),
                const SizedBox(height: 4),
                _buildScoreRow('Streak', (_currentStreak * 2).clamp(0, 30), 30,
                    Colors.orange),
                const SizedBox(height: 4),
                _buildScoreRow(
                    'Notes',
                    _totalNotes * 2 > 20 ? 20 : _totalNotes * 2,
                    20,
                    const Color(0xFF7C4DFF)),
                const SizedBox(height: 4),
                _buildScoreRow(
                    'Study Days',
                    _totalStudyDays * 2 > 20 ? 20 : _totalStudyDays * 2,
                    20,
                    Colors.blue),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildScoreRow(String label, int value, int max, Color color) {
    return Row(
      children: [
        SizedBox(
          width: 70,
          child: Text(label,
              style: TextStyle(
                  color: _t.textPrimary.withValues(alpha: 0.5), fontSize: 11)),
        ),
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: max > 0 ? value / max : 0,
              minHeight: 6,
              backgroundColor: color.withValues(alpha: 0.15),
              valueColor: AlwaysStoppedAnimation<Color>(color),
            ),
          ),
        ),
        const SizedBox(width: 6),
        Text('$value/$max',
            style: TextStyle(
                color: color, fontSize: 10, fontWeight: FontWeight.bold)),
      ],
    );
  }

  // ── Quick Stats ────────────────────────────────────────────────────
  Widget _buildQuickStats(bool isDark, Color textColor) {
    return Row(
      children: [
        Expanded(
            child: _buildMiniStat(
                Icons.local_fire_department,
                '$_currentStreak',
                'Day Streak',
                Colors.orange,
                isDark,
                textColor)),
        const SizedBox(width: 10),
        Expanded(
            child: _buildMiniStat(Icons.note_alt_outlined, '$_totalNotes',
                'Total Notes', const Color(0xFF7C4DFF), isDark, textColor)),
        const SizedBox(width: 10),
        Expanded(
            child: _buildMiniStat(Icons.task_alt, '$_completedTasks',
                'Tasks Done', Colors.teal, isDark, textColor)),
        const SizedBox(width: 10),
        Expanded(
            child: _buildMiniStat(
                Icons.calendar_month_outlined,
                '$_totalStudyDays',
                'Study Days',
                Colors.blue,
                isDark,
                textColor)),
      ],
    );
  }

  Widget _buildMiniStat(IconData icon, String value, String label, Color color,
      bool isDark, Color textColor) {
    return _buildNeuCard(
      isDark: isDark,
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
      child: Column(
        children: [
          Icon(icon, color: color, size: 22),
          const SizedBox(height: 4),
          Text(value,
              style: TextStyle(
                  color: color, fontSize: 18, fontWeight: FontWeight.bold)),
          Text(label,
              style: TextStyle(
                  color: textColor.withValues(alpha: 0.5), fontSize: 10),
              textAlign: TextAlign.center),
        ],
      ),
    );
  }

  // ── Weekly Activity Chart ──────────────────────────────────────────
  Widget _buildWeeklyChart(bool isDark, Color textColor) {
    final maxHours = _weeklyHours.isEmpty
        ? 1.0
        : _weeklyHours
            .map((d) => (d['hours'] as double))
            .reduce((a, b) => a > b ? a : b)
            .clamp(1.0, double.infinity);

    return _buildNeuCard(
      isDark: isDark,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.bar_chart_rounded,
                  color: Color(0xFF7C4DFF), size: 20),
              const SizedBox(width: 8),
              Text('Weekly Activity',
                  style: TextStyle(
                      color: textColor,
                      fontSize: 16,
                      fontWeight: FontWeight.bold)),
              const Spacer(),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: const Color(0xFF7C4DFF).withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: const Text(
                  'Last 7 days',
                  style: TextStyle(
                      color: Color(0xFF7C4DFF),
                      fontSize: 11,
                      fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          SizedBox(
            height: 120,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: _weeklyHours.map((d) {
                final hours = d['hours'] as double;
                final studied = d['studied'] as bool;
                final heightRatio = hours / maxHours;

                return Column(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    if (studied)
                      Text(
                        _formatTime(hours),
                        style: const TextStyle(
                            color: Color(0xFF7C4DFF),
                            fontSize: 9,
                            fontWeight: FontWeight.bold),
                      ),
                    const SizedBox(height: 4),
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 800),
                      curve: Curves.easeOutBack,
                      width: 32,
                      height: studied ? (80 * heightRatio).clamp(8.0, 80.0) : 8,
                      decoration: BoxDecoration(
                        gradient: studied
                            ? const LinearGradient(
                                colors: [Color(0xFF6A1B9A), Color(0xFF9C27B0)],
                                begin: Alignment.bottomCenter,
                                end: Alignment.topCenter,
                              )
                            : null,
                        color: studied
                            ? null
                            : (isDark
                                ? Colors.white.withValues(alpha: 0.07)
                                : Colors.black.withValues(alpha: 0.07)),
                        borderRadius: const BorderRadius.vertical(
                            top: Radius.circular(8)),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      d['day'] as String,
                      style: TextStyle(
                          color: textColor.withValues(alpha: 0.5),
                          fontSize: 11),
                    ),
                  ],
                );
              }).toList(),
            ),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  decoration: BoxDecoration(
                    color: const Color(0xFF7C4DFF).withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Column(
                    children: [
                      Text(
                        _formatTime(_weeklyTotalHours),
                        style: const TextStyle(
                            color: Color(0xFF7C4DFF),
                            fontSize: 18,
                            fontWeight: FontWeight.bold),
                      ),
                      Text('Total this week',
                          style: TextStyle(
                              color: textColor.withValues(alpha: 0.5),
                              fontSize: 11)),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  decoration: BoxDecoration(
                    color: Colors.teal.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Column(
                    children: [
                      Text(
                        _formatTime(_weeklyAvgHours),
                        style: TextStyle(
                            color: Colors.teal.shade400,
                            fontSize: 18,
                            fontWeight: FontWeight.bold),
                      ),
                      Text('Avg per study day',
                          style: TextStyle(
                              color: textColor.withValues(alpha: 0.5),
                              fontSize: 11)),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ── Tasks Completion ──────────────────────────────────────────────
  Widget _buildTasksCard(bool isDark, Color textColor) {
    final completionRate =
        _totalTasks > 0 ? (_completedTasks / _totalTasks * 100).round() : 0;
    final pending = _totalTasks - _completedTasks;

    return _buildNeuCard(
      isDark: isDark,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.task_alt, color: Colors.teal, size: 20),
              const SizedBox(width: 8),
              Text('Task Completion',
                  style: TextStyle(
                      color: textColor,
                      fontSize: 16,
                      fontWeight: FontWeight.bold)),
              const Spacer(),
              Text('$completionRate%',
                  style: const TextStyle(
                      color: Colors.teal,
                      fontSize: 20,
                      fontWeight: FontWeight.bold)),
            ],
          ),
          const SizedBox(height: 14),
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: LinearProgressIndicator(
              value: _totalTasks > 0 ? _completedTasks / _totalTasks : 0,
              minHeight: 12,
              backgroundColor: isDark
                  ? Colors.white.withValues(alpha: 0.08)
                  : Colors.black.withValues(alpha: 0.06),
              valueColor: const AlwaysStoppedAnimation<Color>(Colors.teal),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              // Replaced ✅ with Icons.check_circle_rounded
              Expanded(
                  child: _buildTaskStat(Icons.check_circle_rounded, 'Completed',
                      '$_completedTasks', Colors.teal)),
              // Replaced ⏳ with Icons.hourglass_bottom_rounded
              Expanded(
                  child: _buildTaskStat(Icons.hourglass_bottom_rounded,
                      'Pending', '$pending', Colors.orange)),
              // Replaced 📋 with Icons.list_alt_rounded
              Expanded(
                  child: _buildTaskStat(Icons.list_alt_rounded, 'Total',
                      '$_totalTasks', const Color(0xFF7C4DFF))),
            ],
          ),
          const SizedBox(height: 10),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.teal.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: Colors.teal.withValues(alpha: 0.2)),
            ),
            child: Text(
              _taskMessage,
              style: TextStyle(
                  color: Colors.teal.shade600,
                  fontSize: 12,
                  fontWeight: FontWeight.w600),
              textAlign: TextAlign.center,
            ),
          ),
        ],
      ),
    );
  }

  // Updated signature: uses IconData instead of emoji string label
  Widget _buildTaskStat(
      IconData icon, String label, String value, Color color) {
    return Column(
      children: [
        Icon(icon, color: color, size: 20),
        const SizedBox(height: 4),
        Text(value,
            style: TextStyle(
                color: color, fontSize: 22, fontWeight: FontWeight.bold)),
        Text(label,
            style: TextStyle(
                color: _t.textPrimary.withValues(alpha: 0.5), fontSize: 11),
            textAlign: TextAlign.center),
      ],
    );
  }

  // ── Notes Breakdown ───────────────────────────────────────────────
  Widget _buildNotesBreakdown(bool isDark, Color textColor) {
    final textCount = _notesByType['text'] ?? 0;
    final photoCount = _notesByType['photo'] ?? 0;
    final pdfCount = _notesByType['pdf'] ?? 0;

    return _buildNeuCard(
      isDark: isDark,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.book_outlined,
                  color: Color(0xFF7C4DFF), size: 20),
              const SizedBox(width: 8),
              Text('Notes Breakdown',
                  style: TextStyle(
                      color: textColor,
                      fontSize: 16,
                      fontWeight: FontWeight.bold)),
              const Spacer(),
              Text('$_totalNotes total',
                  style: TextStyle(
                      color: textColor.withValues(alpha: 0.5), fontSize: 12)),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              _buildNoteTypeBadge(Icons.text_snippet_outlined, 'Text',
                  textCount, const Color(0xFF7C4DFF)),
              const SizedBox(width: 10),
              _buildNoteTypeBadge(
                  Icons.image_outlined, 'Photos', photoCount, Colors.teal),
              const SizedBox(width: 10),
              _buildNoteTypeBadge(
                  Icons.picture_as_pdf_outlined, 'PDFs', pdfCount, Colors.red),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildNoteTypeBadge(
      IconData icon, String label, int count, Color color) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withValues(alpha: 0.25)),
        ),
        child: Column(
          children: [
            Icon(icon, color: color, size: 22),
            const SizedBox(height: 4),
            Text('$count',
                style: TextStyle(
                    color: color, fontSize: 18, fontWeight: FontWeight.bold)),
            Text(label,
                style: TextStyle(
                    color: _t.textPrimary.withValues(alpha: 0.5),
                    fontSize: 11)),
          ],
        ),
      ),
    );
  }

  // ── Weekly Goal Card ─────────────────────────────────────────────
  Widget _buildWeeklyGoalCard(bool isDark, Color textColor) {
    final weeklyGoal = _goalHours * 7;
    final progress =
        weeklyGoal > 0 ? (_weeklyTotalHours / weeklyGoal).clamp(0.0, 1.0) : 0.0;
    final percent = (progress * 100).toInt();

    return _buildNeuCard(
      isDark: isDark,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.flag_outlined,
                  color: Color(0xFF7C4DFF), size: 20),
              const SizedBox(width: 8),
              Text('Weekly Study Goal',
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
                progress >= 1.0 ? Colors.green : const Color(0xFF7C4DFF),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Completed: ${_formatTime(_weeklyTotalHours)}',
                  style: const TextStyle(
                      color: Color(0xFF7C4DFF),
                      fontSize: 12,
                      fontWeight: FontWeight.w600)),
              Text('Goal: ${weeklyGoal.toStringAsFixed(0)}h',
                  style: TextStyle(
                      color: textColor.withValues(alpha: 0.5), fontSize: 12)),
            ],
          ),
        ],
      ),
    );
  }

  // ── Best Study Day ────────────────────────────────────────────────
  Widget _buildBestDayCard(bool isDark, Color textColor) {
    final best = _bestStudyDay;
    return _buildNeuCard(
      isDark: isDark,
      child: Row(
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                  colors: [Color(0xFF6A1B9A), Color(0xFF9C27B0)]),
              borderRadius: BorderRadius.circular(14),
            ),
            child: const Center(
              // Icon instead of ⭐ emoji
              child: Icon(Icons.star_rounded, color: Colors.white, size: 32),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Best Study Day',
                    style: TextStyle(
                        color: textColor.withValues(alpha: 0.5),
                        fontSize: 12,
                        fontWeight: FontWeight.w600)),
                const SizedBox(height: 4),
                Text(
                  best != null ? best['day'] as String : 'No data yet',
                  style: TextStyle(
                      color: textColor,
                      fontSize: 20,
                      fontWeight: FontWeight.bold),
                ),
                if (best != null)
                  Text(
                    '${_formatTime(best['hours'] as double)} studied',
                    style: const TextStyle(
                        color: Color(0xFF7C4DFF),
                        fontSize: 13,
                        fontWeight: FontWeight.w600),
                  ),
              ],
            ),
          ),
          if (best != null)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.amber.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                _formatTime(best['hours'] as double),
                style: const TextStyle(
                    color: Colors.amber,
                    fontWeight: FontWeight.bold,
                    fontSize: 16),
              ),
            ),
        ],
      ),
    );
  }

  // ── 30-day Heatmap ────────────────────────────────────────────────
  Widget _buildHeatmapCard(bool isDark, Color textColor) {
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
    final now = DateTime.now();
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
                  color: Color(0xFF7C4DFF), size: 20),
              const SizedBox(width: 8),
              Text('Activity Calendar',
                  style: TextStyle(
                      color: textColor,
                      fontSize: 16,
                      fontWeight: FontWeight.bold)),
              const Spacer(),
              IconButton(
                icon: const Icon(Icons.chevron_left, color: Color(0xFF7C4DFF)),
                onPressed: _calendarLoading ? null : _goToPrevMonth,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
              ),
              Text(
                '${monthNames[_calendarMonth.month - 1]} ${_calendarMonth.year}',
                style: const TextStyle(
                    color: Color(0xFF7C4DFF),
                    fontSize: 13,
                    fontWeight: FontWeight.w600),
              ),
              IconButton(
                icon: Icon(Icons.chevron_right,
                    color: isCurrentMonth
                        ? Colors.grey.withValues(alpha: 0.4)
                        : const Color(0xFF7C4DFF)),
                onPressed: (isCurrentMonth || _calendarLoading)
                    ? null
                    : _goToNextMonth,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text('${_studiedDays.length} days studied this month',
              style: TextStyle(
                  color: textColor.withValues(alpha: 0.5), fontSize: 12)),
          const SizedBox(height: 12),
          _calendarLoading
              ? const Center(
                  child: Padding(
                  padding: EdgeInsets.all(20),
                  child: CircularProgressIndicator(color: Color(0xFF7C4DFF)),
                ))
              : _buildCalendarGrid([], isDark, textColor),
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
            ],
          ),
        ],
      ),
    );
  }

  // ── Monthly Calendar Grid ─────────────────────────────────────────
  Widget _buildCalendarGrid(List<DateTime> days, bool isDark, Color textColor) {
    final now = DateTime.now();
    final displayMonth = _calendarMonth;
    final firstDay = DateTime(displayMonth.year, displayMonth.month, 1);
    final daysInMonth =
        DateTime(displayMonth.year, displayMonth.month + 1, 0).day;
    final startWeekday = firstDay.weekday - 1;
    const weekNames = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];

    final List<int?> calDays = [
      ...List.filled(startWeekday, null),
      ...List.generate(daysInMonth, (i) => i + 1),
    ];
    while (calDays.length % 7 != 0) {
      calDays.add(null);
    }
    final rows = calDays.length ~/ 7;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
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
          final rowDays = calDays.sublist(rowIndex * 7, rowIndex * 7 + 7);
          return Padding(
            padding: const EdgeInsets.only(bottom: 5),
            child: Row(
              children: rowDays.map((day) {
                if (day == null) {
                  return const Expanded(child: SizedBox(height: 34));
                }
                final key =
                    '${displayMonth.year}-${displayMonth.month.toString().padLeft(2, '0')}-${day.toString().padLeft(2, '0')}';
                final isStudied = _studiedDays.contains(key);
                final isCurrentMonthDisplay = displayMonth.year == now.year &&
                    displayMonth.month == now.month;
                final isToday = isCurrentMonthDisplay && day == now.day;
                // Future only applies in current month, and only for days strictly after today
                final isFuture = isCurrentMonthDisplay && day > now.day;
                // Label for tooltip
                final monthNames2 = [
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
                final tooltipLabel = isStudied
                    ? 'Studied'
                    : isToday
                        ? 'Today'
                        : isFuture
                            ? 'Upcoming'
                            : 'Not studied';
                final tooltipDate =
                    '${monthNames2[displayMonth.month - 1]} $day, ${displayMonth.year}';
                return Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 2),
                    child: Tooltip(
                      message: '$tooltipDate — $tooltipLabel',
                      child: Container(
                        height: 34,
                        decoration: BoxDecoration(
                          gradient: isStudied
                              ? const LinearGradient(colors: [
                                  Color(0xFF6A1B9A),
                                  Color(0xFF9C27B0)
                                ])
                              : null,
                          color: isStudied
                              ? null
                              : isFuture
                                  ? (isDark
                                      ? Colors.white.withValues(alpha: 0.02)
                                      : Colors.black.withValues(alpha: 0.02))
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
                                  : isFuture
                                      ? textColor.withValues(alpha: 0.18)
                                      : textColor.withValues(alpha: 0.35),
                              fontSize: 11,
                              fontWeight:
                                  isToday ? FontWeight.bold : FontWeight.normal,
                            ),
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

  // ── Neu Card ──────────────────────────────────────────────────────
  Widget _buildNeuCard({
    required bool isDark,
    required Widget child,
    EdgeInsets? padding,
  }) {
    return Container(
      width: double.infinity,
      padding: padding ?? const EdgeInsets.all(16),
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
