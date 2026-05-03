// pages/yt_notes_page.dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'dart:convert';
import '../Services/theme_provider.dart';
import '../Services/ai_service.dart';

class YTNotesPage extends StatefulWidget {
  const YTNotesPage({super.key});

  @override
  State<YTNotesPage> createState() => _YTNotesPageState();
}

class _YTNotesPageState extends State<YTNotesPage> {
  ThemeProvider get _t => Provider.of<ThemeProvider>(context, listen: false);
  final TextEditingController _urlCtrl = TextEditingController();
  final TextEditingController _titleCtrl = TextEditingController();

  bool _isGenerating = false;
  bool _isSaving = false;
  String _status = '';
  Map<String, dynamic>? _generatedNotes;

  String get _uid => FirebaseAuth.instance.currentUser!.uid;

  // Extract YouTube video ID from URL
  String? _extractVideoId(String url) {
    final regexps = [
      RegExp(r'youtube\.com/watch\?v=([a-zA-Z0-9_-]{11})'),
      RegExp(r'youtu\.be/([a-zA-Z0-9_-]{11})'),
      RegExp(r'youtube\.com/embed/([a-zA-Z0-9_-]{11})'),
      RegExp(r'youtube\.com/shorts/([a-zA-Z0-9_-]{11})'),
    ];
    for (final r in regexps) {
      final m = r.firstMatch(url);
      if (m != null) return m.group(1);
    }
    return null;
  }

  String _getThumbnailUrl(String videoId) =>
      'https://img.youtube.com/vi/$videoId/maxresdefault.jpg';

  Future<void> _generateNotes() async {
    final url = _urlCtrl.text.trim();
    if (url.isEmpty) {
      _showSnackBar('Please enter a YouTube URL!', isError: true);
      return;
    }

    final videoId = _extractVideoId(url);
    if (videoId == null) {
      _showSnackBar('Invalid YouTube URL!', isError: true);
      return;
    }

    setState(() {
      _isGenerating = true;
      _status = 'Fetching video info...';
      _generatedNotes = null;
    });

    try {
      // Fetch video title via YouTube oEmbed API
      String videoTitle = _titleCtrl.text.trim();
      if (videoTitle.isEmpty) {
        setState(() => _status = 'Getting video title...');
        try {
          final oEmbedRes = await http.get(Uri.parse(
              'https://www.youtube.com/oembed?url=https://www.youtube.com/watch?v=$videoId&format=json'));
          if (oEmbedRes.statusCode == 200) {
            final oData = jsonDecode(oEmbedRes.body);
            videoTitle = oData['title'] ?? 'YouTube Video';
          }
        } catch (_) {
          videoTitle = 'YouTube Video';
        }
      }

      setState(() => _status = 'Generating summary & key points...');

      // ── CALL 1: summary, key_points, takeaways (light content) ──────────────
      final prompt1 =
          'Generate study notes for a YouTube video. Output ONLY valid JSON, no markdown.\n'
          'Video Title: "$videoTitle"\n'
          'No newlines inside string values.\n'
          'Return exactly:\n'
          '{"title":"$videoTitle",'
          '"topic":"subject area (3-5 words)",'
          '"summary":"3 sentence overview of what this video teaches",'
          '"key_points":["specific point 1","specific point 2","specific point 3","specific point 4","specific point 5","specific point 6"],'
          '"takeaways":["important lesson 1","important lesson 2","important lesson 3","important lesson 4"]}';

      final raw1 =
          await AiService.call(prompt1, maxTokens: 1000, temperature: 0.3);
      final part1 = _parseJsonObject(raw1);

      setState(() => _status = 'Generating detailed notes & terms...');

      // ── CALL 2: detailed_notes and key_terms ─────────────────────────────────
      final prompt2 =
          'Generate detailed study notes and key terms for a YouTube video. Output ONLY valid JSON, no markdown.\n'
          'Video Title: "$videoTitle"\n'
          'No newlines inside string values. Each content field: 2-3 informative sentences.\n'
          'Return exactly:\n'
          '{"detailed_notes":['
          '{"heading":"Introduction & Overview","content":"explain the topic background and importance"},'
          '{"heading":"Core Concepts","content":"explain the main ideas and theories"},'
          '{"heading":"Key Methods & Techniques","content":"explain methods, formulas, or steps involved"},'
          '{"heading":"Practical Applications","content":"explain real-world uses and examples"},'
          '{"heading":"Conclusion","content":"summarize the most important points"}'
          '],'
          '"key_terms":['
          '{"term":"term1","definition":"1-2 sentence definition"},'
          '{"term":"term2","definition":"1-2 sentence definition"},'
          '{"term":"term3","definition":"1-2 sentence definition"},'
          '{"term":"term4","definition":"1-2 sentence definition"},'
          '{"term":"term5","definition":"1-2 sentence definition"}'
          ']}';

      final raw2 =
          await AiService.call(prompt2, maxTokens: 1200, temperature: 0.3);
      final part2 = _parseJsonObject(raw2);

      // ── Merge both parts ──────────────────────────────────────────────────────
      final Map<String, dynamic> notesData = {
        'title': part1['title'] ?? videoTitle,
        'topic': part1['topic'] ?? 'General',
        'summary': part1['summary'] ?? '',
        'key_points': part1['key_points'] ?? <dynamic>[],
        'takeaways': part1['takeaways'] ?? <dynamic>[],
        'detailed_notes': part2['detailed_notes'] ??
            <dynamic>[
              {
                'heading': 'Overview',
                'content': 'Please regenerate for detailed notes.'
              }
            ],
        'key_terms': part2['key_terms'] ?? <dynamic>[],
      };
      notesData['videoId'] = videoId;
      notesData['videoUrl'] = url;
      notesData['thumbnailUrl'] = _getThumbnailUrl(videoId);

      setState(() {
        _generatedNotes = notesData;
        _isGenerating = false;
        _status = '';
      });
    } catch (e) {
      setState(() {
        _isGenerating = false;
        _status = '';
      });
      _showSnackBar('Error: $e', isError: true);
    }
  }

