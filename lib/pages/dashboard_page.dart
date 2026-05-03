import 'package:flutter/material.dart';
import 'dart:async';
import 'package:provider/provider.dart';
import '../Services/auth_service.dart';
import '../Services/streak_service.dart';
import '../Services/theme_provider.dart';
import '../widgets/feature_card.dart';
import '../widgets/profile_header.dart';
import '../widgets/progress_section.dart';
import 'login_page.dart';
import 'yt_notes_page.dart';
import 'ai_test_generator_page.dart';
import 'study_planner_page.dart';
import 'notes_manager_page.dart';
import 'study_streak_page.dart';
import 'progress_analytics_page.dart';
import 'leaderboard_page.dart';

class DashboardPage extends StatefulWidget {
  const DashboardPage({super.key});

  @override
  State<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends State<DashboardPage>
    with WidgetsBindingObserver {
  final _streakService = StreakService();

  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();

  // ── Study Session Timer ─────────────────────────────────────────
  // Tracks ONLY unsaved seconds since last save.
  // Resets to 0 after each save — prevents double counting.
  int _sessionSeconds = 0; // seconds since last save
  Timer? _timer;
  Timer? _autoSaveTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _streakService.resetDailyHoursIfNewDay();
    _startSessionTimer();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _timer?.cancel();
    _autoSaveTimer?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      // App going background — save elapsed time and stop counting
      _saveAndStopTimer();
    } else if (state == AppLifecycleState.resumed) {
      // App came back — start fresh session
      _startSessionTimer();
    }
  }

  void _startSessionTimer() {
    _timer?.cancel();
    _autoSaveTimer?.cancel();
    _sessionSeconds = 0;

    // Rebuild UI every second so ProgressSection shows live per-minute updates.
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      setState(() => _sessionSeconds++);
    });

    // Auto-save every minute to keep Firestore reasonably in sync.
    _autoSaveTimer = Timer.periodic(const Duration(minutes: 1), (_) {
      _saveCurrentSession();
    });
  }

  // Save elapsed time without stopping timer
  Future<void> _saveCurrentSession() async {
    if (_sessionSeconds < 30) return;
    final elapsed = _sessionSeconds;
    _sessionSeconds = 0; // Reset counter after save
    await _streakService.saveStudySession(elapsed);
  }

  // Save and fully stop timer (on pause/logout)
  Future<void> _saveAndStopTimer() async {
    _timer?.cancel();
    _autoSaveTimer?.cancel();
    if (_sessionSeconds >= 30) {
      await _streakService.saveStudySession(_sessionSeconds);
    }
    _sessionSeconds = 0;
  }

  // ── Side Drawer ──────────────────────────────────────────────────
  Widget _buildDrawer(dynamic user, ThemeProvider t) {
    return Drawer(
      backgroundColor: t.bgColor,
      child: SafeArea(
        child: Column(
          children: [
            // Header
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(24),
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  colors: [Color(0xFF6A1B9A), Color(0xFF9C27B0)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 64,
                    height: 64,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.2),
                      shape: BoxShape.circle,
                      border: Border.all(
                          color: Colors.white.withValues(alpha: 0.4), width: 2),
                    ),
                    child: Center(
                      child: Text(
                        user.username.isNotEmpty
                            ? user.username[0].toUpperCase()
                            : 'S',
                        style: const TextStyle(
                            color: Colors.white,
                            fontSize: 28,
                            fontWeight: FontWeight.bold),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(user.username,
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.bold)),
                  const SizedBox(height: 2),
                  Text(user.email,
                      style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.7),
                          fontSize: 12)),
                ],
              ),
            ),

            const SizedBox(height: 8),

            // Menu items
            _drawerItem(Icons.dashboard_outlined, 'Dashboard', t, () {
              Navigator.pop(context);
            }),
            _drawerItem(Icons.local_fire_department_outlined, 'Study Streak', t,
                () {
              Navigator.pop(context);
              Navigator.push(context,
                  MaterialPageRoute(builder: (_) => const StudyStreakPage()));
            }),
            _drawerItem(Icons.show_chart, 'Progress Analytics', t, () {
              Navigator.pop(context);
              Navigator.push(
                  context,
                  MaterialPageRoute(
                      builder: (_) => const ProgressAnalyticsPage()));
            }),
            _drawerItem(Icons.emoji_events_outlined, 'Leaderboard', t, () {
              Navigator.pop(context);
              Navigator.push(context,
                  MaterialPageRoute(builder: (_) => const LeaderboardPage()));
            }),

            const Spacer(),

            Divider(color: t.textSecondary.withValues(alpha: 0.2)),

            // Theme toggle
            _drawerItem(
              t.isDark ? Icons.wb_sunny_rounded : Icons.nightlight_round,
              t.isDark ? 'Light Mode' : 'Dark Mode',
              t,
              () {
                Navigator.pop(context);
                _toggleTheme();
              },
            ),

            // Logout
            _drawerItem(Icons.logout_rounded, 'Logout', t, () async {
              Navigator.pop(context);
              await _saveAndStopTimer();
              await AuthService().logout();
              if (mounted) {
                Navigator.pushAndRemoveUntil(
                  context,
                  MaterialPageRoute(builder: (_) => const LoginPage()),
                  (_) => false,
                );
              }
            }, color: Colors.red),

            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  Widget _drawerItem(
      IconData icon, String label, ThemeProvider t, VoidCallback onTap,
      {Color? color}) {
    return ListTile(
      leading: Icon(icon, color: color ?? const Color(0xFF7C4DFF), size: 22),
      title: Text(label,
          style: TextStyle(
            color: color ?? t.textPrimary,
            fontWeight: FontWeight.w500,
            fontSize: 15,
          )),
      onTap: onTap,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 2),
    );
  }

  List<Map<String, dynamic>> _features(BuildContext context) => [
        {
          'title': 'YT Notes',
          'icon': Icons.smart_display,
          'page': const YTNotesPage()
        },
        {
          'title': 'Study Planner',
          'icon': Icons.calendar_today,
          'page': const StudyPlannerPage()
        },
        {
          'title': 'Notes Manager',
          'icon': Icons.note_alt,
          'page': const NotesManagerPage()
        },
        {
          'title': 'Progress',
          'icon': Icons.show_chart,
          'page': const ProgressAnalyticsPage()
        },
        {
          'title': 'Study Streak',
          'icon': Icons.local_fire_department,
          'page': const StudyStreakPage()
        },
        {
          'title': 'Leaderboard',
          'icon': Icons.emoji_events,
          'page': const LeaderboardPage()
        },
        {
          'title': 'AI Test Generator',
          'icon': Icons.psychology,
          'page': const AITestGeneratorPage()
        },
      ];

  void _toggleTheme() {
    Provider.of<ThemeProvider>(context, listen: false).toggle();
  }

  @override
  Widget build(BuildContext context) {
    final user = AuthService().currentUser!;
    final t = Provider.of<ThemeProvider>(context);

    return Scaffold(
      key: _scaffoldKey,
      backgroundColor: t.bgColor,
      drawer: _buildDrawer(user, t),
      appBar: AppBar(
        automaticallyImplyLeading: false,
        elevation: 0,
        flexibleSpace: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              colors: [Color(0xFF6A1B9A), Color(0xFF9C27B0)],
            ),
          ),
        ),
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.25),
                shape: BoxShape.circle,
              ),
              child: Image.asset(
                'assets/logo.png',
                height: 18,
              ),
            ),
            const SizedBox(width: 10),
            const Text('ACADIFY',
                style: TextStyle(
                    fontWeight: FontWeight.bold, color: Colors.white)),
          ],
        ),
        centerTitle: true,
        leading: IconButton(
          icon: const Icon(Icons.menu_rounded, color: Colors.white),
          onPressed: () => _scaffoldKey.currentState?.openDrawer(),
        ),
        actions: [
          IconButton(
            tooltip: t.isDark ? 'Switch to Light' : 'Switch to Dark',
            icon: Icon(
              t.isDark ? Icons.wb_sunny_rounded : Icons.nightlight_round,
              color: Colors.white,
            ),
            onPressed: _toggleTheme,
          ),
        ],
      ),
      body: CustomScrollView(
        slivers: [
          // ── Greeting + Profile ────────────────────────────────────
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(24, 24, 24, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Hello, ${user.username}!',
                    style: TextStyle(
                      fontSize: 26,
                      fontWeight: FontWeight.bold,
                      color: t.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text('Ready to study today?',
                      style: TextStyle(fontSize: 15, color: t.textSecondary)),
                  const SizedBox(height: 20),
                  ProfileHeader(user: user),
                  const SizedBox(height: 24),
                ],
              ),
            ),
          ),

          // ── Feature Grid ──────────────────────────────────────────
          SliverPadding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            sliver: SliverGrid(
              gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                maxCrossAxisExtent: 220,
                crossAxisSpacing: 20,
                mainAxisSpacing: 20,
                childAspectRatio: 1.05,
              ),
              delegate: SliverChildBuilderDelegate(
                (context, i) {
                  final f = _features(context)[i];
                  return FeatureCard(
                    title: f['title'] as String,
                    icon: f['icon'] as IconData,
                    page: f['page'] as Widget,
                  );
                },
                childCount: _features(context).length,
              ),
            ),
          ),

          // ── Progress Section ──────────────────────────────────────
          const SliverToBoxAdapter(child: SizedBox(height: 28)),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: ProgressSection(user: user, liveSeconds: _sessionSeconds),
            ),
          ),
          const SliverToBoxAdapter(child: SizedBox(height: 32)),
        ],
      ),
    );
  }
}
