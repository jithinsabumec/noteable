import 'dart:convert';
import 'package:http/http.dart' as http;
import '../config.dart';

class DeepseekService {
  final String baseUrl = 'https://api.deepseek.com/chat/completions';

  Future<Map<String, dynamic>> analyzeTranscription(
      String transcription) async {
    try {
      final response = await http.post(
        Uri.parse(baseUrl),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer ${Config.deepseekAPIKey}',
        },
        body: json.encode({
          'model': 'deepseek-chat',
          'messages': [
            {
              'role': 'system',
              'content': 'You are an advanced assistant that analyzes transcribed speech and extracts two types of information: notes and tasks.\n\n'
                  'NOTES: Any general information, thoughts, reflections, or journaling content that is not an explicit task.\n\n'
                  'TASKS: Explicit to-do items or things the user clearly intends to accomplish. Only include as tasks things that are clearly actionable and the user intends to do.\n\n'
                  'Return a JSON with "notes" and "tasks" arrays. If there are no notes or tasks, return an empty array for that category.'
            },
            {
              'role': 'user',
              'content':
                  'Analyze this transcribed speech and extract notes and tasks. Be thorough and make sure every important piece of information is captured either as a note or task: "$transcription"'
            }
          ],
          'response_format': {'type': 'json_object'}
        }),
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final content = data['choices'][0]['message']['content'];
        final result = json.decode(content);

        // Make sure the result has the correct structure
        if (!result.containsKey('notes')) {
          result['notes'] = [];
        }
        if (!result.containsKey('tasks')) {
          result['tasks'] = [];
        }

        return result;
      } else {
        throw Exception(
            'Failed to analyze text: ${response.statusCode}, ${response.body}');
      }
    } catch (e) {
      print('Error analyzing transcription: $e');
      return {'notes': [], 'tasks': []};
    }
  }
}
