import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:file_picker/file_picker.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import '../Services/theme_provider.dart';
import '../Services/streak_service.dart';
import 'note_detail_page.dart';

class NotesManagerPage extends StatefulWidget {
  const NotesManagerPage({super.key});

  @override
  State<NotesManagerPage> createState() => _NotesManagerPageState();
}

class _NotesManagerPageState extends State<NotesManagerPage>
    with SingleTickerProviderStateMixin {
  ThemeProvider get _t => Provider.of<ThemeProvider>(context, listen: false);
  final TextEditingController _searchController = TextEditingController();
  late TabController _tabController;

  String _searchQuery = '';
  bool _isUploading = false;

  // Cloudinary config
  static const String _cloudName = 'dinqwjeaw';
  static const String _uploadPreset = 'acadify_notes';
  double _uploadProgress = 0;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _searchController.dispose();
    _tabController.dispose();
    super.dispose();
  }

  String get _uid => FirebaseAuth.instance.currentUser!.uid;

  CollectionReference get _notesRef => FirebaseFirestore.instance
      .collection('users')
      .doc(_uid)
      .collection('notes');

  Future<void> _addTextNote() async {
    final isDark = _t.isDark;
    final bg = isDark ? const Color(0xFF1A1A2E) : const Color(0xFFEEEEF5);
    final textColor = isDark ? Colors.white : const Color(0xFF2D2D2D);

    final titleCtrl = TextEditingController();
    final contentCtrl = TextEditingController();
    final subjectCtrl = TextEditingController();
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: bg,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setModalState) => Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(ctx).viewInsets.bottom + 16,
            left: 20,
            right: 20,
            top: 20,
          ),
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
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
                      child: const Icon(Icons.text_snippet,
                          color: Colors.white, size: 20),
                    ),
                    const SizedBox(width: 10),
                    Text('New Text Note',
                        style: TextStyle(
                            color: textColor,
                            fontSize: 18,
                            fontWeight: FontWeight.bold)),
                  ],
                ),
                const SizedBox(height: 16),
                _buildModalField(
                    titleCtrl, 'Title *', Icons.title, textColor, bg, isDark),
                const SizedBox(height: 12),
                _buildModalField(subjectCtrl, 'Subject/Topic', Icons.subject,
                    textColor, bg, isDark),
                const SizedBox(height: 12),
                _buildModalField(
                    contentCtrl, 'Content', Icons.notes, textColor, bg, isDark,
                    maxLines: 5),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14)),
                      backgroundColor: Colors.transparent,
                      shadowColor: Colors.transparent,
                    ).copyWith(
                      backgroundColor:
                          WidgetStateProperty.all(Colors.transparent),
                    ),
                    onPressed: () async {
                      if (titleCtrl.text.trim().isEmpty) {
                        ScaffoldMessenger.of(context)
                            .showSnackBar(const SnackBar(
                          content: Text('Please enter a title!'),
                          backgroundColor: Colors.red,
                        ));
                        return;
                      }
                      await _notesRef.add({
                        'title': titleCtrl.text.trim(),
                        'content': contentCtrl.text.trim(),
                        'subject': subjectCtrl.text.trim(),
                        'category': subjectCtrl.text.trim().isEmpty
                            ? 'General'
                            : subjectCtrl.text.trim(),
                        'type': 'text',
                        'imageUrl': '',
                        'createdAt': Timestamp.now(),
                      });
                      // Add 0.25h when note is added
                      await StreakService().onNoteAdded();
                      if (ctx.mounted) Navigator.pop(ctx);
                      _showSnackBar('Text note saved!');
                    },
                    child: Ink(
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                            colors: [Color(0xFF6A1B9A), Color(0xFF9C27B0)]),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Container(
                        alignment: Alignment.center,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        child: const Text('Save Note',
                            style: TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                                fontSize: 15)),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _uploadMediaNote(String type) async {
    // Step 1: Pick file first
    final result = await FilePicker.platform.pickFiles(
      type: type == 'photo' ? FileType.image : FileType.custom,
      allowedExtensions: type == 'pdf' ? ['pdf'] : null,
      withData: true,
    );
    if (result == null || result.files.isEmpty) return;

    final file = result.files.first;
    if (file.bytes == null) {
      _showSnackBar('Could not read file!', isError: true);
      return;
    }

    // Guard: widget may have been disposed while the file picker was open.
    if (!mounted) return;

    // Step 2: Show title/subject BEFORE uploading
    final isDark = _t.isDark;
    final bg = isDark ? const Color(0xFF1A1A2E) : const Color(0xFFEEEEF5);
    final textColor = isDark ? Colors.white : const Color(0xFF2D2D2D);
    final titleCtrl = TextEditingController(
        text: file.name.replaceAll(RegExp(r'\.[^.]+$'), ''));
    final subjectCtrl = TextEditingController();
    bool confirmed = false;

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: bg,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setModalState) => Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(ctx).viewInsets.bottom + 16,
            left: 20,
            right: 20,
            top: 20,
          ),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: type == 'photo'
                            ? Colors.teal.withValues(alpha: 0.2)
                            : Colors.red.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Icon(
                        type == 'photo' ? Icons.image : Icons.picture_as_pdf,
                        color: type == 'photo' ? Colors.teal : Colors.red,
                        size: 20,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Text(
                      type == 'photo'
                          ? 'Photo Note Details'
                          : 'PDF Note Details',
                      style: TextStyle(
                          color: textColor,
                          fontSize: 18,
                          fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                _buildModalField(
                    titleCtrl, 'Title *', Icons.title, textColor, bg, isDark),
                const SizedBox(height: 12),
                _buildModalField(subjectCtrl, 'Subject/Topic', Icons.subject,
                    textColor, bg, isDark),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14)),
                      backgroundColor:
                          type == 'photo' ? Colors.teal : Colors.red.shade600,
                    ),
                    onPressed: () {
                      if (titleCtrl.text.trim().isEmpty) return;
                      confirmed = true;
                      Navigator.pop(ctx);
                    },
                    child: const Text('Upload & Save',
                        style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 15)),
                  ),
                ),
                const SizedBox(height: 8),
              ],
            ),
          ),
        ),
      ),
    );

    if (!confirmed || titleCtrl.text.trim().isEmpty) return;

    // Step 3: Upload to Cloudinary
    setState(() {
      _isUploading = true;
      _uploadProgress = 0;
    });

    try {
      final uri = Uri.parse(
          'https://api.cloudinary.com/v1_1/$_cloudName/${type == 'photo' ? 'image' : 'raw'}/upload');

      final request = http.MultipartRequest('POST', uri)
        ..fields['upload_preset'] = _uploadPreset
        ..files.add(http.MultipartFile.fromBytes(
          'file',
          file.bytes!,
          filename: file.name,
        ));

      // Send with progress tracking
      setState(() => _uploadProgress = 0.3);
      final streamedResponse = await request.send();
      setState(() => _uploadProgress = 0.8);

      final responseBody = await streamedResponse.stream.bytesToString();
      final data = json.decode(responseBody);
      setState(() => _uploadProgress = 1.0);

      if (data['secure_url'] == null) {
        throw data['error']?['message'] ?? 'Upload failed — no URL returned';
      }

      final downloadUrl = data['secure_url'] as String;

      // Step 4: Save to Firestore
      await _notesRef.add({
        'title': titleCtrl.text.trim(),
        'content': '',
        'subject': subjectCtrl.text.trim(),
        'category': subjectCtrl.text.trim().isEmpty
            ? 'General'
            : subjectCtrl.text.trim(),
        'type': type,
        'imageUrl': downloadUrl,
        'createdAt': Timestamp.now(),
      });

      await StreakService().onNoteAdded();
      _showSnackBar(type == 'photo' ? 'Photo note saved!' : 'PDF note saved!');
    } catch (e) {
      _showSnackBar('Upload failed: $e', isError: true);
    } finally {
      setState(() {
        _isUploading = false;
        _uploadProgress = 0;
      });
    }
  }

  void _showAddNoteMenu() {
    final isDark = _t.isDark;
    final bg = isDark ? const Color(0xFF1A1A2E) : const Color(0xFFEEEEF5);
    final textColor = isDark ? Colors.white : const Color(0xFF2D2D2D);

    showModalBottomSheet(
      context: context,
      backgroundColor: bg,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('What do you want to add?',
                style: TextStyle(
                    color: textColor,
                    fontSize: 18,
                    fontWeight: FontWeight.bold)),
            const SizedBox(height: 20),
            Row(
              children: [
                Expanded(
                    child: _buildAddOptionCard(
                        icon: Icons.text_snippet,
                        label: 'Text Note',
                        color: const Color(0xFF7C4DFF),
                        isDark: isDark,
                        textColor: textColor,
                        onTap: () {
                          Navigator.pop(ctx);
                          _addTextNote();
                        })),
                const SizedBox(width: 12),
                Expanded(
                    child: _buildAddOptionCard(
                        icon: Icons.image,
                        label: 'Photo Note',
                        color: Colors.teal,
                        isDark: isDark,
                        textColor: textColor,
                        onTap: () {
                          Navigator.pop(ctx);
                          _uploadMediaNote('photo');
                        })),
                const SizedBox(width: 12),
                Expanded(
                    child: _buildAddOptionCard(
                        icon: Icons.picture_as_pdf,
                        label: 'PDF Note',
                        color: Colors.red,
                        isDark: isDark,
                        textColor: textColor,
                        onTap: () {
                          Navigator.pop(ctx);
                          _uploadMediaNote('pdf');
                        })),
              ],
            ),
            const SizedBox(height: 12),
          ],
        ),
      ),
    );
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

  @override
  Widget build(BuildContext context) {
    final isDark = _t.isDark;
    final bg = isDark ? const Color(0xFF1A1A2E) : const Color(0xFFEEEEF5);
    final textColor = isDark ? Colors.white : const Color(0xFF2D2D2D);

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
          'Notes Manager',
          style: TextStyle(
              color: Colors.white, fontWeight: FontWeight.bold, fontSize: 18),
        ),
        iconTheme: const IconThemeData(color: Colors.white),
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: Colors.white,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white54,
          tabs: const [
            Tab(
                icon: Icon(Icons.text_snippet_outlined, size: 18),
                text: 'Text'),
            Tab(icon: Icon(Icons.image_outlined, size: 18), text: 'Photos'),
            Tab(
                icon: Icon(Icons.picture_as_pdf_outlined, size: 18),
                text: 'PDFs'),
          ],
        ),
      ),
      body: Column(
        children: [
          // Search + Filter
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Column(
              children: [
                // Search bar
                Container(
                  decoration: BoxDecoration(
                    color: bg,
                    borderRadius: BorderRadius.circular(14),
                    boxShadow: isDark
                        ? [
                            BoxShadow(
                                color: Colors.black.withValues(alpha: 0.4),
                                offset: const Offset(4, 4),
                                blurRadius: 8),
                            BoxShadow(
                                color: Colors.white.withValues(alpha: 0.04),
                                offset: const Offset(-4, -4),
                                blurRadius: 8),
                          ]
                        : [
                            BoxShadow(
                                color: Colors.grey.withValues(alpha: 0.3),
                                offset: const Offset(4, 4),
                                blurRadius: 8),
                            BoxShadow(
                                color: Colors.white.withValues(alpha: 0.9),
                                offset: const Offset(-4, -4),
                                blurRadius: 8),
                          ],
                  ),
                  child: TextField(
                    controller: _searchController,
                    onChanged: (val) =>
                        setState(() => _searchQuery = val.toLowerCase()),
                    style: TextStyle(color: textColor),
                    decoration: InputDecoration(
                      hintText: 'Search notes...',
                      hintStyle:
                          TextStyle(color: textColor.withValues(alpha: 0.4)),
                      prefixIcon: Icon(Icons.search,
                          color: textColor.withValues(alpha: 0.4)),
                      suffixIcon: _searchQuery.isNotEmpty
                          ? IconButton(
                              icon: Icon(Icons.clear,
                                  color: textColor.withValues(alpha: 0.4)),
                              onPressed: () {
                                _searchController.clear();
                                setState(() => _searchQuery = '');
                              },
                            )
                          : null,
                      border: InputBorder.none,
                      contentPadding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                  ),
                ),
              ],
            ),
          ),

          // Uploading indicator
          if (_isUploading)
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFF7C4DFF).withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                    color: const Color(0xFF7C4DFF).withValues(alpha: 0.3)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                              color: Color(0xFF7C4DFF), strokeWidth: 2)),
                      const SizedBox(width: 10),
                      Text(
                        'Uploading... ${(_uploadProgress * 100).toInt()}%',
                        style: const TextStyle(
                            color: Color(0xFF7C4DFF),
                            fontSize: 13,
                            fontWeight: FontWeight.w600),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: _uploadProgress,
                      minHeight: 6,
                      backgroundColor:
                          const Color(0xFF7C4DFF).withValues(alpha: 0.2),
                      valueColor: const AlwaysStoppedAnimation<Color>(
                          Color(0xFF7C4DFF)),
                    ),
                  ),
                ],
              ),
            ),

          // Tab content
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                _buildNotesList('text', isDark, textColor, bg),
                _buildNotesList('photo', isDark, textColor, bg),
                _buildNotesList('pdf', isDark, textColor, bg),
              ],
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _showAddNoteMenu,
        backgroundColor: const Color(0xFF7C4DFF),
        icon: const Icon(Icons.add, color: Colors.white),
        label: const Text('Add Note',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
      ),
    );
  }

  Widget _buildNotesList(String type, bool isDark, Color textColor, Color bg) {
    return StreamBuilder<QuerySnapshot>(
      stream: _notesRef
          .where('type', isEqualTo: type)
          .orderBy('createdAt', descending: true)
          .snapshots(includeMetadataChanges: true),
      builder: (ctx, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(
              child: CircularProgressIndicator(color: Color(0xFF7C4DFF)));
        }
        if (snapshot.hasError) {
          return Center(
            child: Text('Error: ${snapshot.error}',
                style: TextStyle(color: textColor)),
          );
        }

        var docs = snapshot.data?.docs ?? [];

        // Filter by search query
        if (_searchQuery.isNotEmpty) {
          docs = docs.where((doc) {
            final data = doc.data() as Map<String, dynamic>;
            return (data['title'] ?? '')
                    .toString()
                    .toLowerCase()
                    .contains(_searchQuery) ||
                (data['subject'] ?? '')
                    .toString()
                    .toLowerCase()
                    .contains(_searchQuery) ||
                (data['content'] ?? '')
                    .toString()
                    .toLowerCase()
                    .contains(_searchQuery);
          }).toList();
        }

        if (docs.isEmpty) {
          return Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  type == 'text'
                      ? Icons.text_snippet_outlined
                      : type == 'photo'
                          ? Icons.image_outlined
                          : Icons.picture_as_pdf_outlined,
                  size: 64,
                  color: textColor.withValues(alpha: 0.2),
                ),
                const SizedBox(height: 12),
                Text(
                  _searchQuery.isNotEmpty
                      ? 'No notes found'
                      : 'No ${type == 'text' ? 'text' : type == 'photo' ? 'photo' : 'PDF'} notes yet',
                  style: TextStyle(
                      color: textColor.withValues(alpha: 0.4), fontSize: 14),
                ),
                const SizedBox(height: 8),
                Text('Tap + Add Note to get started',
                    style: TextStyle(
                        color: textColor.withValues(alpha: 0.25),
                        fontSize: 12)),
              ],
            ),
          );
        }

        return ListView.builder(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
          itemCount: docs.length,
          itemBuilder: (ctx, i) {
            final doc = docs[i];
            final data = doc.data() as Map<String, dynamic>;
            return _buildNoteCard(doc.id, data, isDark, textColor, bg, type);
          },
        );
      },
    );
  }

  Widget _buildNoteCard(String docId, Map<String, dynamic> data, bool isDark,
      Color textColor, Color bg, String type) {
    final typeColors = {
      'text': const Color(0xFF7C4DFF),
      'photo': Colors.teal,
      'pdf': Colors.red,
    };
    final color = typeColors[type] ?? const Color(0xFF7C4DFF);

    return GestureDetector(
      onTap: () async {
        final deleted = await Navigator.push<bool>(
          context,
          MaterialPageRoute(
            builder: (_) => NoteDetailPage(noteId: docId, noteData: data),
          ),
        );
        // If deleted from detail page, list auto-updates via StreamBuilder
        if (deleted == true) {
          _showSnackBar('Note deleted!');
        }
      },
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(16),
          boxShadow: isDark
              ? [
                  BoxShadow(
                      color: Colors.black.withValues(alpha: 0.4),
                      offset: const Offset(5, 5),
                      blurRadius: 10),
                  BoxShadow(
                      color: Colors.white.withValues(alpha: 0.04),
                      offset: const Offset(-5, -5),
                      blurRadius: 10),
                ]
              : [
                  BoxShadow(
                      color: Colors.grey.withValues(alpha: 0.3),
                      offset: const Offset(5, 5),
                      blurRadius: 10),
                  BoxShadow(
                      color: Colors.white.withValues(alpha: 0.9),
                      offset: const Offset(-5, -5),
                      blurRadius: 10),
                ],
        ),
        child: ListTile(
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          leading: Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(
              type == 'text'
                  ? Icons.text_snippet_outlined
                  : type == 'photo'
                      ? Icons.image_outlined
                      : Icons.picture_as_pdf_outlined,
              color: color,
              size: 22,
            ),
          ),
          title: Text(
            data['title'] ?? 'Untitled',
            style: TextStyle(
                color: textColor, fontWeight: FontWeight.w600, fontSize: 15),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          subtitle: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if ((data['subject'] ?? '').toString().isNotEmpty) ...[
                const SizedBox(height: 2),
                Text(
                  data['subject'],
                  style: TextStyle(
                      color: color.withValues(alpha: 0.8), fontSize: 12),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
              if (type == 'text' &&
                  (data['content'] ?? '').toString().isNotEmpty) ...[
                const SizedBox(height: 2),
                Text(
                  data['content'],
                  style: TextStyle(
                      color: textColor.withValues(alpha: 0.45), fontSize: 12),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ],
          ),
          trailing: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              data['category'] ?? 'General',
              style: TextStyle(
                  color: color, fontSize: 10, fontWeight: FontWeight.w600),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildModalField(
    TextEditingController ctrl,
    String label,
    IconData icon,
    Color textColor,
    Color bg,
    bool isDark, {
    int maxLines = 1,
  }) {
    return TextField(
      controller: ctrl,
      maxLines: maxLines,
      style: TextStyle(color: textColor),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(color: Color(0xFF7C4DFF)),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
        enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: Colors.grey.withValues(alpha: 0.3))),
        focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: Color(0xFF7C4DFF))),
        prefixIcon: Icon(icon, color: const Color(0xFF7C4DFF)),
        filled: true,
        fillColor: isDark
            ? Colors.white.withValues(alpha: 0.05)
            : Colors.white.withValues(alpha: 0.7),
      ),
    );
  }

  Widget _buildAddOptionCard({
    required IconData icon,
    required String label,
    required Color color,
    required bool isDark,
    required Color textColor,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 16),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: color.withValues(alpha: 0.3)),
        ),
        child: Column(
          children: [
            Icon(icon, color: color, size: 28),
            const SizedBox(height: 8),
            Text(label,
                style: TextStyle(
                    color: color, fontSize: 12, fontWeight: FontWeight.w600)),
          ],
        ),
      ),
    );
  }
}