  /// Clean raw AI text and parse as JSON object. Throws on failure.
  Map<String, dynamic> _parseJsonObject(String raw) {
    String cleaned = raw
        .replaceAll(RegExp(r'```json\s*'), '')
        .replaceAll(RegExp(r'```\s*'), '')
        .trim();
    final start = cleaned.indexOf('{');
    final end = cleaned.lastIndexOf('}');
    if (start != -1 && end != -1 && end > start) {
      cleaned = cleaned.substring(start, end + 1);
    }
    // Escape raw newlines inside strings
    final buf = StringBuffer();
    bool inStr = false, esc = false;
    for (final ch in cleaned.split('')) {
      if (esc) {
        buf.write(ch);
        esc = false;
        continue;
      }
      if (ch == '\\') {
        esc = true;
        buf.write(ch);
        continue;
      }
      if (ch == '"') {
        inStr = !inStr;
        buf.write(ch);
        continue;
      }
      if (inStr && ch == '\n') {
        buf.write(r'\n');
        continue;
      }
      if (inStr && ch == '\r') continue;
      buf.write(ch);
    }
    cleaned = buf.toString().replaceAll(RegExp(r',\s*([\]}])'), r'$1');
    try {
      return jsonDecode(cleaned) as Map<String, dynamic>;
    } catch (_) {
      return _recoverPartialNotes(cleaned, '');
    }
  }

  /// Fallback: extract whatever fields were successfully parsed before truncation
  Map<String, dynamic> _recoverPartialNotes(String partial, String title) {
    Map<String, dynamic> result = {
      'title': title,
      'topic': 'General',
      'summary': 'Notes generated from video: $title',
      'key_points': <dynamic>['See video for details'],
      'detailed_notes': <dynamic>[
        {
          'heading': 'Overview',
          'content': 'Notes could not be fully parsed. Please regenerate.'
        }
      ],
      'key_terms': <dynamic>[],
      'takeaways': <dynamic>['Please regenerate notes for full content'],
    };
    // Try to parse each field individually using regex
    void tryStr(String key) {
      final m =
          RegExp('"$key"\\s*:\\s*"((?:[^"\\\\]|\\\\.)*)"').firstMatch(partial);
      if (m != null) result[key] = m.group(1)!.replaceAll(r'\n', ' ');
    }

    void tryArr(String key) {
      final m = RegExp('"$key"\\s*:\\s*(\\[.*?\\])', dotAll: true)
          .firstMatch(partial);
      if (m != null) {
        try {
          result[key] = jsonDecode(m.group(1)!) as List;
        } catch (_) {}
      }
    }

    tryStr('topic');
    tryStr('summary');
    tryArr('key_points');
    tryArr('detailed_notes');
    tryArr('key_terms');
    tryArr('takeaways');
    return result;
  }

