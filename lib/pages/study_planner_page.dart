// lib/pages/study_planner_page.dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'dart:convert';
import '../Services/auth_service.dart';
import '../Services/theme_provider.dart';
import '../Services/streak_service.dart';
import '../Services/ai_service.dart';

class StudyPlannerPage extends StatefulWidget {
  const StudyPlannerPage({super.key});

  @override
  State<StudyPlannerPage> createState() => _StudyPlannerPageState();
}

class _StudyPlannerPageState extends State<StudyPlannerPage>
    with SingleTickerProviderStateMixin {
  final _auth = AuthService();
  final _firestore = FirebaseFirestore.instance;
  late TabController _tabController;

  final _subjectCtrl = TextEditingController();
  String _selectedPriority = 'Medium';
  DateTime _selectedDate = DateTime.now();
  TimeOfDay _selectedTime = TimeOfDay.now();

  final _goalCtrl = TextEditingController();
  final _topicsCtrl = TextEditingController();
  final _hoursCtrl = TextEditingController();
  DateTime? _deadline;
  bool _isGenerating = false;
  String _aiStatus = '';

  ThemeProvider get _t => Provider.of<ThemeProvider>(context, listen: false);

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _tabController.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _tabController.dispose();
    _subjectCtrl.dispose();
    _goalCtrl.dispose();
    _topicsCtrl.dispose();
    _hoursCtrl.dispose();
    super.dispose();
  }

  CollectionReference get _tasks => _firestore
      .collection('users')
      .doc(_auth.currentUser!.uid)
      .collection('tasks');

  Future<void> _showAddTaskDialog() async {
    _subjectCtrl.clear();
    _selectedPriority = 'Medium';
    _selectedDate = DateTime.now();
    _selectedTime = TimeOfDay.now();

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) => AlertDialog(
          backgroundColor: _t.cardColor,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: Text('Add Task',
              style: TextStyle(
                  color: _t.textPrimary, fontWeight: FontWeight.bold)),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(
                  controller: _subjectCtrl,
                  style: TextStyle(color: _t.textPrimary),
                  decoration: InputDecoration(
                    labelText: 'Subject / Task',
                    labelStyle: TextStyle(color: _t.textSecondary),
                    prefixIcon:
                        Icon(Icons.book_outlined, color: _t.accentColor),
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12)),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: _t.accentColor, width: 2),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Text('Priority',
                    style: TextStyle(color: _t.textSecondary, fontSize: 13)),
                const SizedBox(height: 8),
                Row(
                  children: ['Low', 'Medium', 'High'].map((p) {
                    final sel = _selectedPriority == p;
                    return Expanded(
                      child: Padding(
                        padding: const EdgeInsets.only(right: 6),
                        child: ChoiceChip(
                          label: Text(p),
                          selected: sel,
                          onSelected: (_) => setS(() => _selectedPriority = p),
                          selectedColor: _priorityColor(p),
                          showCheckmark: false,
                          labelStyle: TextStyle(
                            color: sel ? Colors.white : _t.textPrimary,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    );
                  }).toList(),
                ),
                const SizedBox(height: 16),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.calendar_today, color: _t.accentColor),
                  title: Text(
                    '${_selectedDate.day}/${_selectedDate.month}/${_selectedDate.year}',
                    style: TextStyle(color: _t.textPrimary),
                  ),
                  subtitle: Text('Tap to change date',
                      style: TextStyle(color: _t.textSecondary, fontSize: 11)),
                  onTap: () async {
                    final d = await showDatePicker(
                      context: ctx,
                      initialDate: _selectedDate,
                      firstDate: DateTime.now(),
                      lastDate: DateTime.now().add(const Duration(days: 365)),
                    );
                    if (d != null) setS(() => _selectedDate = d);
                  },
                ),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.access_time, color: _t.accentColor),
                  title: Text(_selectedTime.format(context),
                      style: TextStyle(color: _t.textPrimary)),
                  subtitle: Text('Tap to change time',
                      style: TextStyle(color: _t.textSecondary, fontSize: 11)),
                  onTap: () async {
                    final t = await showTimePicker(
                      context: ctx,
                      initialTime: _selectedTime,
                    );
                    if (t != null) setS(() => _selectedTime = t);
                  },
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text('Cancel', style: TextStyle(color: _t.textSecondary)),
            ),
            ElevatedButton(
              onPressed: () async {
                if (_subjectCtrl.text.trim().isEmpty) return;
                await _addTask();
                if (ctx.mounted) Navigator.pop(ctx);
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: _t.accentColor,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10)),
              ),
              child: const Text('Add'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _addTask() async {
    final dueDateTime = DateTime(
      _selectedDate.year,
      _selectedDate.month,
      _selectedDate.day,
      _selectedTime.hour,
      _selectedTime.minute,
    );
    await _tasks.add({
      'subject': _subjectCtrl.text.trim(),
      'priority': _selectedPriority,
      'dueDate': Timestamp.fromDate(dueDateTime),
      'completed': false,
      'createdAt': Timestamp.now(),
      'source': 'manual',
    });
  }

  Future<void> _toggleComplete(String id, bool current) async {
    await _tasks.doc(id).update({'completed': !current});
    if (!current) {
      await StreakService().onTaskCompleted();
    }
  }

  Future<void> _deleteTask(String id) async {
    await _tasks.doc(id).delete();
  }

  Future<void> _generateAIPlan() async {
    if (_goalCtrl.text.trim().isEmpty ||
        _topicsCtrl.text.trim().isEmpty ||
        _deadline == null ||
        _hoursCtrl.text.trim().isEmpty) {
      _showSnackBar('Please fill all fields!', isError: true);
      return;
    }

    setState(() {
      _isGenerating = true;
      _aiStatus = 'Generating your plan...';
    });

    try {
      final now = DateTime.now();
      final daysLeft = _deadline!.difference(now).inDays + 1;

      final prompt = '''
You are an expert study planner. Create a day-wise study schedule.
Goal: ${_goalCtrl.text.trim()}
Topics: ${_topicsCtrl.text.trim()}
Days: $daysLeft, Daily hours: ${_hoursCtrl.text.trim()}
Deadline: ${_deadline!.day}/${_deadline!.month}/${_deadline!.year}

Return ONLY valid JSON:
{"tasks":[{"day_offset":1,"subject":"specific task","priority":"High/Medium/Low","duration_hours":2}]}

Rules: specific tasks, max 3/day, distribute evenly, first=foundation last=revision, max 40 tasks total.
''';

      final content = await AiService.call(prompt, maxTokens: 3000);
      final planData = jsonDecode(content) as Map<String, dynamic>;
      final tasks = planData['tasks'] as List;

      setState(() => _aiStatus = 'Saving ${tasks.length} tasks...');

      final batch = FirebaseFirestore.instance.batch();
      for (final task in tasks) {
        final dayOffset = (task['day_offset'] as num).toInt();
        final durationHours = (task['duration_hours'] as num?)?.toInt() ?? 1;
        final taskDate = now.add(Duration(days: dayOffset));
        final dueDateTime =
            DateTime(taskDate.year, taskDate.month, taskDate.day, 9, 0);
        final docRef = _tasks.doc();
        batch.set(docRef, {
          'subject': task['subject'] ?? 'Study Task',
          'priority': task['priority'] ?? 'Medium',
          'dueDate': Timestamp.fromDate(dueDateTime),
          'completed': false,
          'createdAt': Timestamp.now(),
          'source': 'ai',
          'duration': '$durationHours hr',
        });
      }
      await batch.commit();

      _goalCtrl.clear();
      _topicsCtrl.clear();
      _hoursCtrl.clear();
      setState(() {
        _deadline = null;
        _isGenerating = false;
        _aiStatus = '';
      });
      _tabController.animateTo(0);
      _showSnackBar('${tasks.length} tasks added to your planner!');
    } catch (e) {
      setState(() {
        _isGenerating = false;
        _aiStatus = '';
      });
      _showSnackBar('Error: $e', isError: true);
    }
  }

  void _showSnackBar(String msg, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: isError ? Colors.red.shade400 : _t.accentColor,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final t = Provider.of<ThemeProvider>(context);

    return Scaffold(
      backgroundColor: t.bgColor,
      appBar: AppBar(
        title:
            const Text('Study Planner', style: TextStyle(color: Colors.white)),
        flexibleSpace: Container(
          decoration: const BoxDecoration(
            gradient:
                LinearGradient(colors: [Color(0xFF6A1B9A), Color(0xFF9C27B0)]),
          ),
        ),
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: Colors.white,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white54,
          tabs: const [
            Tab(icon: Icon(Icons.task_alt, size: 18), text: 'My Tasks'),
            Tab(
                icon: Icon(Icons.psychology_rounded, size: 18),
                text: 'AI Planner'),
          ],
        ),
      ),
      floatingActionButton: _tabController.index == 0
          ? FloatingActionButton.extended(
              onPressed: _showAddTaskDialog,
              backgroundColor: t.accentColor,
              icon: const Icon(Icons.add, color: Colors.white),
              label:
                  const Text('Add Task', style: TextStyle(color: Colors.white)),
            )
          : null,
      body: TabBarView(
        controller: _tabController,
        children: [_buildTasksTab(t), _buildAIPlannerTab(t)],
      ),
    );
  }

  Widget _buildTasksTab(ThemeProvider t) {
    return StreamBuilder<QuerySnapshot>(
      stream: _tasks.orderBy('dueDate').snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return Center(child: CircularProgressIndicator(color: t.accentColor));
        }
        final docs = snapshot.data?.docs ?? [];
        if (docs.isEmpty) return _buildEmptyState(t);
        final pending = docs.where((d) => !(d['completed'] as bool)).toList();
        final completed = docs.where((d) => (d['completed'] as bool)).toList();
        return ListView(
          padding: const EdgeInsets.all(20),
          children: [
            if (pending.isNotEmpty) ...[
              _sectionHeader('Pending (${pending.length})', t),
              const SizedBox(height: 10),
              ...pending.map((d) => _buildTaskCard(d, t)),
              const SizedBox(height: 20),
            ],
            if (completed.isNotEmpty) ...[
              _sectionHeader('Completed (${completed.length})', t),
              const SizedBox(height: 10),
              ...completed.map((d) => _buildTaskCard(d, t)),
            ],
          ],
        );
      },
    );
  }

  Widget _buildEmptyState(ThemeProvider t) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.calendar_today, size: 64, color: t.textSecondary),
          const SizedBox(height: 16),
          Text('No tasks yet!',
              style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: t.textPrimary)),
          const SizedBox(height: 8),
          Text('Add tasks manually or use AI Planner tab',
              style: TextStyle(color: t.textSecondary)),
        ],
      ),
    );
  }

  Widget _sectionHeader(String title, ThemeProvider t) => Text(title,
      style: TextStyle(
          fontSize: 15, fontWeight: FontWeight.bold, color: t.textPrimary));

  Widget _buildTaskCard(QueryDocumentSnapshot doc, ThemeProvider t) {
    final data = doc.data() as Map<String, dynamic>;
    final completed = data['completed'] as bool;
    final subject = data['subject'] as String? ?? '';
    final priority = data['priority'] as String? ?? 'Medium';
    final dueDate = (data['dueDate'] as Timestamp).toDate();
    final pColor = _priorityColor(priority);
    final isAI = (data['source'] ?? '') == 'ai';
    final duration = data['duration'] ?? '';

    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      decoration: BoxDecoration(
        color: t.cardColor,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
              color: t.shadowDark, offset: const Offset(4, 4), blurRadius: 10),
          BoxShadow(
              color: t.shadowLight,
              offset: const Offset(-4, -4),
              blurRadius: 10),
        ],
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        leading: GestureDetector(
          onTap: () => _toggleComplete(doc.id, completed),
          child: Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              color: completed ? t.accentColor : Colors.transparent,
              shape: BoxShape.circle,
              border: Border.all(
                  color: completed ? t.accentColor : t.textSecondary, width: 2),
            ),
            child: completed
                ? const Icon(Icons.check, color: Colors.white, size: 16)
                : null,
          ),
        ),
        title: Row(
          children: [
            Expanded(
              child: Text(
                subject,
                style: TextStyle(
                  color: completed ? t.textSecondary : t.textPrimary,
                  fontWeight: FontWeight.w600,
                  decoration: completed ? TextDecoration.lineThrough : null,
                ),
              ),
            ),
            if (isAI)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: t.accentColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text('AI',
                    style: TextStyle(
                        color: t.accentColor,
                        fontSize: 9,
                        fontWeight: FontWeight.bold)),
              ),
          ],
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 4),
            Row(children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: pColor.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(priority,
                    style: TextStyle(
                        fontSize: 11,
                        color: pColor,
                        fontWeight: FontWeight.bold)),
              ),
              const SizedBox(width: 8),
              Icon(Icons.access_time, size: 12, color: t.textSecondary),
              const SizedBox(width: 4),
              Text('${dueDate.day}/${dueDate.month} ${_formatTime(dueDate)}',
                  style: TextStyle(fontSize: 11, color: t.textSecondary)),
              if (duration.isNotEmpty) ...[
                const SizedBox(width: 8),
                Text('$duration',
                    style: TextStyle(fontSize: 10, color: t.textSecondary)),
              ],
            ]),
          ],
        ),
        trailing: IconButton(
          icon:
              Icon(Icons.delete_outline, color: Colors.red.shade300, size: 20),
          onPressed: () => _deleteTask(doc.id),
        ),
      ),
    );
  }

  Widget _buildAIPlannerTab(ThemeProvider t) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
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
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                            colors: [Color(0xFF6A1B9A), Color(0xFF9C27B0)]),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(Icons.psychology_rounded,
                          color: Colors.white, size: 22),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('AI Smart Planner',
                              style: TextStyle(
                                  color: t.textPrimary,
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold)),
                          Text('Tell AI your goal — get a complete schedule!',
                              style: TextStyle(
                                  color: t.textSecondary, fontSize: 12)),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                _aiLabel('Study Goal', icon: Icons.flag_outlined, t: t),
                const SizedBox(height: 8),
                _aiTextField(
                    controller: _goalCtrl,
                    hint: 'e.g. Prepare for Physics Class 12 Boards',
                    icon: Icons.flag_outlined,
                    t: t),
                const SizedBox(height: 14),
                _aiLabel('Topics to Cover',
                    icon: Icons.list_alt_outlined, t: t),
                const SizedBox(height: 8),
                _aiTextField(
                    controller: _topicsCtrl,
                    hint: 'e.g. Mechanics, Thermodynamics, Optics',
                    icon: Icons.list_alt_outlined,
                    maxLines: 3,
                    t: t),
                const SizedBox(height: 14),
                Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _aiLabel('Deadline',
                              icon: Icons.calendar_today_outlined, t: t),
                          const SizedBox(height: 8),
                          GestureDetector(
                            onTap: () async {
                              final picked = await showDatePicker(
                                context: context,
                                initialDate:
                                    DateTime.now().add(const Duration(days: 7)),
                                firstDate:
                                    DateTime.now().add(const Duration(days: 1)),
                                lastDate: DateTime.now()
                                    .add(const Duration(days: 365)),
                              );
                              if (picked != null) {
                                setState(() => _deadline = picked);
                              }
                            },
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 12, vertical: 14),
                              decoration: BoxDecoration(
                                color: t.isDark
                                    ? Colors.white.withValues(alpha: 0.05)
                                    : Colors.black.withValues(alpha: 0.04),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                    color:
                                        t.accentColor.withValues(alpha: 0.3)),
                              ),
                              child: Row(
                                children: [
                                  Icon(Icons.calendar_today,
                                      color: t.accentColor, size: 16),
                                  const SizedBox(width: 8),
                                  Text(
                                    _deadline == null
                                        ? 'Pick date'
                                        : '${_deadline!.day}/${_deadline!.month}/${_deadline!.year}',
                                    style: TextStyle(
                                        color: _deadline == null
                                            ? t.textSecondary
                                            : t.textPrimary,
                                        fontSize: 13),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _aiLabel('Daily Hours',
                              icon: Icons.timer_outlined, t: t),
                          const SizedBox(height: 8),
                          _aiTextField(
                              controller: _hoursCtrl,
                              hint: 'e.g. 3',
                              icon: Icons.timer_outlined,
                              keyboardType: TextInputType.number,
                              t: t),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                SizedBox(
                  width: double.infinity,
                  child: GestureDetector(
                    onTap: _isGenerating ? null : _generateAIPlan,
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      decoration: BoxDecoration(
                        gradient: _isGenerating
                            ? LinearGradient(colors: [
                                Colors.grey.shade400,
                                Colors.grey.shade500
                              ])
                            : const LinearGradient(
                                colors: [Color(0xFF6A1B9A), Color(0xFF9C27B0)]),
                        borderRadius: BorderRadius.circular(14),
                        boxShadow: _isGenerating
                            ? []
                            : [
                                BoxShadow(
                                    color: t.accentColor.withValues(alpha: 0.4),
                                    blurRadius: 16,
                                    offset: const Offset(0, 6)),
                              ],
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          if (_isGenerating)
                            const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                    color: Colors.white, strokeWidth: 2))
                          else
                            const Icon(Icons.psychology_rounded,
                                color: Colors.white, size: 20),
                          const SizedBox(width: 10),
                          Text(
                            _isGenerating
                                ? _aiStatus
                                : 'Generate My Study Plan',
                            style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                                fontSize: 15),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 32),
        ],
      ),
    );
  }

  Widget _aiLabel(String text, {IconData? icon, required ThemeProvider t}) =>
      Row(
        children: [
          if (icon != null) ...[
            Icon(icon, color: t.accentColor, size: 15),
            const SizedBox(width: 6),
          ],
          Text(text,
              style: TextStyle(
                  color: t.textPrimary,
                  fontSize: 13,
                  fontWeight: FontWeight.w600)),
        ],
      );

  Widget _aiTextField({
    required TextEditingController controller,
    required String hint,
    required IconData icon,
    required ThemeProvider t,
    int maxLines = 1,
    TextInputType keyboardType = TextInputType.text,
  }) =>
      TextField(
        controller: controller,
        maxLines: maxLines,
        keyboardType: keyboardType,
        style: TextStyle(color: t.textPrimary),
        decoration: InputDecoration(
          hintText: hint,
          hintStyle: TextStyle(color: t.textSecondary.withValues(alpha: 0.5)),
          prefixIcon: Icon(icon, color: t.accentColor, size: 20),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
          enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide:
                  BorderSide(color: Colors.grey.withValues(alpha: 0.3))),
          focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: t.accentColor)),
          filled: true,
          fillColor: t.isDark
              ? Colors.white.withValues(alpha: 0.05)
              : Colors.white.withValues(alpha: 0.7),
        ),
      );

  Color _priorityColor(String p) {
    switch (p) {
      case 'High':
        return Colors.red;
      case 'Medium':
        return Colors.orange;
      default:
        return Colors.green;
    }
  }

  String _formatTime(DateTime dt) {
    final h = dt.hour % 12 == 0 ? 12 : dt.hour % 12;
    final m = dt.minute.toString().padLeft(2, '0');
    final a = dt.hour < 12 ? 'AM' : 'PM';
    return '$h:$m $a';
  }
}
