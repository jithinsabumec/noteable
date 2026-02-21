import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter/foundation.dart';
import '../config.dart';

class AIAnalysisService {
  final String baseUrl = 'https://openrouter.ai/api/v1/chat/completions';
  static const String model = 'nvidia/nemotron-nano-12b-v2-vl:free';

  Future<Map<String, dynamic>> analyzeTranscription(
      String transcription) async {
    try {
      // Validate input
      if (transcription.isEmpty) {
        debugPrint('❌ Empty transcription provided to AIAnalysisService');
        return {'notes': [], 'tasks': []};
      }

      debugPrint('🤖 OpenRouter ($model): Starting analysis...');
      debugPrint(
          '📝 Input text: "${transcription.substring(0, transcription.length > 100 ? 100 : transcription.length)}..."');

      final requestBody = {
        'model': model,
        'messages': [
          {
            'role': 'user',
            'content':
                'You are an advanced assistant that analyzes transcribed speech and extracts two types of information: notes and tasks.\n\n'
                'NOTES: Any general information, thoughts, reflections, or journaling content that is not an explicit task.\n\n'
                'TASKS: Explicit to-do items or things the user clearly intends to accomplish. Only include as tasks things that are clearly actionable and the user intends to do.\n\n'
                'Return a JSON with "notes" and "tasks" arrays. If there are no notes or tasks, return an empty array for that category.\n\n'
                'Example response format:\n'
                '{"notes": ["I had a great meeting today"], "tasks": ["Call the client tomorrow", "Finish the report"]}\n\n'
                'Now analyze this transcribed speech and extract notes and tasks. Be thorough and make sure every important piece of information is captured either as a note or task: "$transcription"\n\n'
                'Respond with only the JSON object, no other text.'
          }
        ],
        'temperature': 0.7,
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
        const Duration(seconds: 30),
        onTimeout: () {
          throw Exception('OpenRouter request timed out after 30 seconds');
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

        // Try to parse JSON from the content
        Map<String, dynamic> result;
        try {
          // First try to parse the entire content as JSON
          result = json.decode(content);
        } catch (e) {
          debugPrint(
              '⚠️ Failed to parse full content as JSON, attempting to extract JSON...');

          // Try to find JSON within the content
          final jsonMatch = RegExp(r'\{[^{}]*"notes"[^{}]*"tasks"[^{}]*\}')
              .firstMatch(content);
          if (jsonMatch != null) {
            try {
              result = json.decode(jsonMatch.group(0)!);
            } catch (e2) {
              debugPrint('❌ Failed to parse extracted JSON: $e2');
              // Fallback: create a note from the raw content
              result = {
                'notes': [content.trim()],
                'tasks': []
              };
            }
          } else {
            debugPrint('⚠️ No JSON structure found, treating as note');
            // Fallback: create a note from the raw content
            result = {
              'notes': [content.trim()],
              'tasks': []
            };
          }
        }

        debugPrint('✅ OpenRouter: Parsed result: $result');

        // Make sure the result has the correct structure
        if (!result.containsKey('notes')) {
          result['notes'] = [];
        }
        if (!result.containsKey('tasks')) {
          result['tasks'] = [];
        }

        // Ensure arrays are lists of strings
        if (result['notes'] is! List) {
          result['notes'] = [];
        } else {
          // Filter out any empty notes
          result['notes'] = (result['notes'] as List)
              .where(
                  (note) => note != null && note.toString().trim().isNotEmpty)
              .map((note) => note.toString())
              .toList();
        }

        if (result['tasks'] is! List) {
          result['tasks'] = [];
        } else {
          // Filter out any empty tasks
          result['tasks'] = (result['tasks'] as List)
              .where(
                  (task) => task != null && task.toString().trim().isNotEmpty)
              .map((task) => task.toString())
              .toList();
        }

        // If both lists are empty but we had transcription, create a fallback note
        if (result['notes'].isEmpty &&
            result['tasks'].isEmpty &&
            transcription.isNotEmpty) {
          result['notes'] = ['Recorded: $transcription'];
        }

        debugPrint(
            '📊 OpenRouter: Final result - Notes: ${result['notes']?.length ?? 0}, Tasks: ${result['tasks']?.length ?? 0}');
        return result;
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
}
