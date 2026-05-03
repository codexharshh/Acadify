import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter/services.dart';
import '../Services/theme_provider.dart';
import '../Services/ai_service.dart';

class AITestGeneratorPage extends StatefulWidget {
  const AITestGeneratorPage({super.key});

  @override
  State<AITestGeneratorPage> createState() => _AITestGeneratorPageState();
}

class _AITestGeneratorPageState extends State<AITestGeneratorPage> {
  final _topicCtrl = TextEditingController();
  final _gradeCtrl = TextEditingController();

  String _questionType = 'Mixed';
  String _difficulty = 'Medium';
  double _numQuestions = 10;

  bool _isGenerating = false;
  String? _errorMessage;
  Map<String, dynamic>? _generatedTest;

  final _questionTypes = ['MCQ', 'Short Answer', 'Long Answer', 'Mixed'];
  final _difficulties = ['Easy', 'Medium', 'Hard'];

  @override
  void dispose() {
    _topicCtrl.dispose();
    _gradeCtrl.dispose();
    super.dispose();
  }

  Color _difficultyColor(String d) {
    switch (d) {
      case 'Easy':
        return const Color(0xFF4CAF50);
      case 'Hard':
        return const Color(0xFFFF6B6B);
      default:
        return const Color(0xFFFF9800);
    }
  }

  // ── Generate ────────────────────────────────────────────────────────────────
  Future<void> _generateTest() async {
    if (_topicCtrl.text.trim().isEmpty) {
      setState(() => _errorMessage = 'Please enter a topic.');
      return;
    }
    setState(() {
      _isGenerating = true;
      _errorMessage = null;
      _generatedTest = null;
    });
    try {
      final result = await _callAI();
      setState(() {
        _generatedTest = result;
        _isGenerating = false;
      });
    } catch (e) {
      setState(() {
        _errorMessage = 'Error: $e';
        _isGenerating = false;
      });
    }
  }

  // ── Section counts ──────────────────────────────────────────────────────────
  Map<String, int> _sectionCounts() {
    final n = _numQuestions.toInt();
    switch (_questionType) {
      case 'MCQ':
        return {'MCQ': n, 'Short Answer': 0, 'Long Answer': 0};
      case 'Short Answer':
        return {'MCQ': 0, 'Short Answer': n, 'Long Answer': 0};
      case 'Long Answer':
        return {'MCQ': 0, 'Short Answer': 0, 'Long Answer': n};
      case 'Mixed':
      default:
        final each = n ~/ 3;
        final extra = n % 3;
        return {
          'MCQ': each + (extra > 0 ? 1 : 0),
          'Short Answer': each + (extra > 1 ? 1 : 0),
          'Long Answer': each,
        };
    }
  }

  int _tokensPerQuestion(String sectionType) {
    if (sectionType == 'Long Answer') return 250;
    if (sectionType == 'Short Answer') return 180;
    return 150;
  }

  static const _chunkSize = 3;

  // ── Sanitize raw JSON ───────────────────────────────────────────────────────
  String _sanitizeRaw(String raw) {
    String cleaned = raw
        .replaceAll(RegExp(r'```json\s*'), '')
        .replaceAll(RegExp(r'```\s*'), '')
        .replaceAll('\t', ' ')
        .trim();

    final arrStart = cleaned.indexOf('[');
    if (arrStart != -1) cleaned = cleaned.substring(arrStart);
    final arrEnd = cleaned.lastIndexOf(']');
    if (arrEnd != -1) cleaned = cleaned.substring(0, arrEnd + 1);

    cleaned = cleaned.replaceAll(RegExp(r',\s*([\]}])'), r'$1');

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
    return buf.toString();
  }

  // ── Repair truncated JSON array ─────────────────────────────────────────────
  String _repairTruncatedArray(String raw) {
    final arrStart = raw.indexOf('[');
    if (arrStart == -1) return raw;
    final String s = raw.substring(arrStart).trim();
    if (s.endsWith(']')) return s;

    final complete = <String>[];
    int depth = 0;
    int objStart = -1;
    bool inStr = false, esc = false;

    for (int i = 0; i < s.length; i++) {
      final ch = s[i];
      if (esc) {
        esc = false;
        continue;
      }
      if (ch == '\\' && inStr) {
        esc = true;
        continue;
      }
      if (ch == '"') {
        inStr = !inStr;
        continue;
      }
      if (inStr) continue;
      if (ch == '{') {
        if (depth == 0) objStart = i;
        depth++;
      } else if (ch == '}') {
        depth--;
        if (depth == 0 && objStart != -1) {
          complete.add(s.substring(objStart, i + 1));
          objStart = -1;
        }
      }
    }

    if (complete.isEmpty) return s;
    return '[${complete.join(',')}]';
  }

