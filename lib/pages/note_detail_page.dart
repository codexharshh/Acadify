import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../Services/theme_provider.dart';

class NoteDetailPage extends StatefulWidget {
  final String noteId;
  final Map<String, dynamic> noteData;

  const NoteDetailPage({
    super.key,
    required this.noteId,
    required this.noteData,
  });

  @override
  State<NoteDetailPage> createState() => _NoteDetailPageState();
}

class _NoteDetailPageState extends State<NoteDetailPage>
    with SingleTickerProviderStateMixin {
  ThemeProvider get _t => Provider.of<ThemeProvider>(context, listen: false);
  bool _isEditing = false;
  bool _isSaving = false;

  late TextEditingController _titleController;
  late TextEditingController _contentController;
  late TextEditingController _subjectController;
  late AnimationController _animController;
  late Animation<double> _fadeAnim;

  final List<String> _categories = [
    'General',
    'Math',
    'Science',
    'History',
    'English',
    'Computer',
    'Other',
  ];
  String _selectedCategory = 'General';

  @override
  void initState() {
    super.initState();
    _titleController =
        TextEditingController(text: widget.noteData['title'] ?? '');
    _contentController =
        TextEditingController(text: widget.noteData['content'] ?? '');
    _subjectController =
        TextEditingController(text: widget.noteData['subject'] ?? '');
    _selectedCategory = widget.noteData['category'] ?? 'General';

    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    );
    _fadeAnim = CurvedAnimation(
      parent: _animController,
      curve: Curves.easeInOut,
    );
    _animController.forward();
  }

  @override
  void dispose() {
    _titleController.dispose();
    _contentController.dispose();
    _subjectController.dispose();
    _animController.dispose();
    super.dispose();
  }

  Future<void> _saveNote() async {
    if (_titleController.text.trim().isEmpty) {
      _showSnackBar('Title cannot be empty!', isError: true);
      return;
    }
    setState(() => _isSaving = true);
    try {
      final uid = FirebaseAuth.instance.currentUser!.uid;
      await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .collection('notes')
          .doc(widget.noteId)
          .update({
        'title': _titleController.text.trim(),
        'content': _contentController.text.trim(),
        'subject': _subjectController.text.trim(),
        'category': _selectedCategory,
        'updatedAt': FieldValue.serverTimestamp(),
      });
      setState(() {
        _isEditing = false;
        _isSaving = false;
      });
      _showSnackBar('Note saved successfully! ✅');
    } catch (e) {
      setState(() => _isSaving = false);
      _showSnackBar('Error saving note: $e', isError: true);
    }
  }

  Future<void> _deleteNote() async {
    final confirmed = await _showDeleteDialog();
    if (!confirmed) return;
    try {
      final uid = FirebaseAuth.instance.currentUser!.uid;
      await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .collection('notes')
          .doc(widget.noteId)
          .delete();
      if (mounted) {
        Navigator.pop(context, true); // true = deleted
        _showSnackBar('Note deleted!');
      }
    } catch (e) {
      _showSnackBar('Error deleting note: $e', isError: true);
    }
  }

  Future<bool> _showDeleteDialog() async {
    final bg = _t.bgColor;
    final textColor = _t.textPrimary;

    return await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            backgroundColor: bg,
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            title: Text(
              '🗑️ Delete Note?',
              style: TextStyle(
                  color: textColor, fontWeight: FontWeight.bold, fontSize: 18),
            ),
            content: Text(
              'This note will be permanently deleted. Are you sure?',
              style: TextStyle(
                  color: textColor.withValues(alpha: 0.7), fontSize: 14),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: Text('Cancel',
                    style: TextStyle(color: textColor.withValues(alpha: 0.6))),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.red.shade400,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                ),
                onPressed: () => Navigator.pop(ctx, true),
                child:
                    const Text('Delete', style: TextStyle(color: Colors.white)),
              ),
            ],
          ),
        ) ??
        false;
  }

  void _shareNote() {
    final noteType = widget.noteData['type'] ?? 'text';
    String shareText =
        '${_titleController.text}\n\nSubject: ${_subjectController.text}\n\n';

    if (noteType == 'text') {
      shareText += _contentController.text;
    } else {
      final url = widget.noteData['imageUrl'] ?? '';
      shareText +=
          url.isNotEmpty ? url : '[${noteType.toUpperCase()} Note - Acadify]';
    }

    Share.share(shareText, subject: _titleController.text);
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
    final bg = _t.bgColor;
    final textColor = _t.textPrimary;
    final noteType = widget.noteData['type'] ?? 'text';

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
        title: Text(
          _isEditing ? 'Edit Note' : 'Note Details',
          style: const TextStyle(
              color: Colors.white, fontWeight: FontWeight.bold, fontSize: 18),
        ),
        iconTheme: const IconThemeData(color: Colors.white),
        actions: [
          if (!_isEditing) ...[
            IconButton(
              icon: const Icon(Icons.share_outlined, color: Colors.white),
              tooltip: 'Share',
              onPressed: _shareNote,
            ),
            IconButton(
              icon: const Icon(Icons.edit_outlined, color: Colors.white),
              tooltip: 'Edit',
              onPressed: () => setState(() => _isEditing = true),
            ),
            IconButton(
              icon: const Icon(Icons.delete_outline, color: Colors.white),
              tooltip: 'Delete',
              onPressed: _deleteNote,
            ),
          ] else ...[
            if (_isSaving)
              const Padding(
                padding: EdgeInsets.all(16),
                child: SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                      color: Colors.white, strokeWidth: 2),
                ),
              )
            else
              IconButton(
                icon: const Icon(Icons.check, color: Colors.white),
                tooltip: 'Save',
                onPressed: _saveNote,
              ),
            IconButton(
              icon: const Icon(Icons.close, color: Colors.white),
              tooltip: 'Cancel',
              onPressed: () => setState(() => _isEditing = false),
            ),
          ],
        ],
      ),
      body: FadeTransition(
        opacity: _fadeAnim,
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Type Badge + Category
              Row(
                children: [
                  _buildTypeBadge(noteType),
                  const SizedBox(width: 8),
                  _buildCategoryChip(isDark, textColor),
                ],
              ),
              const SizedBox(height: 16),

              // Title
              _buildNeuCard(
                isDark: isDark,
                child: _isEditing
                    ? TextField(
                        controller: _titleController,
                        style: TextStyle(
                            color: textColor,
                            fontSize: 20,
                            fontWeight: FontWeight.bold),
                        decoration: InputDecoration(
                          border: InputBorder.none,
                          hintText: 'Enter title...',
                          hintStyle: TextStyle(
                              color: textColor.withValues(alpha: 0.4)),
                          labelText: 'Title',
                          labelStyle: const TextStyle(
                              color: Color(0xFF7C4DFF), fontSize: 12),
                          floatingLabelBehavior: FloatingLabelBehavior.always,
                        ),
                      )
                    : Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('Title',
                              style: TextStyle(
                                  color: Color(0xFF7C4DFF),
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600)),
                          const SizedBox(height: 4),
                          Text(
                            _titleController.text.isEmpty
                                ? 'Untitled'
                                : _titleController.text,
                            style: TextStyle(
                                color: textColor,
                                fontSize: 20,
                                fontWeight: FontWeight.bold),
                          ),
                        ],
                      ),
              ),
              const SizedBox(height: 12),

              // Subject
              _buildNeuCard(
                isDark: isDark,
                child: _isEditing
                    ? TextField(
                        controller: _subjectController,
                        style: TextStyle(color: textColor, fontSize: 15),
                        decoration: InputDecoration(
                          border: InputBorder.none,
                          hintText: 'Subject/Topic...',
                          hintStyle: TextStyle(
                              color: textColor.withValues(alpha: 0.4)),
                          labelText: 'Subject',
                          labelStyle: const TextStyle(
                              color: Color(0xFF7C4DFF), fontSize: 12),
                          floatingLabelBehavior: FloatingLabelBehavior.always,
                          prefixIcon: const Icon(Icons.subject,
                              color: Color(0xFF7C4DFF), size: 20),
                        ),
                      )
                    : Row(
                        children: [
                          const Icon(Icons.subject,
                              color: Color(0xFF7C4DFF), size: 18),
                          const SizedBox(width: 8),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text('Subject',
                                  style: TextStyle(
                                      color: Color(0xFF7C4DFF),
                                      fontSize: 11,
                                      fontWeight: FontWeight.w600)),
                              Text(
                                _subjectController.text.isEmpty
                                    ? 'No subject'
                                    : _subjectController.text,
                                style:
                                    TextStyle(color: textColor, fontSize: 15),
                              ),
                            ],
                          ),
                        ],
                      ),
              ),
              const SizedBox(height: 12),

              // Category Dropdown (edit mode only)
              if (_isEditing) ...[
                _buildNeuCard(
                  isDark: isDark,
                  child: DropdownButtonFormField<String>(
                    initialValue: _selectedCategory,
                    dropdownColor: bg,
                    decoration: const InputDecoration(
                      border: InputBorder.none,
                      labelText: 'Category',
                      labelStyle:
                          TextStyle(color: Color(0xFF7C4DFF), fontSize: 12),
                      floatingLabelBehavior: FloatingLabelBehavior.always,
                      prefixIcon: Icon(Icons.folder_outlined,
                          color: Color(0xFF7C4DFF), size: 20),
                    ),
                    items: _categories
                        .map((cat) => DropdownMenuItem(
                              value: cat,
                              child:
                                  Text(cat, style: TextStyle(color: textColor)),
                            ))
                        .toList(),
                    onChanged: (val) =>
                        setState(() => _selectedCategory = val!),
                    style: TextStyle(color: textColor),
                    icon: Icon(Icons.arrow_drop_down,
                        color: textColor.withValues(alpha: 0.5)),
                  ),
                ),
                const SizedBox(height: 12),
              ],

              // Content / Media
              if (noteType == 'text') ...[
                _buildNeuCard(
                  isDark: isDark,
                  minHeight: 200,
                  child: _isEditing
                      ? TextField(
                          controller: _contentController,
                          maxLines: null,
                          style: TextStyle(
                              color: textColor, fontSize: 15, height: 1.6),
                          decoration: InputDecoration(
                            border: InputBorder.none,
                            hintText: 'Write note content...',
                            hintStyle: TextStyle(
                                color: textColor.withValues(alpha: 0.4)),
                            labelText: 'Content',
                            labelStyle: const TextStyle(
                                color: Color(0xFF7C4DFF), fontSize: 12),
                            floatingLabelBehavior: FloatingLabelBehavior.always,
                          ),
                        )
                      : Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('Content',
                                style: TextStyle(
                                    color: Color(0xFF7C4DFF),
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600)),
                            const SizedBox(height: 8),
                            _contentController.text.isEmpty
                                ? Text('No content...',
                                    style: TextStyle(
                                        color: textColor.withValues(alpha: 0.4),
                                        fontStyle: FontStyle.italic))
                                : Text(
                                    _contentController.text,
                                    style: TextStyle(
                                        color: textColor,
                                        fontSize: 15,
                                        height: 1.6),
                                  ),
                          ],
                        ),
                ),
              ] else if (noteType == 'photo') ...[
                _buildNeuCard(
                  isDark: isDark,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Photo',
                          style: TextStyle(
                              color: Color(0xFF7C4DFF),
                              fontSize: 12,
                              fontWeight: FontWeight.w600)),
                      const SizedBox(height: 8),
                      if (widget.noteData['imageUrl'] != null &&
                          widget.noteData['imageUrl'].toString().isNotEmpty)
                        ClipRRect(
                          borderRadius: BorderRadius.circular(12),
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(maxHeight: 300),
                            child: Image.network(
                              widget.noteData['imageUrl'],
                              fit: BoxFit.contain,
                              width: double.infinity,
                              loadingBuilder: (ctx, child, progress) =>
                                  progress == null
                                      ? child
                                      : Container(
                                          height: 200,
                                          color: isDark
                                              ? Colors.white
                                                  .withValues(alpha: 0.05)
                                              : Colors.black
                                                  .withValues(alpha: 0.05),
                                          child: const Center(
                                            child: CircularProgressIndicator(
                                                color: Color(0xFF7C4DFF)),
                                          ),
                                        ),
                              errorBuilder: (ctx, err, st) => Container(
                                height: 120,
                                decoration: BoxDecoration(
                                  color: isDark
                                      ? Colors.white.withValues(alpha: 0.05)
                                      : Colors.black.withValues(alpha: 0.05),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Center(
                                  child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(Icons.broken_image_outlined,
                                          color:
                                              textColor.withValues(alpha: 0.3),
                                          size: 40),
                                      const SizedBox(height: 8),
                                      Text('Image failed to load',
                                          style: TextStyle(
                                              color: textColor.withValues(
                                                  alpha: 0.4))),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ),
                        )
                      else
                        _buildMediaPlaceholder(Icons.image_outlined, 'No photo',
                            textColor, isDark),
                    ],
                  ),
                ),
              ] else if (noteType == 'pdf') ...[
                _buildNeuCard(
                  isDark: isDark,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('PDF Document',
                          style: TextStyle(
                              color: Color(0xFF7C4DFF),
                              fontSize: 12,
                              fontWeight: FontWeight.w600)),
                      const SizedBox(height: 12),
                      if (widget.noteData['imageUrl'] != null &&
                          widget.noteData['imageUrl'].toString().isNotEmpty)
                        _buildPdfCard(
                            widget.noteData['imageUrl'], isDark, textColor)
                      else
                        _buildMediaPlaceholder(Icons.picture_as_pdf_outlined,
                            'No PDF', textColor, isDark),
                    ],
                  ),
                ),
              ],

              const SizedBox(height: 12),

              // Timestamps
              _buildNeuCard(
                isDark: isDark,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Info',
                        style: TextStyle(
                            color: Color(0xFF7C4DFF),
                            fontSize: 12,
                            fontWeight: FontWeight.w600)),
                    const SizedBox(height: 8),
                    _buildInfoRow(
                        Icons.calendar_today_outlined,
                        'Created: ${_formatTimestamp(widget.noteData['createdAt'])}',
                        textColor),
                    if (widget.noteData['updatedAt'] != null) ...[
                      const SizedBox(height: 4),
                      _buildInfoRow(
                          Icons.update_outlined,
                          'Updated: ${_formatTimestamp(widget.noteData['updatedAt'])}',
                          textColor),
                    ],
                    const SizedBox(height: 4),
                    _buildInfoRow(Icons.category_outlined,
                        'Category: $_selectedCategory', textColor),
                  ],
                ),
              ),

              const SizedBox(height: 24),

              // Bottom action buttons (view mode)
              if (!_isEditing) ...[
                Row(
                  children: [
                    Expanded(
                      child: _buildActionButton(
                        icon: Icons.edit,
                        label: 'Edit Note',
                        color: const Color(0xFF7C4DFF),
                        onTap: () => setState(() => _isEditing = true),
                        isDark: isDark,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _buildActionButton(
                        icon: Icons.delete_outline,
                        label: 'Delete Note',
                        color: Colors.red.shade400,
                        onTap: _deleteNote,
                        isDark: isDark,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: _buildActionButton(
                    icon: Icons.share_outlined,
                    label: 'Share Note',
                    color: Colors.teal.shade400,
                    onTap: _shareNote,
                    isDark: isDark,
                  ),
                ),
              ],

              const SizedBox(height: 32),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildNeuCard(
      {required bool isDark, required Widget child, double? minHeight}) {
    return Container(
      width: double.infinity,
      constraints:
          minHeight != null ? BoxConstraints(minHeight: minHeight) : null,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1A1A2E) : const Color(0xFFEEEEF5),
        borderRadius: BorderRadius.circular(16),
        boxShadow: isDark
            ? [
                BoxShadow(
                    color: Colors.black.withValues(alpha: 0.4),
                    offset: const Offset(5, 5),
                    blurRadius: 10),
                BoxShadow(
                    color: Colors.white.withValues(alpha: 0.05),
                    offset: const Offset(-5, -5),
                    blurRadius: 10),
              ]
            : [
                BoxShadow(
                    color: Colors.grey.withValues(alpha: 0.35),
                    offset: const Offset(5, 5),
                    blurRadius: 10),
                BoxShadow(
                    color: Colors.white.withValues(alpha: 0.9),
                    offset: const Offset(-5, -5),
                    blurRadius: 10),
              ],
      ),
      child: child,
    );
  }

  Widget _buildTypeBadge(String type) {
    final config = {
      'text': {
        'icon': Icons.text_snippet_outlined,
        'label': 'Text',
        'color': const Color(0xFF7C4DFF)
      },
      'photo': {
        'icon': Icons.image_outlined,
        'label': 'Photo',
        'color': Colors.teal
      },
      'pdf': {
        'icon': Icons.picture_as_pdf_outlined,
        'label': 'PDF',
        'color': Colors.red
      },
    };
    final c = config[type] ?? config['text']!;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            (c['color'] as Color).withValues(alpha: 0.2),
            (c['color'] as Color).withValues(alpha: 0.1),
          ],
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: (c['color'] as Color).withValues(alpha: 0.4)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(c['icon'] as IconData, size: 14, color: c['color'] as Color),
          const SizedBox(width: 4),
          Text(c['label'] as String,
              style: TextStyle(
                  color: c['color'] as Color,
                  fontSize: 12,
                  fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }

  Widget _buildCategoryChip(bool isDark, Color textColor) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: isDark
            ? Colors.white.withValues(alpha: 0.05)
            : Colors.black.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.folder_outlined,
              size: 14, color: textColor.withValues(alpha: 0.5)),
          const SizedBox(width: 4),
          Text(_selectedCategory,
              style: TextStyle(
                  color: textColor.withValues(alpha: 0.7),
                  fontSize: 12,
                  fontWeight: FontWeight.w500)),
        ],
      ),
    );
  }

  Widget _buildPdfCard(String url, bool isDark, Color textColor) {
    return GestureDetector(
      onTap: () {
        Share.share(url, subject: 'PDF Note');
      },
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.red.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.red.withValues(alpha: 0.3)),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.red.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(10),
              ),
              child:
                  const Icon(Icons.picture_as_pdf, color: Colors.red, size: 28),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('PDF Document',
                      style: TextStyle(
                          color: textColor,
                          fontWeight: FontWeight.w600,
                          fontSize: 14)),
                  const SizedBox(height: 2),
                  Text(
                    url.length > 40 ? '${url.substring(0, 40)}...' : url,
                    style: TextStyle(
                        color: textColor.withValues(alpha: 0.5), fontSize: 11),
                  ),
                  const SizedBox(height: 4),
                  Text('Tap to copy URL',
                      style: TextStyle(
                          color: Colors.red.withValues(alpha: 0.7),
                          fontSize: 11,
                          fontWeight: FontWeight.w500)),
                ],
              ),
            ),
            Icon(Icons.copy_outlined,
                color: Colors.red.withValues(alpha: 0.7), size: 18),
          ],
        ),
      ),
    );
  }

  Widget _buildMediaPlaceholder(
      IconData icon, String msg, Color textColor, bool isDark) {
    return Container(
      height: 100,
      width: double.infinity,
      decoration: BoxDecoration(
        color: isDark
            ? Colors.white.withValues(alpha: 0.03)
            : Colors.black.withValues(alpha: 0.03),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, color: textColor.withValues(alpha: 0.25), size: 36),
          const SizedBox(height: 6),
          Text(msg,
              style: TextStyle(
                  color: textColor.withValues(alpha: 0.3),
                  fontSize: 12,
                  fontStyle: FontStyle.italic)),
        ],
      ),
    );
  }

  Widget _buildInfoRow(IconData icon, String text, Color textColor) {
    return Row(
      children: [
        Icon(icon, size: 14, color: textColor.withValues(alpha: 0.4)),
        const SizedBox(width: 6),
        Text(text,
            style: TextStyle(
                color: textColor.withValues(alpha: 0.6), fontSize: 12)),
      ],
    );
  }

  Widget _buildActionButton({
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onTap,
    required bool isDark,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [color.withValues(alpha: 0.8), color],
          ),
          borderRadius: BorderRadius.circular(14),
          boxShadow: [
            BoxShadow(
                color: color.withValues(alpha: 0.35),
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
                    fontSize: 14)),
          ],
        ),
      ),
    );
  }

  String _formatTimestamp(dynamic ts) {
    if (ts == null) return 'Unknown';
    if (ts is Timestamp) {
      final dt = ts.toDate();
      return '${dt.day}/${dt.month}/${dt.year} ${dt.hour}:${dt.minute.toString().padLeft(2, '0')}';
    }
    return ts.toString();
  }
}
