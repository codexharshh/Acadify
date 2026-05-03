import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class StreakService {
  // ── Singleton ─────────────────────────────────────────────────────
  static final StreakService _instance = StreakService._internal();
  factory StreakService() => _instance;
  StreakService._internal();

  // ── Session state (in-memory only) ───────────────────────────────
  // Timer logic is in DashboardPage — StreakService only handles saves.
  String _lastSaveDate = '';

  // ── Firestore refs ────────────────────────────────────────────────
  String get _uid => FirebaseAuth.instance.currentUser!.uid;

  DocumentReference get _userDoc =>
      FirebaseFirestore.instance.collection('users').doc(_uid);

  CollectionReference get _streakHistoryRef =>
      _userDoc.collection('streakHistory');

  CollectionReference get _studyLogsRef => _userDoc.collection('studyLogs');

  // ── Date helpers ──────────────────────────────────────────────────
  String _dateKey(DateTime dt) =>
      '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}';

  String get _todayKey => _dateKey(DateTime.now());

  // ── Daily reset (call once on app open) ──────────────────────────
  Future<void> resetDailyHoursIfNewDay() async {
    try {
      final snap = await _userDoc.get();
      final data = snap.data() as Map<String, dynamic>? ?? {};
      final lastReset = data['lastResetDate'] ?? '';
      final today = _todayKey;
      final now = DateTime.now();

      if (lastReset != today) {
        // New day — reset today's counter
        Map<String, dynamic> updateData = {
          'todayStudiedHours': 0.0,
          'lastResetDate': today,
        };

        // Streak break check: if lastCheckin is not today or yesterday → reset streak
        final lastCheckin = (data['lastCheckinDate'] ?? '') as String;
        final yesterday = DateTime(now.year, now.month, now.day - 1);
        final yesterdayKey = _dateKey(yesterday);

        if (lastCheckin.isNotEmpty &&
            lastCheckin != today &&
            lastCheckin != yesterdayKey) {
          // Streak broken — reset to 0
          updateData['studyStreakDays'] = 0;
        }

        await _userDoc.set(updateData, SetOptions(merge: true));

        // Reset in-memory tracking
        _lastSaveDate = today;
      } else {
        _lastSaveDate = today;
      }
    } catch (_) {}
  }

  // ── Save a study session (called by dashboard timer) ─────────────
  // Only saves REAL elapsed seconds — never auto-increments.
  Future<void> saveStudySession(int elapsedSeconds) async {
    if (elapsedSeconds < 30) return; // ignore < 30 sec sessions

    final hours = elapsedSeconds / 3600.0;
    final today = _todayKey;

    // If day changed mid-session, reset first
    if (_lastSaveDate.isNotEmpty && _lastSaveDate != today) {
      await resetDailyHoursIfNewDay();
    }

    try {
      // 1. Update today's running total on user doc
      await _userDoc.set({
        'todayStudiedHours': FieldValue.increment(hours),
        'lastResetDate': today,
      }, SetOptions(merge: true));

      // 2. Update studyLogs for real weekly/monthly data
      await _studyLogsRef.doc(today).set({
        'date': today,
        'hours': FieldValue.increment(hours),
        'updatedAt': Timestamp.now(),
      }, SetOptions(merge: true));

      // 3. Check if streak should be updated
      await _updateStreakIfEligible();
    } catch (_) {}
  }

  // ── Task completed → count as 0.5h study ─────────────────────────
  Future<void> onTaskCompleted() async {
    await saveStudySession(1800); // 30 min equivalent
  }

  // ── Note added → count as 0.25h study ────────────────────────────
  Future<void> onNoteAdded() async {
    await saveStudySession(900); // 15 min equivalent
  }

  // ── Streak update logic ───────────────────────────────────────────
  Future<void> _updateStreakIfEligible() async {
    try {
      final today = _todayKey;
      final now = DateTime.now();

      final snap = await _userDoc.get();
      final data = snap.data() as Map<String, dynamic>? ?? {};
      final todayHours = (data['todayStudiedHours'] ?? 0.0) as double;

      // Need at least 1 hour studied today
      if (todayHours < 1.0) return;

      // Already recorded today?
      final historyDoc = await _streakHistoryRef.doc(today).get();
      if (historyDoc.exists) return;

      // Record today in history
      await _streakHistoryRef.doc(today).set({
        'date': today,
        'studied': true,
        'hours': todayHours,
        'recordedAt': Timestamp.now(),
      });

      // Calculate streak
      final currentStreak = (data['studyStreakDays'] ?? 0) as int;
      final lastCheckin = (data['lastCheckinDate'] ?? '') as String;
      final longestStreak = (data['longestStreak'] ?? 0) as int;

      final yesterday = DateTime(now.year, now.month, now.day - 1);
      final yesterdayKey = _dateKey(yesterday);

      int newStreak;
      if (lastCheckin == yesterdayKey) {
        newStreak = currentStreak + 1;
      } else if (lastCheckin == today) {
        return;
      } else {
        newStreak = 1;
      }

      await _userDoc.set({
        'studyStreakDays': newStreak,
        'lastCheckinDate': today,
        'longestStreak': newStreak > longestStreak ? newStreak : longestStreak,
        'totalStudyDays': FieldValue.increment(1),
      }, SetOptions(merge: true));
    } catch (_) {}
  }

  // ── Get real study hours for a date range (weekly/monthly charts) ─
  Future<Map<String, double>> getStudyLogsForRange(
      DateTime start, DateTime end) async {
    try {
      final startKey = _dateKey(start);
      final endKey = _dateKey(end);

      final snap = await _studyLogsRef
          .where('date', isGreaterThanOrEqualTo: startKey)
          .where('date', isLessThanOrEqualTo: endKey)
          .get();

      final Map<String, double> result = {};
      for (final doc in snap.docs) {
        final data = doc.data() as Map<String, dynamic>;
        result[doc.id] = (data['hours'] ?? 0.0).toDouble();
      }
      return result;
    } catch (_) {
      return {};
    }
  }

  // ── Get streak history for a month ───────────────────────────────
  Future<Set<String>> getStudiedDaysForMonth(int year, int month) async {
    try {
      final startKey = '$year-${month.toString().padLeft(2, '0')}-01';
      final lastDay = DateTime(year, month + 1, 0).day;
      final endKey =
          '$year-${month.toString().padLeft(2, '0')}-${lastDay.toString().padLeft(2, '0')}';

      final snap = await _streakHistoryRef
          .where('date', isGreaterThanOrEqualTo: startKey)
          .where('date', isLessThanOrEqualTo: endKey)
          .get();

      return snap.docs.map((d) => d.id).toSet();
    } catch (_) {
      return {};
    }
  }
}