  // ── Parse AI array ──────────────────────────────────────────────────────────
  List<dynamic> _parseArray(String raw, String sectionType) {
    final sanitized = _sanitizeRaw(raw);
    try {
      return jsonDecode(sanitized) as List;
    } catch (_) {}

    final repaired = _repairTruncatedArray(sanitized);
    try {
      return jsonDecode(repaired) as List;
    } catch (_) {}

    final repairedRaw = _repairTruncatedArray(raw);
    try {
      return jsonDecode(_sanitizeRaw(repairedRaw)) as List;
    } catch (e) {
      throw 'Failed to parse $sectionType questions: $e\n'
          'Raw: ${raw.length > 300 ? raw.substring(0, 300) : raw}';
    }
  }

  // ── Generate a chunk of questions ──────────────────────────────────────────
  Future<List<dynamic>> _generateChunk({
    required String sectionType,
    required int count,
    required String topic,
    required String grade,
    required int startNo,
    List<String> previousQuestions = const [],
  }) async {
    final avoidHint = previousQuestions.isNotEmpty
        ? 'Do NOT repeat these already-used questions:\n'
            '${previousQuestions.take(10).map((q) => '- $q').join('\n')}\n'
            'All questions must be completely new and different.\n'
        : '';

    final String typeRules;
    final String exampleJson;

    if (sectionType == 'MCQ') {
      typeRules = 'Each question MUST:\n'
          '  - Be a complete, meaningful question ending with "?" (NOT a statement)\n'
          '  - Be specific (e.g. "What is the SI unit of force?" not "A man is walking")\n'
          '  - Have exactly 4 options: ["A) ...", "B) ...", "C) ...", "D) ..."]\n'
          '  - Have "answer" = exact text of the correct option\n'
          '  - Have "marks": 1\n'
          '  - Have "no" starting at $startNo';
      exampleJson =
          '[{"no":$startNo,"question":"What is the SI unit of force?","options":["A) Newton","B) Joule","C) Watt","D) Pascal"],"answer":"A) Newton","marks":1}]';
    } else if (sectionType == 'Short Answer') {
      typeRules = 'Each question MUST:\n'
          '  - Be a complete question ending with "?"\n'
          '  - Have "options": [] (empty)\n'
          '  - Have "answer" as a proper 1-2 sentence answer\n'
          '  - Have "marks": 3\n'
          '  - Have "no" starting at $startNo';
      exampleJson =
          '[{"no":$startNo,"question":"What is the difference between speed and velocity?","options":[],"answer":"Speed is the distance covered per unit time while velocity is displacement per unit time with a specific direction.","marks":3}]';
    } else {
      typeRules = 'Each question MUST:\n'
          '  - Be a complete, detailed question ending with "?"\n'
          '  - Require an explanation-type answer\n'
          '  - Have "options": [] (empty)\n'
          '  - Have "answer" as a complete 2-3 sentence explanation\n'
          '  - Have "marks": 5\n'
          '  - Have "no" starting at $startNo';
      exampleJson =
          '[{"no":$startNo,"question":"Explain the process of photosynthesis and its significance for life on Earth?","options":[],"answer":"Photosynthesis is the process by which green plants use sunlight, water, and CO2 to produce glucose and oxygen. It is the primary source of energy for almost all living organisms and maintains oxygen levels in the atmosphere.","marks":5}]';
    }

    final prompt =
        'Generate exactly $count $_difficulty $sectionType question(s) about: "$topic" for $grade students.\n'
        '$avoidHint'
        'Output ONLY a valid JSON array. No markdown, no code blocks, no extra text.\n'
        'Rules:\n'
        '$typeRules\n'
        '- No newlines inside any string value\n'
        '- Array must start with [ and end with ]\n'
        'Correct format example:\n'
        '$exampleJson';

    final maxTok = 500 + (count * _tokensPerQuestion(sectionType));
    final raw =
        await AiService.call(prompt, maxTokens: maxTok, temperature: 0.4);
    return _parseArray(raw, sectionType);
  }

