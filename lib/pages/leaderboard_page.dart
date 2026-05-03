import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter/services.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../Services/theme_provider.dart';

class LeaderboardPage extends StatefulWidget {
  const LeaderboardPage({super.key});

  @override
  State<LeaderboardPage> createState() => _LeaderboardPageState();
}

class _LeaderboardPageState extends State<LeaderboardPage>
    with TickerProviderStateMixin {
  ThemeProvider get _t => Provider.of<ThemeProvider>(context, listen: false);
  late TabController _tabController;
  late AnimationController _fadeController;
  late Animation<double> _fadeAnim;

  bool _isLoading = true;
  bool _isJoining = false;
  bool _hasGroup = false;

  String _groupId = '';
  String _groupName = '';
  String _inviteCode = '';
  List<Map<String, dynamic>> _members = [];

  final TextEditingController _codeController = TextEditingController();
  final TextEditingController _groupNameController = TextEditingController();

  int _selectedRanking = 0;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 5, vsync: this);
    _tabController.addListener(() {
      setState(() => _selectedRanking = _tabController.index);
    });
    _fadeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    )..forward();
    _fadeAnim = CurvedAnimation(parent: _fadeController, curve: Curves.easeOut);
    _checkUserGroup();
  }

  @override
  void dispose() {
    _tabController.dispose();
    _fadeController.dispose();
    _codeController.dispose();
    _groupNameController.dispose();
    super.dispose();
  }

  String get _uid => FirebaseAuth.instance.currentUser!.uid;

  DocumentReference get _userDoc =>
      FirebaseFirestore.instance.collection('users').doc(_uid);

  Future<void> _checkUserGroup() async {
    try {
      final userSnap = await _userDoc.get();
      final userData = userSnap.data() as Map<String, dynamic>? ?? {};
      final groupId = userData['leaderboardGroupId'] ?? '';

      if (groupId.isNotEmpty) {
        await _loadGroup(groupId);
      } else {
        setState(() {
          _hasGroup = false;
          _isLoading = false;
        });
      }
    } catch (e) {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _loadGroup(String groupId) async {
    try {
      final groupSnap = await FirebaseFirestore.instance
          .collection('leaderboardGroups')
          .doc(groupId)
          .get();

      if (!groupSnap.exists) {
        // Group deleted, remove from user
        await _userDoc.update({'leaderboardGroupId': ''});
        setState(() {
          _hasGroup = false;
          _isLoading = false;
        });
        return;
      }

      final groupData = groupSnap.data() ?? {};
      final memberIds = List<String>.from(groupData['members'] ?? []);

      // Load all members data
      List<Map<String, dynamic>> members = [];
      for (final uid in memberIds) {
        final memberSnap =
            await FirebaseFirestore.instance.collection('users').doc(uid).get();
        if (memberSnap.exists) {
          final data = memberSnap.data() as Map<String, dynamic>;

          // Get notes count
          final notesSnap = await FirebaseFirestore.instance
              .collection('users')
              .doc(uid)
              .collection('notes')
              .get();

          // Get tasks count
          final tasksSnap = await FirebaseFirestore.instance
              .collection('users')
              .doc(uid)
              .collection('tasks')
              .get();
          final completedTasks =
              tasksSnap.docs.where((d) => d['completed'] == true).length;

          final streak = data['studyStreakDays'] ?? 0;
          final totalDays = data['totalStudyDays'] ?? 0;
          final goalHours = (data['todayGoalHours'] ?? 3).toDouble();
          final studyHours = totalDays * goalHours;
          final totalNotes = notesSnap.docs.length;
          final totalTasks = tasksSnap.docs.length;

          // Overall score
          int score = 0;
          if (totalTasks > 0) {
            score += ((completedTasks / totalTasks) * 30).round();
          }
          final int streakInt = (streak as num).toInt();
          final int notesInt = totalNotes;
          final int daysInt = (totalDays as num).toInt();
          int streakPts = streakInt * 2;
          if (streakPts > 30) streakPts = 30;
          int notesPts = notesInt * 2;
          if (notesPts > 20) notesPts = 20;
          int daysPts = daysInt * 2;
          if (daysPts > 20) daysPts = 20;
          score += streakPts;
          score += notesPts;
          score += daysPts;

          members.add({
            'uid': uid,
            'username': data['username'] ?? 'Student',
            'email': data['email'] ?? '',
            'streak': streak,
            'notes': totalNotes,
            'tasks': completedTasks,
            'hours': studyHours,
            'score': score.clamp(0, 100).toInt(),
            'isMe': uid == _uid,
          });
        }
      }

      setState(() {
        _groupId = groupId;
        _groupName = groupData['name'] ?? 'My Group';
        _inviteCode = groupData['inviteCode'] ?? '';
        _members = members;
        _hasGroup = true;
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _createGroup() async {
    if (_groupNameController.text.trim().isEmpty) return;
    setState(() => _isJoining = true);

    try {
      // Generate 6-char invite code
      final code = _generateCode();
      final groupRef =
          FirebaseFirestore.instance.collection('leaderboardGroups').doc();

      await groupRef.set({
        'name': _groupNameController.text.trim(),
        'inviteCode': code,
        'createdBy': _uid,
        'members': [_uid],
        'createdAt': Timestamp.now(),
      });

      await _userDoc.update({'leaderboardGroupId': groupRef.id});
      await _loadGroup(groupRef.id);
    } catch (e) {
      _showSnackBar('Error creating group: $e', isError: true);
    }
    setState(() => _isJoining = false);
  }

  Future<void> _joinGroup() async {
    final code = _codeController.text.trim().toUpperCase();
    if (code.isEmpty) return;
    setState(() => _isJoining = true);

    try {
      final snap = await FirebaseFirestore.instance
          .collection('leaderboardGroups')
          .where('inviteCode', isEqualTo: code)
          .limit(1)
          .get();

      if (snap.docs.isEmpty) {
        _showSnackBar('Invalid invite code!', isError: true);
        setState(() => _isJoining = false);
        return;
      }

      final groupDoc = snap.docs.first;
      final groupId = groupDoc.id;

      await groupDoc.reference.update({
        'members': FieldValue.arrayUnion([_uid]),
      });

      await _userDoc.update({'leaderboardGroupId': groupId});
      await _loadGroup(groupId);
    } catch (e) {
      _showSnackBar('Error joining group: $e', isError: true);
    }
    setState(() => _isJoining = false);
  }

  Future<void> _leaveGroup() async {
    final confirm = await _showConfirmDialog(
      'Leave Group?',
      'You will leave "$_groupName". You can rejoin with the invite code.',
    );
    if (!confirm) return;

    try {
      await FirebaseFirestore.instance
          .collection('leaderboardGroups')
          .doc(_groupId)
          .update({
        'members': FieldValue.arrayRemove([_uid]),
      });
      await _userDoc.update({'leaderboardGroupId': ''});
      setState(() {
        _hasGroup = false;
        _members = [];
        _groupId = '';
        _groupName = '';
        _inviteCode = '';
      });
    } catch (e) {
      _showSnackBar('Error leaving group: $e', isError: true);
    }
  }

  String _generateCode() {
    const chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';
    final now = DateTime.now().millisecondsSinceEpoch;
    String code = '';
    for (int i = 0; i < 6; i++) {
      code += chars[(now + i * 7) % chars.length];
    }
    return code;
  }

  List<Map<String, dynamic>> _getSortedMembers() {
    final sorted = List<Map<String, dynamic>>.from(_members);
    switch (_selectedRanking) {
      case 0:
        sorted.sort((a, b) => (b['score'] as int).compareTo(a['score'] as int));
        break;
      case 1:
        sorted
            .sort((a, b) => (b['streak'] as int).compareTo(a['streak'] as int));
        break;
      case 2:
        sorted.sort((a, b) => (b['notes'] as int).compareTo(a['notes'] as int));
        break;
      case 3:
        sorted.sort((a, b) => (b['tasks'] as int).compareTo(a['tasks'] as int));
        break;
      case 4:
        sorted.sort(
            (a, b) => (b['hours'] as double).compareTo(a['hours'] as double));
        break;
    }
    return sorted;
  }

  String _getRankingValue(Map<String, dynamic> member) {
    switch (_selectedRanking) {
      case 0:
        return '${member['score']} pts';
      case 1:
        return '${member['streak']} days';
      case 2:
        return '${member['notes']} notes';
      case 3:
        return '${member['tasks']} tasks';
      case 4:
        return '${(member['hours'] as double).toStringAsFixed(1)}h';
      default:
        return '';
    }
  }

  void _showSnackBar(String msg, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor:
            isError ? Colors.red.shade400 : const Color(0xFF7C4DFF),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }

  Future<bool> _showConfirmDialog(String title, String content) async {
    return await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            backgroundColor: _t.bgColor,
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            title: Text(title,
                style: TextStyle(
                    color: _t.textPrimary, fontWeight: FontWeight.bold)),
            content: Text(content,
                style: TextStyle(
                    color: _t.textPrimary.withValues(alpha: 0.7),
                    fontSize: 14)),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: Text('Cancel',
                    style: TextStyle(
                        color: _t.textPrimary.withValues(alpha: 0.6))),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.red.shade400,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                ),
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Confirm',
                    style: TextStyle(color: Colors.white)),
              ),
            ],
          ),
        ) ??
        false;
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
        title: const Text('Leaderboard',
            style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 18)),
        iconTheme: const IconThemeData(color: Colors.white),
        actions: [
          if (_hasGroup) ...[
            IconButton(
              icon: const Icon(Icons.refresh, color: Colors.white),
              onPressed: () {
                setState(() => _isLoading = true);
                _loadGroup(_groupId);
              },
            ),
            IconButton(
              icon: const Icon(Icons.exit_to_app, color: Colors.white),
              tooltip: 'Leave Group',
              onPressed: _leaveGroup,
            ),
          ],
        ],
      ),
      body: _isLoading
          ? const Center(
              child: CircularProgressIndicator(color: Color(0xFF7C4DFF)))
          : FadeTransition(
              opacity: _fadeAnim,
              child: _hasGroup
                  ? _buildLeaderboard(isDark, textColor)
                  : _buildJoinScreen(isDark, textColor),
            ),
    );
  }

  // ── Join / Create Screen ──────────────────────────────────────────
  Widget _buildJoinScreen(bool isDark, Color textColor) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        children: [
          const SizedBox(height: 20),
          // Trophy illustration
          Container(
            width: 120,
            height: 120,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFF6A1B9A), Color(0xFF9C27B0)],
              ),
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                    color: const Color(0xFF7C4DFF).withValues(alpha: 0.4),
                    blurRadius: 20,
                    offset: const Offset(0, 8)),
              ],
            ),
            child: const Center(
              child: Icon(Icons.emoji_events_rounded,
                  color: Colors.white, size: 56),
            ),
          ),
          const SizedBox(height: 20),
          Text('Join a Leaderboard',
              style: TextStyle(
                  color: textColor, fontSize: 24, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          Text('Compete with friends and track your progress together!',
              style: TextStyle(
                  color: textColor.withValues(alpha: 0.5), fontSize: 14),
              textAlign: TextAlign.center),
          const SizedBox(height: 32),

          // Join with code
          _buildNeuCard(
            isDark: isDark,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.login, color: Color(0xFF7C4DFF), size: 20),
                    const SizedBox(width: 8),
                    Text('Join with Invite Code',
                        style: TextStyle(
                            color: textColor,
                            fontSize: 16,
                            fontWeight: FontWeight.bold)),
                  ],
                ),
                const SizedBox(height: 14),
                TextField(
                  controller: _codeController,
                  textCapitalization: TextCapitalization.characters,
                  style: TextStyle(
                      color: textColor,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 4),
                  decoration: InputDecoration(
                    hintText: 'XXXXXX',
                    hintStyle: TextStyle(
                        color: textColor.withValues(alpha: 0.3),
                        letterSpacing: 4),
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12)),
                    enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(
                            color: Colors.grey.withValues(alpha: 0.3))),
                    focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: const BorderSide(color: Color(0xFF7C4DFF))),
                    filled: true,
                    fillColor: isDark
                        ? Colors.white.withValues(alpha: 0.05)
                        : Colors.white.withValues(alpha: 0.7),
                    prefixIcon: const Icon(Icons.vpn_key_outlined,
                        color: Color(0xFF7C4DFF)),
                  ),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: _buildGradientButton(
                    label: _isJoining ? 'Joining...' : 'Join Group',
                    icon: Icons.group_add,
                    onTap: _isJoining ? null : _joinGroup,
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 16),

          Row(
            children: [
              Expanded(child: Divider(color: textColor.withValues(alpha: 0.2))),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Text('OR',
                    style: TextStyle(
                        color: textColor.withValues(alpha: 0.4),
                        fontWeight: FontWeight.bold)),
              ),
              Expanded(child: Divider(color: textColor.withValues(alpha: 0.2))),
            ],
          ),

          const SizedBox(height: 16),

          // Create group
          _buildNeuCard(
            isDark: isDark,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.add_circle_outline,
                        color: Colors.teal, size: 20),
                    const SizedBox(width: 8),
                    Text('Create New Group',
                        style: TextStyle(
                            color: textColor,
                            fontSize: 16,
                            fontWeight: FontWeight.bold)),
                  ],
                ),
                const SizedBox(height: 14),
                TextField(
                  controller: _groupNameController,
                  style: TextStyle(color: textColor),
                  decoration: InputDecoration(
                    hintText: 'Group name (e.g. Class 10-A)',
                    hintStyle:
                        TextStyle(color: textColor.withValues(alpha: 0.3)),
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12)),
                    enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(
                            color: Colors.grey.withValues(alpha: 0.3))),
                    focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: const BorderSide(color: Colors.teal)),
                    filled: true,
                    fillColor: isDark
                        ? Colors.white.withValues(alpha: 0.05)
                        : Colors.white.withValues(alpha: 0.7),
                    prefixIcon: const Icon(Icons.group, color: Colors.teal),
                  ),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: _buildGradientButton(
                    label: _isJoining ? 'Creating...' : 'Create Group',
                    icon: Icons.add,
                    onTap: _isJoining ? null : _createGroup,
                    colors: [Colors.teal.shade600, Colors.teal],
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

  // ── Leaderboard Screen ────────────────────────────────────────────
  Widget _buildLeaderboard(bool isDark, Color textColor) {
    final sorted = _getSortedMembers();
    final myRank = sorted.indexWhere((m) => m['uid'] == _uid) + 1;

    return Column(
      children: [
        // Group info header
        Container(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          child: _buildNeuCard(
            isDark: isDark,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                        colors: [Color(0xFF6A1B9A), Color(0xFF9C27B0)]),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.group, color: Colors.white, size: 18),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(_groupName,
                          style: TextStyle(
                              color: textColor,
                              fontWeight: FontWeight.bold,
                              fontSize: 15)),
                      Text('${sorted.length} members • Your rank: #$myRank',
                          style: TextStyle(
                              color: textColor.withValues(alpha: 0.5),
                              fontSize: 12)),
                    ],
                  ),
                ),
                // Invite code
                GestureDetector(
                  onTap: () {
                    Clipboard.setData(ClipboardData(text: _inviteCode));
                    _showSnackBar('Invite code copied! 📋');
                  },
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: const Color(0xFF7C4DFF).withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                          color:
                              const Color(0xFF7C4DFF).withValues(alpha: 0.3)),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(_inviteCode,
                            style: const TextStyle(
                                color: Color(0xFF7C4DFF),
                                fontWeight: FontWeight.bold,
                                fontSize: 13,
                                letterSpacing: 2)),
                        const SizedBox(width: 4),
                        const Icon(Icons.copy,
                            color: Color(0xFF7C4DFF), size: 14),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),

        // Tab bar for ranking type
        Container(
          margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          decoration: BoxDecoration(
            color: isDark
                ? Colors.white.withValues(alpha: 0.05)
                : Colors.black.withValues(alpha: 0.05),
            borderRadius: BorderRadius.circular(12),
          ),
          child: TabBar(
            controller: _tabController,
            labelColor: Colors.white,
            unselectedLabelColor: textColor.withValues(alpha: 0.5),
            indicator: BoxDecoration(
              gradient: const LinearGradient(
                  colors: [Color(0xFF6A1B9A), Color(0xFF9C27B0)]),
              borderRadius: BorderRadius.circular(10),
            ),
            indicatorSize: TabBarIndicatorSize.tab,
            dividerColor: Colors.transparent,
            tabs: const [
              Tab(icon: Icon(Icons.emoji_events_rounded, size: 18)),
              Tab(icon: Icon(Icons.local_fire_department, size: 18)),
              Tab(icon: Icon(Icons.note_alt_outlined, size: 18)),
              Tab(icon: Icon(Icons.task_alt, size: 18)),
              Tab(icon: Icon(Icons.timer_outlined, size: 18)),
            ],
          ),
        ),

        // Ranking label
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
          child: Row(
            children: [
              Text(
                [
                  'Overall Score',
                  'Study Streak',
                  'Notes Count',
                  'Tasks Done',
                  'Study Hours'
                ][_selectedRanking],
                style: TextStyle(
                    color: textColor.withValues(alpha: 0.5),
                    fontSize: 12,
                    fontWeight: FontWeight.w600),
              ),
            ],
          ),
        ),

        // Top 3 podium
        if (sorted.length >= 3) _buildPodium(sorted, isDark, textColor),

        // Full list
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
            itemCount: sorted.length,
            itemBuilder: (ctx, i) =>
                _buildRankCard(sorted[i], i + 1, isDark, textColor),
          ),
        ),
      ],
    );
  }

  Widget _buildPodium(
      List<Map<String, dynamic>> sorted, bool isDark, Color textColor) {
    final first = sorted[0];
    final second = sorted[1];
    final third = sorted.length > 2 ? sorted[2] : null;

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      padding: const EdgeInsets.symmetric(vertical: 16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: isDark
              ? [
                  const Color(0xFF6A1B9A).withValues(alpha: 0.2),
                  const Color(0xFF9C27B0).withValues(alpha: 0.1),
                ]
              : [
                  const Color(0xFF6A1B9A).withValues(alpha: 0.08),
                  const Color(0xFF9C27B0).withValues(alpha: 0.04),
                ],
        ),
        borderRadius: BorderRadius.circular(20),
        border:
            Border.all(color: const Color(0xFF7C4DFF).withValues(alpha: 0.2)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          // 2nd place
          _buildPodiumItem(second, 2, 70, Colors.grey.shade400, textColor),
          // 1st place
          _buildPodiumItem(first, 1, 90, Colors.amber, textColor),
          // 3rd place
          if (third != null)
            _buildPodiumItem(third, 3, 55, Colors.brown.shade300, textColor),
        ],
      ),
    );
  }

  Widget _buildPodiumItem(Map<String, dynamic> member, int rank, double height,
      Color medalColor, Color textColor) {
    final isMe = member['isMe'] as bool;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (isMe)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: const Color(0xFF7C4DFF),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Text('You',
                style: TextStyle(
                    color: Colors.white,
                    fontSize: 9,
                    fontWeight: FontWeight.bold)),
          ),
        const SizedBox(height: 4),
        // Avatar
        Container(
          width: rank == 1 ? 56 : 46,
          height: rank == 1 ? 56 : 46,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: LinearGradient(
              colors: isMe
                  ? [const Color(0xFF6A1B9A), const Color(0xFF9C27B0)]
                  : [medalColor.withValues(alpha: 0.6), medalColor],
            ),
            boxShadow: [
              BoxShadow(
                  color: medalColor.withValues(alpha: 0.4),
                  blurRadius: 8,
                  offset: const Offset(0, 3)),
            ],
          ),
          child: Center(
            child: Text(
              (member['username'] as String).substring(0, 1).toUpperCase(),
              style: TextStyle(
                  color: Colors.white,
                  fontSize: rank == 1 ? 22 : 18,
                  fontWeight: FontWeight.bold),
            ),
          ),
        ),
        const SizedBox(height: 4),
        Icon(
          rank == 1
              ? Icons.workspace_premium_rounded
              : rank == 2
                  ? Icons.military_tech_rounded
                  : Icons.emoji_events_outlined,
          color: medalColor,
          size: 20,
        ),
        Text(
          (member['username'] as String).length > 8
              ? '${(member['username'] as String).substring(0, 8)}...'
              : member['username'] as String,
          style: TextStyle(
              color: textColor, fontSize: 11, fontWeight: FontWeight.w600),
        ),
        Text(
          _getRankingValue(member),
          style: TextStyle(
              color: medalColor, fontSize: 11, fontWeight: FontWeight.bold),
        ),
      ],
    );
  }

  Widget _buildRankCard(
      Map<String, dynamic> member, int rank, bool isDark, Color textColor) {
    final isMe = member['isMe'] as bool;
    final rankColors = {1: Colors.amber, 2: Colors.grey, 3: Colors.brown};
    final rankColor = rankColors[rank] ?? textColor.withValues(alpha: 0.4);

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color:
            isMe ? const Color(0xFF7C4DFF).withValues(alpha: 0.08) : _t.bgColor,
        borderRadius: BorderRadius.circular(16),
        border: isMe
            ? Border.all(color: const Color(0xFF7C4DFF).withValues(alpha: 0.3))
            : null,
        boxShadow: isDark
            ? [
                BoxShadow(
                    color: Colors.black.withValues(alpha: 0.3),
                    offset: const Offset(4, 4),
                    blurRadius: 8),
                BoxShadow(
                    color: Colors.white.withValues(alpha: 0.04),
                    offset: const Offset(-4, -4),
                    blurRadius: 8),
              ]
            : [
                BoxShadow(
                    color: Colors.grey.withValues(alpha: 0.25),
                    offset: const Offset(4, 4),
                    blurRadius: 8),
                BoxShadow(
                    color: Colors.white.withValues(alpha: 0.9),
                    offset: const Offset(-4, -4),
                    blurRadius: 8),
              ],
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        leading: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 28,
              child: Text(
                rank <= 3 ? '' : '#$rank',
                style: TextStyle(
                    color: rankColor,
                    fontSize: rank <= 3 ? 18 : 13,
                    fontWeight: FontWeight.bold),
                textAlign: TextAlign.center,
              ),
            ),
            const SizedBox(width: 8),
            // Avatar circle
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: LinearGradient(
                  colors: isMe
                      ? [const Color(0xFF6A1B9A), const Color(0xFF9C27B0)]
                      : [
                          Colors.grey.withValues(alpha: 0.4),
                          Colors.grey.withValues(alpha: 0.6),
                        ],
                ),
              ),
              child: Center(
                child: Text(
                  (member['username'] as String).substring(0, 1).toUpperCase(),
                  style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 16),
                ),
              ),
            ),
          ],
        ),
        title: Row(
          children: [
            Text(
              member['username'] as String,
              style: TextStyle(
                  color: textColor, fontWeight: FontWeight.w600, fontSize: 14),
            ),
            if (isMe) ...[
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: const Color(0xFF7C4DFF),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Text('You',
                    style: TextStyle(
                        color: Colors.white,
                        fontSize: 9,
                        fontWeight: FontWeight.bold)),
              ),
            ],
          ],
        ),
        subtitle: Text(
          '${member['streak']}d streak  ${member['notes']} notes  ${member['tasks']} tasks',
          style:
              TextStyle(color: textColor.withValues(alpha: 0.45), fontSize: 11),
        ),
        trailing: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            gradient: rank <= 3
                ? LinearGradient(
                    colors: [rankColor.withValues(alpha: 0.6), rankColor])
                : const LinearGradient(
                    colors: [Color(0xFF6A1B9A), Color(0xFF9C27B0)]),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Text(
            _getRankingValue(member),
            style: const TextStyle(
                color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12),
          ),
        ),
      ),
    );
  }

  Widget _buildGradientButton({
    required String label,
    required IconData icon,
    required VoidCallback? onTap,
    List<Color> colors = const [Color(0xFF6A1B9A), Color(0xFF9C27B0)],
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(
          gradient: LinearGradient(colors: colors),
          borderRadius: BorderRadius.circular(14),
          boxShadow: [
            BoxShadow(
                color: colors.last.withValues(alpha: 0.4),
                offset: const Offset(0, 4),
                blurRadius: 12),
          ],
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: Colors.white, size: 18),
            const SizedBox(width: 8),
            Text(label,
                style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 15)),
          ],
        ),
      ),
    );
  }

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
