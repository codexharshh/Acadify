import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:fl_chart/fl_chart.dart';
import '../Services/theme_provider.dart';

class ProgressPage extends StatefulWidget {
  const ProgressPage({super.key});

  @override
  State<ProgressPage> createState() => _ProgressPageState();
}

class _ProgressPageState extends State<ProgressPage> {
  final ThemeProvider _t = ThemeProvider();
  final _db = FirebaseFirestore.instance;

  int _totalTasks = 0;
  int _completedTasks = 0;
  int _totalNotes = 0;
  int _pendingTasks = 0;
  bool _loading = true;
  Map<String, int> _subjectNotes = {};
  List<int> _weeklyCompleted = List.filled(7, 0);

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  String get _uid => FirebaseAuth.instance.currentUser!.uid;

  Future<void> _loadData() async {
    try {
      final tasksSnap =
          await _db.collection('users').doc(_uid).collection('tasks').get();
      final notesSnap =
          await _db.collection('users').doc(_uid).collection('notes').get();

      final Map<String, int> subjectMap = {};
      for (final doc in notesSnap.docs) {
        final data = doc.data();
        final cat = (data['subject'] as String?) ??
            (data['category'] as String?) ??
            'General';
        subjectMap[cat] = (subjectMap[cat] ?? 0) + 1;
      }

      final List<int> weekly = List.filled(7, 0);
      final now = DateTime.now();
      for (final doc in tasksSnap.docs) {
        final data = doc.data();
        if (data['completed'] == true && data['createdAt'] != null) {
          final ts = (data['createdAt'] as Timestamp).toDate();
          final diff = now.difference(ts).inDays;
          if (diff < 7) weekly[6 - diff]++;
        }
      }

      final completed =
          tasksSnap.docs.where((d) => d['completed'] == true).length;

      if (mounted) {
        setState(() {
          _totalTasks = tasksSnap.docs.length;
          _completedTasks = completed;
          _pendingTasks = _totalTasks - completed;
          _totalNotes = notesSnap.docs.length;
          _subjectNotes = subjectMap;
          _weeklyCompleted = weekly;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _t.bgColor,
      appBar: AppBar(
        title: const Text('Progress Analytics',
            style: TextStyle(color: Colors.white)),
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
        flexibleSpace: Container(
          decoration: const BoxDecoration(
            gradient:
                LinearGradient(colors: [Color(0xFF6A1B9A), Color(0xFF9C27B0)]),
          ),
        ),
      ),
      body: _loading
          ? const Center(
              child: CircularProgressIndicator(color: Color(0xFF7C4DFF)))
          : RefreshIndicator(
              onRefresh: _loadData,
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _sectionTitle('Overview'),
                    const SizedBox(height: 12),
                    Row(children: [
                      Expanded(
                          child: _statCard('Total Tasks', '$_totalTasks',
                              Icons.task_alt, Colors.blue)),
                      const SizedBox(width: 12),
                      Expanded(
                          child: _statCard('Completed', '$_completedTasks',
                              Icons.check_circle_outline, Colors.green)),
                    ]),
                    const SizedBox(height: 12),
                    Row(children: [
                      Expanded(
                          child: _statCard('Pending', '$_pendingTasks',
                              Icons.pending_outlined, Colors.orange)),
                      const SizedBox(width: 12),
                      Expanded(
                          child: _statCard(
                              'Total Notes',
                              '$_totalNotes',
                              Icons.note_alt_outlined,
                              const Color(0xFF7C4DFF))),
                    ]),
                    const SizedBox(height: 28),
                    _sectionTitle('Task Completion'),
                    const SizedBox(height: 16),
                    _neuCard(
                        child: _totalTasks == 0
                            ? _emptyState('No tasks yet!')
                            : SizedBox(
                                height: 200,
                                child: Row(children: [
                                  Expanded(
                                    child: PieChart(PieChartData(
                                      sectionsSpace: 3,
                                      centerSpaceRadius: 50,
                                      sections: [
                                        PieChartSectionData(
                                            value: _completedTasks.toDouble(),
                                            color: Colors.green,
                                            title: '$_completedTasks',
                                            radius: 40,
                                            titleStyle: const TextStyle(
                                                fontSize: 13,
                                                fontWeight: FontWeight.bold,
                                                color: Colors.white)),
                                        PieChartSectionData(
                                            value: _pendingTasks.toDouble(),
                                            color: Colors.orange,
                                            title: '$_pendingTasks',
                                            radius: 40,
                                            titleStyle: const TextStyle(
                                                fontSize: 13,
                                                fontWeight: FontWeight.bold,
                                                color: Colors.white)),
                                      ],
                                    )),
                                  ),
                                  Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      _legend(Colors.green,
                                          'Completed ($_completedTasks)'),
                                      const SizedBox(height: 12),
                                      _legend(Colors.orange,
                                          'Pending ($_pendingTasks)'),
                                      const SizedBox(height: 16),
                                      Text(
                                        _totalTasks > 0
                                            ? '${((_completedTasks / _totalTasks) * 100).toStringAsFixed(0)}%\nDone'
                                            : '0%',
                                        textAlign: TextAlign.center,
                                        style: TextStyle(
                                            fontSize: 20,
                                            fontWeight: FontWeight.bold,
                                            color: _t.textPrimary),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(width: 16),
                                ]),
                              )),
                    const SizedBox(height: 28),
                    _sectionTitle('Tasks This Week'),
                    const SizedBox(height: 16),
                    _neuCard(
                        child: SizedBox(
                      height: 200,
                      child: _weeklyCompleted.every((v) => v == 0)
                          ? _emptyState('No completed tasks this week!')
                          : BarChart(BarChartData(
                              alignment: BarChartAlignment.spaceAround,
                              maxY: (_weeklyCompleted
                                          .reduce((a, b) => a > b ? a : b) +
                                      1)
                                  .toDouble(),
                              barTouchData: BarTouchData(enabled: true),
                              titlesData: FlTitlesData(
                                leftTitles: AxisTitles(
                                    sideTitles: SideTitles(
                                        showTitles: true,
                                        reservedSize: 28,
                                        getTitlesWidget: (v, _) => Text(
                                            v.toInt().toString(),
                                            style: TextStyle(
                                                fontSize: 10,
                                                color: _t.textSecondary)))),
                                bottomTitles: AxisTitles(
                                    sideTitles: SideTitles(
                                        showTitles: true,
                                        getTitlesWidget: (v, _) {
                                          const days = [
                                            'Mon',
                                            'Tue',
                                            'Wed',
                                            'Thu',
                                            'Fri',
                                            'Sat',
                                            'Sun'
                                          ];
                                          final day = DateTime.now().subtract(
                                              Duration(days: 6 - v.toInt()));
                                          return Text(days[day.weekday - 1],
                                              style: TextStyle(
                                                  fontSize: 10,
                                                  color: _t.textSecondary));
                                        })),
                                rightTitles: const AxisTitles(
                                    sideTitles: SideTitles(showTitles: false)),
                                topTitles: const AxisTitles(
                                    sideTitles: SideTitles(showTitles: false)),
                              ),
                              gridData: FlGridData(
                                  show: true,
                                  getDrawingHorizontalLine: (v) => FlLine(
                                      color: _t.textSecondary
                                          .withValues(alpha: 0.1),
                                      strokeWidth: 1)),
                              borderData: FlBorderData(show: false),
                              barGroups: List.generate(
                                  7,
                                  (i) => BarChartGroupData(x: i, barRods: [
                                        BarChartRodData(
                                          toY: _weeklyCompleted[i].toDouble(),
                                          color: const Color(0xFF7C4DFF),
                                          width: 18,
                                          borderRadius:
                                              BorderRadius.circular(6),
                                          backDrawRodData:
                                              BackgroundBarChartRodData(
                                            show: true,
                                            toY: (_weeklyCompleted.reduce(
                                                        (a, b) =>
                                                            a > b ? a : b) +
                                                    1)
                                                .toDouble(),
                                            color: const Color(0xFF7C4DFF)
                                                .withValues(alpha: 0.08),
                                          ),
                                        ),
                                      ])),
                            )),
                    )),
                    const SizedBox(height: 28),
                    _sectionTitle('Notes by Subject'),
                    const SizedBox(height: 16),
                    _neuCard(
                        child: _subjectNotes.isEmpty
                            ? _emptyState('No notes yet!')
                            : Column(
                                children: _subjectNotes.entries.map((e) {
                                final pct = _totalNotes > 0
                                    ? e.value / _totalNotes
                                    : 0.0;
                                return Padding(
                                  padding: const EdgeInsets.only(bottom: 14),
                                  child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Row(
                                            mainAxisAlignment:
                                                MainAxisAlignment.spaceBetween,
                                            children: [
                                              Text(e.key,
                                                  style: TextStyle(
                                                      color: _t.textPrimary,
                                                      fontWeight:
                                                          FontWeight.w600)),
                                              Text('${e.value} notes',
                                                  style: TextStyle(
                                                      color: _t.textSecondary,
                                                      fontSize: 12)),
                                            ]),
                                        const SizedBox(height: 6),
                                        ClipRRect(
                                          borderRadius:
                                              BorderRadius.circular(8),
                                          child: LinearProgressIndicator(
                                            value: pct,
                                            minHeight: 10,
                                            backgroundColor:
                                                const Color(0xFF7C4DFF)
                                                    .withValues(alpha: 0.1),
                                            valueColor:
                                                const AlwaysStoppedAnimation<
                                                    Color>(Color(0xFF7C4DFF)),
                                          ),
                                        ),
                                      ]),
                                );
                              }).toList())),
                    const SizedBox(height: 28),
                  ],
                ),
              ),
            ),
    );
  }

  Widget _sectionTitle(String text) => Text(text,
      style: TextStyle(
          fontSize: 17, fontWeight: FontWeight.bold, color: _t.textPrimary));

  Widget _statCard(String label, String value, IconData icon, Color color) =>
      Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: _t.cardColor,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
                color: _t.shadowDark,
                offset: const Offset(4, 4),
                blurRadius: 10),
            BoxShadow(
                color: _t.shadowLight,
                offset: const Offset(-4, -4),
                blurRadius: 10),
          ],
        ),
        child: Row(children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
                color: color.withValues(alpha: 0.15), shape: BoxShape.circle),
            child: Icon(icon, color: color, size: 22),
          ),
          const SizedBox(width: 12),
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(value,
                style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                    color: _t.textPrimary)),
            Text(label,
                style: TextStyle(fontSize: 12, color: _t.textSecondary)),
          ]),
        ]),
      );

  Widget _neuCard({required Widget child}) => Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: _t.cardColor,
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
                color: _t.shadowDark,
                offset: const Offset(5, 5),
                blurRadius: 12),
            BoxShadow(
                color: _t.shadowLight,
                offset: const Offset(-5, -5),
                blurRadius: 12),
          ],
        ),
        child: child,
      );

  Widget _legend(Color color, String label) => Row(children: [
        Container(
            width: 12,
            height: 12,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
        const SizedBox(width: 8),
        Text(label, style: TextStyle(color: _t.textSecondary, fontSize: 13)),
      ]);

  Widget _emptyState(String msg) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 20),
        child: Center(
            child: Text(msg,
                style: TextStyle(color: _t.textSecondary, fontSize: 14))),
      );
}