  // ── Generate a full section in chunks ──────────────────────────────────────
  Future<List<dynamic>> _generateSection({
    required String sectionType,
    required int count,
    required String topic,
    required String grade,
    required int startNo,
  }) async {
    if (count == 0) return [];

    final allQuestions = <dynamic>[];
    final previousQuestions = <String>[];
    int currentNo = startNo;
    int remaining = count;

    while (remaining > 0) {
      final batch = remaining > _chunkSize ? _chunkSize : remaining;
      final questions = await _generateChunk(
        sectionType: sectionType,
        count: batch,
        topic: topic,
        grade: grade,
        startNo: currentNo,
        previousQuestions: previousQuestions,
      );
      for (final q in questions) {
        final qText = q['question']?.toString() ?? '';
        if (qText.isNotEmpty) previousQuestions.add(qText);
      }
      allQuestions.addAll(questions);
      currentNo += batch;
      remaining -= batch;
    }

    return allQuestions;
  }

  // ── Main AI call ────────────────────────────────────────────────────────────
  Future<Map<String, dynamic>> _callAI() async {
    final grade =
        _gradeCtrl.text.trim().isEmpty ? 'General' : _gradeCtrl.text.trim();
    final topic = _topicCtrl.text.trim();
    final counts = _sectionCounts();

    int qNo = 1;
    final sections = <Map<String, dynamic>>[];

    for (final entry in [
      {'type': 'MCQ', 'name': 'Section A - MCQ'},
      {'type': 'Short Answer', 'name': 'Section B - Short Answer'},
      {'type': 'Long Answer', 'name': 'Section C - Long Answer'},
    ]) {
      final type = entry['type']!;
      final count = counts[type] ?? 0;
      final questions = await _generateSection(
        sectionType: type,
        count: count,
        topic: topic,
        grade: grade,
        startNo: qNo,
      );
      sections
          .add({'name': entry['name']!, 'type': type, 'questions': questions});
      qNo += count;
    }

    final totalMarks = sections.fold<int>(0, (sum, s) {
      return sum +
          (s['questions'] as List).fold<int>(0, (qSum, q) {
            return qSum + ((q['marks'] ?? 0) as int);
          });
    });

    return {
      'title': 'Test on $topic',
      'class': grade,
      'difficulty': _difficulty,
      'duration': '60 minutes',
      'totalMarks': totalMarks,
      'sections': sections,
    };
  }

