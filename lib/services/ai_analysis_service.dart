import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter/foundation.dart';
import '../config.dart';
import '../utils/date_formatter.dart';

class AIAnalysisService {
  final String baseUrl = 'https://openrouter.ai/api/v1/chat/completions';
  static const String model = 'deepseek/deepseek-r1-0528:free';

  Future<Map<String, dynamic>> analyzeTranscription(
    String transcription, {
    required DateTime today,
  }) async {
    try {
      // Validate input
      if (transcription.isEmpty) {
        debugPrint('❌ Empty transcription provided to AIAnalysisService');
        return {'notes': [], 'tasks': []};
      }

      final todayIso = _toIsoDate(today);

      debugPrint('🤖 OpenRouter ($model): Starting analysis...');
      debugPrint(
          '📝 Input text: "${transcription.substring(0, transcription.length > 100 ? 100 : transcription.length)}..."');

      final requestBody = {
        'model': model,
        'messages': [
          {
            'role': 'user',
            'content': 'You analyze transcribed speech into notes and tasks.\n\n'
                'Reference date (today, local device date): $todayIso.\n\n'
                'Return STRICT JSON only with this schema:\n'
                '{\n'
                '  "notes": ["string"],\n'
                '  "tasks": [\n'
                '    {\n'
                '      "text": "string",\n'
                '      "scheduledDate": "YYYY-MM-DD or null",\n'
                '      "scheduledTime": "HH:mm or h:mm AM/PM or null"\n'
                '    }\n'
                '  ]\n'
                '}\n\n'
                'Rules:\n'
                '1) NOTES: non-actionable reflections, observations, journal-like statements, or general information.\n'
                '2) TASKS: actionable intentions, commitments, goals, or plans. If the speaker expresses a need, obligation, or intent to do something (e.g., "I need to", "I must", "I will", "plan to", "should prepare"), it is a TASK.\n'
                '3) Task "text" must be clean and should NOT include temporal phrases such as tomorrow, next week, next Monday, in 3 days, at 3pm.\n'
                '4) Detect and resolve date/time expressions into metadata fields.\n'
                '5) Support explicit dates (25th February, Feb 25, 2026), relative dates (tomorrow, day after tomorrow, next Monday, this Friday, in 3 days, next week), and time expressions (at 3pm, 15:00, in the morning).\n'
                '6) If a TASK mentions a date/time, ALWAYS resolve it into scheduledDate/scheduledTime. Otherwise set them to null.\n'
                '7) Use the provided reference date for resolving relative dates like "tomorrow" or "next Monday".\n\n'
                'Transcription:\n'
                '"$transcription"'
          }
        ],
        'temperature': 0.1, // Lower temperature for more consistent JSON extraction
        'max_tokens': 1024,
      };

      debugPrint('🌐 OpenRouter: Making API request...');

      final response = await http
          .post(
        Uri.parse(baseUrl),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer ${Config.openRouterAPIKey}',
          'HTTP-Referer': 'https://noteable.app', // Optional: for analytics
          'X-Title': 'Noteable App', // Optional: for analytics
        },
        body: json.encode(requestBody),
      )
          .timeout(
        const Duration(seconds: 60),
        onTimeout: () {
          throw Exception('OpenRouter request timed out after 60 seconds');
        },
      );

      debugPrint('📡 OpenRouter: Response status: ${response.statusCode}');

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        debugPrint('📦 OpenRouter: Raw response: ${json.encode(data)}');

        if (data['choices'] == null || data['choices'].isEmpty) {
          throw Exception('No choices in response from OpenRouter API');
        }

        final content = data['choices'][0]['message']['content'];
        debugPrint('💬 OpenRouter: Content to parse: $content');

        if (content == null || content.toString().trim().isEmpty) {
          throw Exception('Empty content in response from OpenRouter API');
        }

        final parsedJson = _decodeResponseJson(content.toString().trim());
        final normalizedResult = _normalizeResult(
          parsedJson,
          fallbackText: transcription,
        );

        debugPrint(
          '📊 OpenRouter: Final result - Notes: ${normalizedResult['notes']?.length ?? 0}, Tasks: ${normalizedResult['tasks']?.length ?? 0}',
        );

        return normalizedResult;
      } else {
        debugPrint('❌ OpenRouter: API error - Status: ${response.statusCode}');
        debugPrint('❌ OpenRouter: Error response: ${response.body}');

        // Try to parse error details
        String errorMessage = 'HTTP ${response.statusCode}';
        try {
          final errorData = json.decode(response.body);
          if (errorData['error'] != null) {
            errorMessage = errorData['error']['message'] ?? errorMessage;
          }
        } catch (e) {
          // Use generic error message if can't parse
        }

        throw Exception(
            'OpenRouter API error: $errorMessage (Status: ${response.statusCode})');
      }
    } catch (e) {
      debugPrint('❌ OpenRouter: Exception occurred: $e');

      // Create a fallback result with the raw transcription as a note
      if (transcription.isNotEmpty) {
        return {
          'notes': ['Recorded: $transcription'],
          'tasks': []
        };
      }

      // Return empty result if we can't do anything else
      return {'notes': [], 'tasks': []};
    }
  }

  String _toIsoDate(DateTime date) {
    final normalized = DateTime(date.year, date.month, date.day);
    final month = normalized.month.toString().padLeft(2, '0');
    final day = normalized.day.toString().padLeft(2, '0');
    return '${normalized.year}-$month-$day';
  }

  Map<String, dynamic> _decodeResponseJson(String content) {
    try {
      final decoded = json.decode(content);
      if (decoded is Map<String, dynamic>) {
        return decoded;
      }
      return {};
    } catch (_) {
      final extracted = _extractJsonBlock(content);
      if (extracted == null) {
        return {
          'notes': [content.trim()],
          'tasks': [],
        };
      }

      try {
        final decoded = json.decode(extracted);
        if (decoded is Map<String, dynamic>) {
          return decoded;
        }
      } catch (error) {
        debugPrint('❌ Failed to parse extracted AI JSON: $error');
      }

      return {
        'notes': [content.trim()],
        'tasks': [],
      };
    }
  }

  String? _extractJsonBlock(String content) {
    final fencedMatch =
        RegExp(r'```(?:json)?\s*([\s\S]*?)```', caseSensitive: false)
            .firstMatch(content);
    if (fencedMatch != null) {
      return fencedMatch.group(1)?.trim();
    }

    final start = content.indexOf('{');
    final end = content.lastIndexOf('}');
    if (start == -1 || end == -1 || end <= start) {
      return null;
    }

    return content.substring(start, end + 1);
  }

  Map<String, dynamic> _normalizeResult(
    Map<String, dynamic> rawResult, {
    required String fallbackText,
  }) {
    final notes = <String>[];
    final tasks = <Map<String, dynamic>>[];

    if (rawResult['notes'] is List) {
      for (final note in rawResult['notes'] as List) {
        final noteText = note?.toString().trim() ?? '';
        if (noteText.isNotEmpty) {
          notes.add(noteText);
        }
      }
    }

    if (rawResult['tasks'] is List) {
      for (final item in rawResult['tasks'] as List) {
        if (item is String) {
          final text = item.trim();
          if (text.isNotEmpty) {
            tasks.add({
              'text': text,
              'scheduledDate': null,
              'scheduledTime': null,
            });
          }
          continue;
        }

        if (item is! Map) {
          continue;
        }

        final rawText =
            (item['text'] ?? item['task'] ?? item['content'])?.toString() ?? '';
        final text = rawText.trim();
        if (text.isEmpty) {
          continue;
        }

        final scheduledDate = _validatedScheduledDate(item['scheduledDate']);
        final rawScheduledTime = item['scheduledTime'];
        final scheduledTime =
            DateFormatter.normalizeScheduledTime(rawScheduledTime);
        if (rawScheduledTime != null &&
            rawScheduledTime.toString().trim().isNotEmpty &&
            scheduledTime == null) {
          debugPrint(
              '⚠️ AI scheduledTime is invalid and will be ignored: $rawScheduledTime');
        }

        tasks.add({
          'text': text,
          'scheduledDate': scheduledDate,
          'scheduledTime': scheduledTime,
        });
      }
    }

    if (notes.isEmpty && tasks.isEmpty && fallbackText.trim().isNotEmpty) {
      notes.add('Recorded: ${fallbackText.trim()}');
    }

    return {
      'notes': notes,
      'tasks': tasks,
    };
  }

  String? _validatedScheduledDate(dynamic rawDate) {
    if (rawDate == null) return null;

    final dateString = rawDate.toString().trim();
    if (dateString.isEmpty) return null;

    final isoMatch = RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(dateString);
    if (!isoMatch) {
      debugPrint('⚠️ AI scheduledDate is not ISO yyyy-MM-dd: $dateString');
      return null;
    }

    final parsed = DateTime.tryParse(dateString);
    if (parsed == null) {
      debugPrint('⚠️ Failed to parse AI scheduledDate: $dateString');
      return null;
    }

    final month = parsed.month.toString().padLeft(2, '0');
    final day = parsed.day.toString().padLeft(2, '0');
    return '${parsed.year}-$month-$day';
  }
}