  Future<void> _saveToNotesManager() async {
    if (_generatedNotes == null) return;
    setState(() => _isSaving = true);

    try {
      final title = _generatedNotes!['title'] ?? 'YT Notes';
      final topic = _generatedNotes!['topic'] ?? 'General';

      // Build content string
      final sb = StringBuffer();
      sb.writeln('📺 YouTube Notes\n');
      sb.writeln(' Summary:\n${_generatedNotes!['summary']}\n');

      sb.writeln('🔑 Key Points:');
      for (final point in (_generatedNotes!['key_points'] as List)) {
        sb.writeln('• $point');
      }
      sb.writeln();

      sb.writeln('📖 Detailed Notes:');
      for (final section in (_generatedNotes!['detailed_notes'] as List)) {
        sb.writeln('\n${section['heading']}:');
        sb.writeln(section['content']);
      }
      sb.writeln();

      sb.writeln('📚 Key Terms:');
      for (final term in (_generatedNotes!['key_terms'] as List)) {
        sb.writeln('• ${term['term']}: ${term['definition']}');
      }
      sb.writeln();

      sb.writeln(' Key Takeaways:');
      for (final t in (_generatedNotes!['takeaways'] as List)) {
        sb.writeln('• $t');
      }

      sb.writeln('\n🔗 Video: ${_generatedNotes!['videoUrl']}');

      await FirebaseFirestore.instance
          .collection('users')
          .doc(_uid)
          .collection('notes')
          .add({
        'title': title,
        'content': sb.toString(),
        'subject': topic,
        'category': 'General',
        'type': 'text',
        'imageUrl': '',
        'createdAt': Timestamp.now(),
        'source': 'youtube',
      });

      setState(() => _isSaving = false);
      _showSnackBar('Notes saved to Notes Manager! ');
    } catch (e) {
      setState(() => _isSaving = false);
      _showSnackBar('Error saving: $e', isError: true);
    }
  }

  void _copyNotes() {
    if (_generatedNotes == null) return;
    final sb = StringBuffer();
    sb.writeln(_generatedNotes!['title']);
    sb.writeln('Topic: ${_generatedNotes!['topic']}\n');
    sb.writeln('Summary:\n${_generatedNotes!['summary']}\n');
    sb.writeln('Key Points:');
    for (final p in (_generatedNotes!['key_points'] as List)) {
      sb.writeln('• $p');
    }
    sb.writeln('\nDetailed Notes:');
    for (final s in (_generatedNotes!['detailed_notes'] as List)) {
      sb.writeln('\n${s['heading']}:\n${s['content']}');
    }
    sb.writeln('\nKey Terms:');
    for (final t in (_generatedNotes!['key_terms'] as List)) {
      sb.writeln('• ${t['term']}: ${t['definition']}');
    }
    sb.writeln('\nTakeaways:');
    for (final t in (_generatedNotes!['takeaways'] as List)) {
      sb.writeln('• $t');
    }
    Clipboard.setData(ClipboardData(text: sb.toString()));
    _showSnackBar('Notes copied to clipboard! 📋');
  }

