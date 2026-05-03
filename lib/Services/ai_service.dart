import 'dart:convert';
import 'dart:async';
import 'package:http/http.dart' as http;

class AiService {
  static const _groqKey = String.fromEnvironment('GROQ_API_KEY');

  static const _groqUrl = 'https://api.groq.com/openai/v1/chat/completions';
  static const _primaryModel = 'llama-3.1-8b-instant';
  static const _fallbackModel = 'gemma2-9b-it';

  static Future<String> call(
    String prompt, {
    int maxTokens = 1500,
    double temperature = 0.7,
  }) async {
    // Safety check — key must be provided at build time.
    if (_groqKey.isEmpty) {
      throw 'GROQ_API_KEY is not set. '
          'Run with --dart-define=GROQ_API_KEY=your_key_here';
    }

    String model = _primaryModel;
    const maxRetries = 3;

    for (int attempt = 0; attempt <= maxRetries; attempt++) {
      final response = await http.post(
        Uri.parse(_groqUrl),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $_groqKey',
        },
        body: jsonEncode({
          'model': model,
          'max_tokens': maxTokens,
          'temperature': temperature,
          'messages': [
            {
              'role': 'system',
              'content': 'You are a helpful AI assistant for a student study app. '
                  'Always respond with valid JSON when asked. '
                  'Never include markdown code blocks or backticks. '
                  'Never use newlines inside JSON string values. '
                  'All property names and string values must be double-quoted. '
                  'Do not use trailing commas.',
            },
            {'role': 'user', 'content': prompt},
          ],
        }),
      );

      if (response.statusCode == 200) {
        final body = jsonDecode(response.body);
        String text =
            (body['choices'][0]['message']['content'] as String).trim();
        text = text
            .replaceAll(RegExp(r'```json\s*'), '')
            .replaceAll(RegExp(r'```\s*'), '')
            .trim();
        return text;
      }

      if (response.statusCode == 429) {
        // Rate limit hit — parse wait time from error message.
        int waitSeconds = 5 * (attempt + 1);
        try {
          final errBody = jsonDecode(response.body);
          final msg = errBody['error']['message'] as String? ?? '';
          final match =
              RegExp(r'try again in (\d+(?:\.\d+)?)s').firstMatch(msg);
          if (match != null) {
            waitSeconds = (double.parse(match.group(1)!) + 1).ceil();
          }
        } catch (_) {}

        // Switch to fallback model on second attempt.
        if (attempt == 1 && model == _primaryModel) {
          model = _fallbackModel;
          continue;
        }

        if (attempt < maxRetries) {
          await Future.delayed(Duration(seconds: waitSeconds));
          continue;
        }

        throw 'Rate limit reached. Please wait a moment and try again.';
      }

      throw 'AI error ${response.statusCode}: ${response.body}';
    }

    throw 'AI request failed after $maxRetries retries.';
  }

  static String _sanitizeJson(String raw) {
    final jsonStart = raw.indexOf('{');
    final jsonEnd = raw.lastIndexOf('}');
    if (jsonStart == -1 || jsonEnd == -1 || jsonEnd < jsonStart) return raw;
    String text = raw.substring(jsonStart, jsonEnd + 1);

    text = text.replaceAll(RegExp(r',\s*([}\]])'), r'$1');
    text = text.replaceAll('\t', ' ');

    final buffer = StringBuffer();
    bool inString = false;
    bool escaped = false;

    for (int i = 0; i < text.length; i++) {
      final ch = text[i];
      if (escaped) {
        buffer.write(ch);
        escaped = false;
        continue;
      }
      if (ch == '\\') {
        escaped = true;
        buffer.write(ch);
        continue;
      }
      if (ch == '"') {
        inString = !inString;
        buffer.write(ch);
        continue;
      }
      if (inString && ch == '\n') {
        buffer.write(r'\n');
        continue;
      }
      if (inString && ch == '\r') {
        continue;
      }
      buffer.write(ch);
    }

    return buffer.toString();
  }

  static Future<Map<String, dynamic>> callJson(
    String prompt, {
    int maxTokens = 2000,
  }) async {
    final text = await call(prompt, maxTokens: maxTokens, temperature: 0.3);

    // Attempt 1 — direct parse.
    try {
      return jsonDecode(text) as Map<String, dynamic>;
    } catch (_) {}

    // Attempt 2 — sanitize then parse.
    final sanitized = _sanitizeJson(text);
    try {
      return jsonDecode(sanitized) as Map<String, dynamic>;
    } catch (_) {}

    // Attempt 3 — extract JSON object boundaries then parse.
    final jsonStart = text.indexOf('{');
    final jsonEnd = text.lastIndexOf('}');
    if (jsonStart != -1 && jsonEnd != -1 && jsonEnd > jsonStart) {
      final extracted = text.substring(jsonStart, jsonEnd + 1);
      try {
        return jsonDecode(extracted) as Map<String, dynamic>;
      } catch (_) {}

      final sanitizedExtracted = _sanitizeJson(extracted);
      try {
        return jsonDecode(sanitizedExtracted) as Map<String, dynamic>;
      } catch (e) {
        throw 'FormatException: $e\n\nRaw AI output (first 500 chars):\n'
            '${text.length > 500 ? text.substring(0, 500) : text}';
      }
    }

    throw 'AI returned invalid JSON. Response: '
        '${text.length > 300 ? text.substring(0, 300) : text}';
  }
}
