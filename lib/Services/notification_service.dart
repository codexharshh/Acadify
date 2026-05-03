// lib/Services/notification_service.dart
// Task reminder and missed-task notifications for Flutter Web.
// Calls JS helper functions defined in web/index.html.

import 'dart:js_interop';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

// ── External JS function declarations ────────────────────────────────
// These must match the function names exported in web/index.html.

@JS('requestNotificationPermission')
external void _jsRequestPermission();

@JS('getNotificationPermission')
external String _jsGetPermission();

@JS('showTaskNotification')
external void _jsShowNotification(String title, String body);

@JS('hasNotificationSupport')
external bool _jsHasSupport();

// ─────────────────────────────────────────────────────────────────────

class NotificationService {
  static final NotificationService _instance = NotificationService._internal();
  factory NotificationService() => _instance;
  NotificationService._internal();

  // Track fired notifications to avoid duplicates within a session.
  final Set<String> _fired = {};

  String get _uid => FirebaseAuth.instance.currentUser!.uid;

  // ── Check if browser notifications are supported ──────────────────
  bool get isSupported {
    try {
      return _jsHasSupport();
    } catch (_) {
      return false;
    }
  }

  // ── Request browser notification permission ───────────────────────
  Future<bool> requestPermission() async {
    try {
      if (!isSupported) return false;
      _jsRequestPermission();
      await Future.delayed(const Duration(milliseconds: 500));
      return _jsGetPermission() == 'granted';
    } catch (_) {
      return false;
    }
  }

  bool get hasPermission {
    try {
      if (!isSupported) return false;
      return _jsGetPermission() == 'granted';
    } catch (_) {
      return false;
    }
  }

  // ── Show notification via index.html helper ───────────────────────
  void _show(String title, String body) {
    try {
      _jsShowNotification(title, body);
    } catch (_) {}
  }

  // ── Main check — call every minute from dashboard ─────────────────
  Future<void> checkReminders() async {
    if (!isSupported || !hasPermission) return;

    try {
      final now = DateTime.now();

      final tasksSnap = await FirebaseFirestore.instance
          .collection('users')
          .doc(_uid)
          .collection('tasks')
          .where('completed', isEqualTo: false)
          .get();

      for (final doc in tasksSnap.docs) {
        final data = doc.data();
        final dueDate = (data['dueDate'] as Timestamp).toDate();
        final subject = data['subject'] as String? ?? 'Task';
        final id = doc.id;
        final diffMin = dueDate.difference(now).inMinutes;

        // 30-minute reminder
        if (diffMin <= 30 && diffMin > 25) {
          _fireOnce('${id}_30min', 'Task Reminder — 30 min left',
              '"$subject" is due in 30 minutes. Get ready!');
        }

        // 10-minute reminder
        if (diffMin <= 10 && diffMin > 5) {
          _fireOnce('${id}_10min', 'Task Due Soon — 10 min left',
              '"$subject" is due in 10 minutes. Start now!');
        }

        // 5-minute reminder
        if (diffMin <= 5 && diffMin > 0) {
          _fireOnce('${id}_5min', 'Hurry! 5 Minutes Left',
              '"$subject" is due very soon. Wrap it up!');
        }

        // Due right now
        if (diffMin == 0) {
          _fireOnce('${id}_now', 'Task Due Now!',
              '"$subject" is due right now. Complete it!');
        }

        // Missed — 1 to 3 minutes after due
        if (diffMin < 0 && diffMin >= -3) {
          _fireOnce('${id}_missed', 'Missed Task!',
              '"$subject" was due ${(-diffMin)} minute(s) ago and is still incomplete.');
        }

        // Still incomplete — 1 hour overdue
        if (diffMin <= -60 && diffMin >= -63) {
          _fireOnce('${id}_missed_1h', 'Task Still Incomplete!',
              '"$subject" is overdue by 1 hour. Complete or reschedule it.');
        }
      }
    } catch (_) {}
  }

  void _fireOnce(String key, String title, String body) {
    if (!_fired.contains(key)) {
      _fired.add(key);
      _show(title, body);
    }
  }

  // ── Clear cache on new day ────────────────────────────────────────
  void clearCache() => _fired.clear();
}