  void _showSnackBar(String msg, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: isError ? Colors.red.shade400 : const Color(0xFF7C4DFF),
      behavior: SnackBarBehavior.floating,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(12))),
    ));
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
            ),
          ),
        ),
        title: const Text('YT Notes',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Input Card
            _buildNeuCard(
              isDark: isDark,
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
                        child: const Icon(Icons.smart_display,
                            color: Colors.white, size: 22),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('YouTube Notes Generator',
                                style: TextStyle(
                                    color: textColor,
                                    fontSize: 17,
                                    fontWeight: FontWeight.bold)),
                            Text('Paste a YouTube URL → Get instant notes!',
                                style: TextStyle(
                                    color: textColor.withValues(alpha: 0.5),
                                    fontSize: 12)),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),

                  // URL field
                  Text('YouTube URL',
                      style: TextStyle(
                          color: textColor,
                          fontSize: 13,
                          fontWeight: FontWeight.w600)),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _urlCtrl,
                    style: TextStyle(color: textColor),
                    decoration: InputDecoration(
                      hintText: 'https://youtube.com/watch?v=...',
                      hintStyle:
                          TextStyle(color: textColor.withValues(alpha: 0.35)),
                      prefixIcon: const Icon(Icons.link,
                          color: Color(0xFF7C4DFF), size: 20),
                      suffixIcon: IconButton(
                        icon: Icon(Icons.clear,
                            color: textColor.withValues(alpha: 0.4), size: 18),
                        onPressed: () => _urlCtrl.clear(),
                      ),
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12)),
                      enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(
                              color: Colors.grey.withValues(alpha: 0.3))),
                      focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide:
                              const BorderSide(color: Color(0xFF7C4DFF))),
                      filled: true,
                      fillColor: isDark
                          ? Colors.white.withValues(alpha: 0.05)
                          : Colors.white.withValues(alpha: 0.7),
                    ),
                  ),
                  const SizedBox(height: 12),

                  // Optional title
                  Text('Video Title (optional)',
                      style: TextStyle(
                          color: textColor,
                          fontSize: 13,
                          fontWeight: FontWeight.w600)),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _titleCtrl,
                    style: TextStyle(color: textColor),
                    decoration: InputDecoration(
                      hintText: 'Leave blank to auto-detect',
                      hintStyle:
                          TextStyle(color: textColor.withValues(alpha: 0.35)),
                      prefixIcon: const Icon(Icons.title,
                          color: Color(0xFF7C4DFF), size: 20),
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12)),
                      enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(
                              color: Colors.grey.withValues(alpha: 0.3))),
                      focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide:
                              const BorderSide(color: Color(0xFF7C4DFF))),
                      filled: true,
                      fillColor: isDark
                          ? Colors.white.withValues(alpha: 0.05)
                          : Colors.white.withValues(alpha: 0.7),
                    ),
                  ),
                  const SizedBox(height: 20),

                  // Generate button
                  SizedBox(
                    width: double.infinity,
                    child: GestureDetector(
                      onTap: _isGenerating ? null : _generateNotes,
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        padding: const EdgeInsets.symmetric(vertical: 15),
                        decoration: BoxDecoration(
                          gradient: _isGenerating
                              ? LinearGradient(colors: [
                                  Colors.grey.shade400,
                                  Colors.grey.shade500
                                ])
                              : const LinearGradient(colors: [
                                  Color(0xFF6A1B9A),
                                  Color(0xFF9C27B0)
                                ]),
                          borderRadius: BorderRadius.circular(14),
                          boxShadow: _isGenerating
                              ? []
                              : [
                                  BoxShadow(
                                      color: const Color(0xFF7C4DFF)
                                          .withValues(alpha: 0.4),
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
                              const Icon(Icons.auto_awesome,
                                  color: Colors.white, size: 20),
                            const SizedBox(width: 10),
                            Text(
                              _isGenerating ? _status : 'Generate Notes',
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

            // Generated Notes
            if (_generatedNotes != null) ...[
              const SizedBox(height: 16),

              // Action buttons
              Row(
                children: [
                  Expanded(
                    child: GestureDetector(
                      onTap: _copyNotes,
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        decoration: BoxDecoration(
                          color: const Color(0xFF7C4DFF).withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                              color: const Color(0xFF7C4DFF)
                                  .withValues(alpha: 0.3)),
                        ),
                        child: const Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.copy,
                                color: Color(0xFF7C4DFF), size: 18),
                            SizedBox(width: 6),
                            Text('Copy',
                                style: TextStyle(
                                    color: Color(0xFF7C4DFF),
                                    fontWeight: FontWeight.bold)),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: GestureDetector(
                      onTap: _isSaving ? null : _saveToNotesManager,
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                              colors: [Colors.teal, Color(0xFF00897B)]),
                          borderRadius: BorderRadius.circular(12),
                          boxShadow: [
                            BoxShadow(
                                color: Colors.teal.withValues(alpha: 0.3),
                                blurRadius: 10,
                                offset: const Offset(0, 4))
                          ],
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            if (_isSaving)
                              const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(
                                      color: Colors.white, strokeWidth: 2))
                            else
                              const Icon(Icons.save_alt,
                                  color: Colors.white, size: 18),
                            const SizedBox(width: 6),
                            const Text('Save to Notes',
                                style: TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.bold)),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: GestureDetector(
                      onTap: _generateNotes,
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                              colors: [Color(0xFF6A1B9A), Color(0xFF9C27B0)]),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.refresh, color: Colors.white, size: 18),
                            SizedBox(width: 6),
                            Text('Regenerate',
                                style: TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.bold)),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 16),

              // Thumbnail
              if (_generatedNotes!['videoId'] != null)
                ClipRRect(
                  borderRadius: BorderRadius.circular(16),
                  child: Image.network(
                    _generatedNotes!['thumbnailUrl'],
                    width: double.infinity,
                    height: 200,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                  ),
                ),
              const SizedBox(height: 16),

              // Title + Topic
              _buildNeuCard(
                isDark: isDark,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _generatedNotes!['title'] ?? '',
                      style: const TextStyle(
                          color: Color(0xFF7C4DFF),
                          fontSize: 18,
                          fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: const Color(0xFF7C4DFF).withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        _generatedNotes!['topic'] ?? '',
                        style: const TextStyle(
                            color: Color(0xFF7C4DFF),
                            fontSize: 12,
                            fontWeight: FontWeight.w600),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      _generatedNotes!['summary'] ?? '',
                      style: TextStyle(
                          color: textColor.withValues(alpha: 0.7),
                          fontSize: 14,
                          height: 1.5),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),

              // Key Points
              _buildNotesSection(
                isDark: isDark,
                icon: Icons.lightbulb_outline,
                title: 'Key Points',
                color: Colors.amber,
                child: Column(
                  children: (_generatedNotes!['key_points'] as List)
                      .map((p) => _buildBulletItem(p.toString(), textColor))
                      .toList(),
                ),
              ),
              const SizedBox(height: 12),

              // Detailed Notes
              _buildNotesSection(
                isDark: isDark,
                icon: Icons.notes_outlined,
                title: 'Detailed Notes',
                color: const Color(0xFF7C4DFF),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children:
                      (_generatedNotes!['detailed_notes'] as List).map((s) {
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 14),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            s['heading'] ?? '',
                            style: TextStyle(
                                color: textColor,
                                fontWeight: FontWeight.bold,
                                fontSize: 14),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            s['content'] ?? '',
                            style: TextStyle(
                                color: textColor.withValues(alpha: 0.7),
                                fontSize: 13,
                                height: 1.5),
                          ),
                        ],
                      ),
                    );
                  }).toList(),
                ),
              ),
              const SizedBox(height: 12),

              // Key Terms
              _buildNotesSection(
                isDark: isDark,
                icon: Icons.book_outlined,
                title: 'Key Terms',
                color: Colors.teal,
                child: Column(
                  children: (_generatedNotes!['key_terms'] as List).map((t) {
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: Colors.teal.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(t['term'] ?? '',
                                style: const TextStyle(
                                    color: Colors.teal,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 12)),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              t['definition'] ?? '',
                              style: TextStyle(
                                  color: textColor.withValues(alpha: 0.7),
                                  fontSize: 13),
                            ),
                          ),
                        ],
                      ),
                    );
                  }).toList(),
                ),
              ),
              const SizedBox(height: 12),

              // Takeaways
              _buildNotesSection(
                isDark: isDark,
                icon: Icons.emoji_events_outlined,
                title: 'Key Takeaways',
                color: Colors.green,
                child: Column(
                  children: (_generatedNotes!['takeaways'] as List)
                      .map((t) => _buildBulletItem(t.toString(), textColor,
                          color: Colors.green))
                      .toList(),
                ),
              ),
              const SizedBox(height: 32),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildBulletItem(String text, Color textColor, {Color? color}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            margin: const EdgeInsets.only(top: 6),
            width: 6,
            height: 6,
            decoration: BoxDecoration(
              color: color ?? const Color(0xFF7C4DFF),
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(text,
                style: TextStyle(
                    color: textColor.withValues(alpha: 0.8),
                    fontSize: 13,
                    height: 1.5)),
          ),
        ],
      ),
    );
  }

  Widget _buildNotesSection({
    required bool isDark,
    required IconData icon,
    required String title,
    required Color color,
    required Widget child,
  }) {
    return _buildNeuCard(
      isDark: isDark,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: color, size: 18),
              const SizedBox(width: 8),
              Text(title,
                  style: TextStyle(
                      color: _t.textPrimary,
                      fontSize: 15,
                      fontWeight: FontWeight.bold)),
            ],
          ),
          const SizedBox(height: 12),
          child,
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

  @override
  void dispose() {
    _urlCtrl.dispose();
    _titleCtrl.dispose();
    super.dispose();
  }
}