  // ── Copy test ───────────────────────────────────────────────────────────────
  void _copyTest() {
    if (_generatedTest == null) return;
    final b = StringBuffer();
    b.writeln(_generatedTest!['title']);
    b.writeln(
        'Class: ${_generatedTest!['class']} | Difficulty: ${_generatedTest!['difficulty']} | Duration: ${_generatedTest!['duration']}');
    b.writeln('Total Marks: ${_generatedTest!['totalMarks']}');
    b.writeln('');
    for (final section in (_generatedTest!['sections'] as List)) {
      b.writeln(section['name']);
      for (final q in (section['questions'] as List)) {
        b.writeln('Q${q['no']}. ${q['question']} [${q['marks']} mark(s)]');
        for (final o in ((q['options'] as List?) ?? [])) {
          b.writeln(' $o');
        }
        b.writeln('');
      }
    }
    b.writeln('── ANSWER KEY ──────────────────────────');
    int i = 1;
    for (final section in (_generatedTest!['sections'] as List)) {
      for (final q in (section['questions'] as List)) {
        b.writeln('Q$i. ${q['answer']}');
        i++;
      }
    }
    Clipboard.setData(ClipboardData(text: b.toString()));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Test copied to clipboard!'),
        backgroundColor: Color(0xFF7C4DFF),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  // ── BUILD ───────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final t = Provider.of<ThemeProvider>(context);
    return Scaffold(
      backgroundColor: t.bgColor,
      appBar: AppBar(
        title: const Text('AI Test Generator',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
        flexibleSpace: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              colors: [Color(0xFF6A1B9A), Color(0xFF9C27B0)],
            ),
          ),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 800),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _buildFormCard(t),
                if (_errorMessage != null) ...[
                  const SizedBox(height: 12),
                  _buildError(t),
                ],
                if (_isGenerating) ...[
                  const SizedBox(height: 40),
                  _buildLoading(t),
                ],
                if (_generatedTest != null) ...[
                  const SizedBox(height: 32),
                  _buildTestOutput(t),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ── Form card ───────────────────────────────────────────────────────────────
  Widget _buildFormCard(ThemeProvider t) {
    return Container(
      decoration: BoxDecoration(
        color: t.cardColor,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
              color: t.shadowDark, offset: const Offset(6, 6), blurRadius: 16),
          BoxShadow(
              color: t.shadowLight,
              offset: const Offset(-6, -6),
              blurRadius: 16),
        ],
      ),
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                      colors: [Color(0xFF6A1B9A), Color(0xFF9C27B0)]),
                  borderRadius: BorderRadius.circular(14),
                ),
                child:
                    const Icon(Icons.psychology, color: Colors.white, size: 24),
              ),
              const SizedBox(width: 14),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Generate Test Paper',
                      style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: t.textPrimary)),
                  Text('Fill in the details below',
                      style: TextStyle(fontSize: 13, color: t.textSecondary)),
                ],
              ),
            ],
          ),
          const SizedBox(height: 20),
          Divider(color: t.textSecondary.withValues(alpha: 0.15)),
          const SizedBox(height: 16),
          _label('Topic *', t),
          const SizedBox(height: 8),
          _inputField(
              controller: _topicCtrl,
              hint: 'e.g. Photosynthesis, World War II, Quadratic Equations',
              icon: Icons.lightbulb_outline,
              t: t),
          const SizedBox(height: 20),
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _label('Class / Grade', t),
                    const SizedBox(height: 8),
                    _inputField(
                        controller: _gradeCtrl,
                        hint: 'e.g. Class 10, BTech...',
                        icon: Icons.school_outlined,
                        t: t),
                  ],
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _label('Difficulty', t),
                    const SizedBox(height: 8),
                    Row(
                      children: _difficulties.map((d) {
                        final sel = _difficulty == d;
                        final color = _difficultyColor(d);
                        return Expanded(
                          child: GestureDetector(
                            onTap: () => setState(() => _difficulty = d),
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 180),
                              margin:
                                  EdgeInsets.only(right: d != 'Hard' ? 6 : 0),
                              padding: const EdgeInsets.symmetric(vertical: 10),
                              decoration: BoxDecoration(
                                color:
                                    sel ? color : color.withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                    color:
                                        color.withValues(alpha: sel ? 0 : 0.3)),
                                boxShadow: sel
                                    ? [
                                        BoxShadow(
                                            color:
                                                color.withValues(alpha: 0.35),
                                            blurRadius: 10,
                                            offset: const Offset(0, 4))
                                      ]
                                    : [],
                              ),
                              child: Text(d,
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                      color: sel ? Colors.white : color,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 12)),
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          _label('Question Type', t),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _questionTypes.map((qt) {
              final sel = _questionType == qt;
              return GestureDetector(
                onTap: () => setState(() => _questionType = qt),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  decoration: BoxDecoration(
                    color: sel
                        ? const Color(0xFF7C4DFF)
                        : const Color(0xFF7C4DFF).withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                        color: const Color(0xFF7C4DFF)
                            .withValues(alpha: sel ? 0 : 0.3)),
                    boxShadow: sel
                        ? [
                            BoxShadow(
                                color: const Color(0xFF7C4DFF)
                                    .withValues(alpha: 0.35),
                                blurRadius: 10,
                                offset: const Offset(0, 4))
                          ]
                        : [],
                  ),
                  child: Text(qt,
                      style: TextStyle(
                          color: sel ? Colors.white : const Color(0xFF7C4DFF),
                          fontWeight: FontWeight.bold,
                          fontSize: 13)),
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: 20),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _label('Number of Questions', t),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
                decoration: BoxDecoration(
                    color: const Color(0xFF7C4DFF).withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(20)),
                child: Text('${_numQuestions.toInt()}',
                    style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF7C4DFF),
                        fontSize: 15)),
              ),
            ],
          ),
          SliderTheme(
            data: SliderTheme.of(context).copyWith(
              activeTrackColor: const Color(0xFF7C4DFF),
              inactiveTrackColor:
                  const Color(0xFF7C4DFF).withValues(alpha: 0.15),
              thumbColor: const Color(0xFF7C4DFF),
              overlayColor: const Color(0xFF7C4DFF).withValues(alpha: 0.15),
              trackHeight: 4,
            ),
            child: Slider(
                value: _numQuestions,
                min: 5,
                max: 30,
                divisions: 25,
                onChanged: (v) => setState(() => _numQuestions = v)),
          ),
          const SizedBox(height: 24),
          GestureDetector(
            onTap: _isGenerating ? null : _generateTest,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 16),
              decoration: BoxDecoration(
                gradient: _isGenerating
                    ? LinearGradient(
                        colors: [Colors.grey.shade400, Colors.grey.shade500])
                    : const LinearGradient(
                        colors: [Color(0xFF6A1B9A), Color(0xFF9C27B0)]),
                borderRadius: BorderRadius.circular(16),
                boxShadow: _isGenerating
                    ? []
                    : [
                        BoxShadow(
                            color:
                                const Color(0xFF7C4DFF).withValues(alpha: 0.4),
                            blurRadius: 16,
                            offset: const Offset(0, 6))
                      ],
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.psychology_rounded,
                      color: Colors.white, size: 20),
                  const SizedBox(width: 10),
                  Text(
                    _isGenerating ? 'Generating...' : 'Generate Test',
                    style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 16),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Loading ─────────────────────────────────────────────────────────────────
  Widget _buildLoading(ThemeProvider t) {
    return Column(
      children: [
        const CircularProgressIndicator(color: Color(0xFF7C4DFF)),
        const SizedBox(height: 16),
        Text('Generating test on "${_topicCtrl.text}"...',
            style: TextStyle(color: t.textSecondary, fontSize: 14),
            textAlign: TextAlign.center),
      ],
    );
  }

  // ── Error ───────────────────────────────────────────────────────────────────
  Widget _buildError(ThemeProvider t) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.red.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.red.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          const Icon(Icons.error_outline, color: Colors.red),
          const SizedBox(width: 10),
          Expanded(
              child: Text(_errorMessage!,
                  style: const TextStyle(color: Colors.red))),
        ],
      ),
    );
  }

  // ── Test output ─────────────────────────────────────────────────────────────
  Widget _buildTestOutput(ThemeProvider t) {
    final test = _generatedTest!;
    final sections = test['sections'] as List;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: GestureDetector(
                onTap: _copyTest,
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 13),
                  decoration: BoxDecoration(
                    color: const Color(0xFF7C4DFF).withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                        color: const Color(0xFF7C4DFF).withValues(alpha: 0.4)),
                  ),
                  child: const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.copy, color: Color(0xFF7C4DFF), size: 18),
                      SizedBox(width: 8),
                      Text('Copy Test',
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
                onTap: _generateTest,
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 13),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                        colors: [Color(0xFF6A1B9A), Color(0xFF9C27B0)]),
                    borderRadius: BorderRadius.circular(12),
                    boxShadow: [
                      BoxShadow(
                          color: const Color(0xFF7C4DFF).withValues(alpha: 0.3),
                          blurRadius: 10,
                          offset: const Offset(0, 4))
                    ],
                  ),
                  child: const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.refresh, color: Colors.white, size: 18),
                      SizedBox(width: 8),
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
        const SizedBox(height: 20),
        Container(
          decoration: BoxDecoration(
            color: t.cardColor,
            borderRadius: BorderRadius.circular(24),
            boxShadow: [
              BoxShadow(
                  color: t.shadowDark,
                  offset: const Offset(6, 6),
                  blurRadius: 16),
              BoxShadow(
                  color: t.shadowLight,
                  offset: const Offset(-6, -6),
                  blurRadius: 16),
            ],
          ),
          padding: const EdgeInsets.all(28),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  gradient: LinearGradient(colors: [
                    const Color(0xFF6A1B9A).withValues(alpha: 0.1),
                    const Color(0xFF9C27B0).withValues(alpha: 0.05)
                  ]),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                      color: const Color(0xFF7C4DFF).withValues(alpha: 0.2)),
                ),
                child: Column(
                  children: [
                    Text(test['title'] ?? 'Test Paper',
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF7C4DFF))),
                    const SizedBox(height: 12),
                    Wrap(
                      alignment: WrapAlignment.center,
                      spacing: 12,
                      runSpacing: 8,
                      children: [
                        _infoChip(
                            t, Icons.school_outlined, test['class'] ?? ''),
                        _infoChip(t, Icons.bar_chart, test['difficulty'] ?? ''),
                        _infoChip(
                            t, Icons.timer_outlined, test['duration'] ?? ''),
                        _infoChip(t, Icons.stars_outlined,
                            'Total: ${test['totalMarks']} marks'),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 28),
              ...sections.map((s) => _buildSection(s, t)),
              Divider(
                  thickness: 2, color: t.textSecondary.withValues(alpha: 0.15)),
              const SizedBox(height: 16),
              _buildAnswerKey(sections, t),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildSection(dynamic section, ThemeProvider t) {
    final questions = section['questions'] as List;
    if (questions.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          margin: const EdgeInsets.only(bottom: 16),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
                colors: [Color(0xFF6A1B9A), Color(0xFF9C27B0)]),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Text(section['name'] ?? '',
              style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 14)),
        ),
        ...questions.map((q) {
          final opts = (q['options'] as List?) ?? [];
          return Padding(
            padding: const EdgeInsets.only(bottom: 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Q${q['no']}. ',
                        style: TextStyle(
                            fontWeight: FontWeight.bold, color: t.textPrimary)),
                    Expanded(
                        child: Text(q['question'] ?? '',
                            style:
                                TextStyle(fontSize: 14, color: t.textPrimary))),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                          color: const Color(0xFF7C4DFF).withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(8)),
                      child: Text('[${q['marks']} mark(s)]',
                          style: const TextStyle(
                              fontSize: 11,
                              color: Color(0xFF7C4DFF),
                              fontStyle: FontStyle.italic)),
                    ),
                  ],
                ),
                if (opts.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  ...opts.map((o) => Padding(
                        padding: const EdgeInsets.only(left: 24, bottom: 4),
                        child: Text(o.toString(),
                            style:
                                TextStyle(fontSize: 13, color: t.textPrimary)),
                      )),
                ],
                if (opts.isEmpty) ...[
                  const SizedBox(height: 8),
                  ...List.generate(
                    section['type'] == 'Long Answer' ? 4 : 2,
                    (_) => Container(
                        margin: const EdgeInsets.only(bottom: 8),
                        height: 1,
                        color: t.textSecondary.withValues(alpha: 0.2)),
                  ),
                ],
              ],
            ),
          );
        }),
        const SizedBox(height: 8),
      ],
    );
  }

  Widget _buildAnswerKey(List sections, ThemeProvider t) {
    int idx = 1;
    final items = <Widget>[];
    for (final section in sections) {
      for (final q in (section['questions'] as List)) {
        items.add(Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                  width: 32,
                  child: Text('Q$idx.',
                      style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 13,
                          color: t.textPrimary))),
              Expanded(
                  child: Text(q['answer'] ?? '',
                      style: TextStyle(fontSize: 13, color: t.textPrimary))),
            ],
          ),
        ));
        idx++;
      }
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(Icons.key, color: Color(0xFF7C4DFF), size: 20),
            const SizedBox(width: 8),
            Text('Answer Key',
                style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: t.textPrimary)),
          ],
        ),
        const SizedBox(height: 14),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: const Color(0xFF4CAF50).withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
                color: const Color(0xFF4CAF50).withValues(alpha: 0.25)),
          ),
          child: Column(
              crossAxisAlignment: CrossAxisAlignment.start, children: items),
        ),
      ],
    );
  }

  Widget _label(String text, ThemeProvider t) => Text(text,
      style: TextStyle(
          fontWeight: FontWeight.w600, fontSize: 13, color: t.textPrimary));

  Widget _inputField({
    required TextEditingController controller,
    required String hint,
    required IconData icon,
    required ThemeProvider t,
  }) =>
      Container(
        decoration: BoxDecoration(
          color: t.isDark
              ? Colors.white.withValues(alpha: 0.06)
              : Colors.black.withValues(alpha: 0.04),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
              color: const Color(0xFF7C4DFF).withValues(alpha: 0.25)),
        ),
        child: TextField(
          controller: controller,
          style: TextStyle(color: t.textPrimary),
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: TextStyle(color: t.textSecondary.withValues(alpha: 0.5)),
            prefixIcon: Icon(icon, color: const Color(0xFF7C4DFF), size: 20),
            border: InputBorder.none,
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          ),
        ),
      );

  Widget _infoChip(ThemeProvider t, IconData icon, String label) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
            color: const Color(0xFF7C4DFF).withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(20)),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 13, color: const Color(0xFF7C4DFF)),
            const SizedBox(width: 5),
            Text(label,
                style: const TextStyle(
                    fontSize: 12,
                    color: Color(0xFF7C4DFF),
                    fontWeight: FontWeight.w500)),
          ],
        ),
      );
}
