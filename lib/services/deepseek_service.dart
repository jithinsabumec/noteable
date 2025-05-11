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
              'content':
                  'You are an assistant that analyzes transcribed text and extracts todos and ideas from it. Return a JSON with "todos" and "ideas" arrays. If there are no todos or ideas, return an empty array for that category.'
            },
            {
              'role': 'user',
              'content':
                  'Analyze this transcribed text and extract any todos and ideas: "$transcription"'
            }
          ],
          'response_format': {'type': 'json_object'}
        }),
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final content = data['choices'][0]['message']['content'];
        final result = json.decode(content);
        return result;
      } else {
        throw Exception(
            'Failed to analyze text: ${response.statusCode}, ${response.body}');
      }
    } catch (e) {
      print('Error analyzing transcription: $e');
      return {'todos': [], 'ideas': []};
    }
  }
}
