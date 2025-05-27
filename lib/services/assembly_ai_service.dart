import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:io';
import '../config.dart';

class AssemblyAIService {
  static const String _baseUrl = 'https://api.assemblyai.com/v2';

  // Upload audio file and get transcription
  Future<String> transcribeAudio(String filePath) async {
    try {
      print('Starting AssemblyAI transcription for: $filePath');

      // Step 1: Upload the audio file
      print('Step 1: Uploading audio file...');
      final uploadUrl = await _uploadAudioFile(filePath);
      print('Upload successful. URL: $uploadUrl');

      // Step 2: Request transcription
      print('Step 2: Requesting transcription...');
      final transcriptId = await _requestTranscription(uploadUrl);
      print('Transcription requested. ID: $transcriptId');

      // Step 3: Poll for completion and get result
      print('Step 3: Polling for completion...');
      final transcriptionText = await _getTranscriptionResult(transcriptId);
      print(
          'Transcription completed. Length: ${transcriptionText.length} characters');

      return transcriptionText;
    } catch (e) {
      print('AssemblyAI transcription error: $e');
      throw Exception('Failed to transcribe audio: $e');
    }
  }

  // Step 1: Upload audio file to AssemblyAI
  Future<String> _uploadAudioFile(String filePath) async {
    final file = File(filePath);
    if (!await file.exists()) {
      throw Exception('Audio file not found: $filePath');
    }

    final bytes = await file.readAsBytes();
    final fileSizeKB = (bytes.length / 1024).round();
    print(
        'Audio file details: Path=$filePath, Size=${fileSizeKB}KB, Format=${filePath.split('.').last}');

    final response = await http.post(
      Uri.parse('$_baseUrl/upload'),
      headers: {
        'authorization': Config.assemblyAIKey,
        'content-type': 'application/octet-stream',
      },
      body: bytes,
    );

    if (response.statusCode == 200) {
      final data = json.decode(response.body);
      print('Upload response: ${response.body}');
      return data['upload_url'];
    } else {
      print('Upload failed with status ${response.statusCode}');
      print('Upload error response: ${response.body}');
      throw Exception(
          'Failed to upload audio file: ${response.statusCode} - ${response.body}');
    }
  }

  // Step 2: Request transcription
  Future<String> _requestTranscription(String audioUrl) async {
    final response = await http.post(
      Uri.parse('$_baseUrl/transcript'),
      headers: {
        'authorization': Config.assemblyAIKey,
        'content-type': 'application/json',
      },
      body: json.encode({
        'audio_url': audioUrl,
        'language_detection': true, // Auto-detect language
      }),
    );

    if (response.statusCode == 200) {
      final data = json.decode(response.body);
      print('Transcription request response: ${response.body}');
      return data['id'];
    } else {
      print('Transcription request failed with status ${response.statusCode}');
      print('Transcription request error response: ${response.body}');
      throw Exception(
          'Failed to request transcription: ${response.statusCode} - ${response.body}');
    }
  }

  // Step 3: Poll for transcription completion
  Future<String> _getTranscriptionResult(String transcriptId) async {
    const maxAttempts = 60; // Maximum 5 minutes (60 * 5 seconds)
    int attempts = 0;

    while (attempts < maxAttempts) {
      final response = await http.get(
        Uri.parse('$_baseUrl/transcript/$transcriptId'),
        headers: {
          'authorization': Config.assemblyAIKey,
        },
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final status = data['status'];

        print('Polling attempt ${attempts + 1}: Status = $status');

        if (status == 'completed') {
          final text = data['text'] ?? '';
          print(
              'Transcription completed successfully. Text: ${text.substring(0, text.length > 100 ? 100 : text.length)}...');
          return text;
        } else if (status == 'error') {
          throw Exception('Transcription failed: ${data['error']}');
        }
        // If status is 'queued' or 'processing', continue polling
      } else {
        throw Exception(
            'Failed to get transcription result: ${response.statusCode} - ${response.body}');
      }

      // Wait 5 seconds before next attempt
      await Future.delayed(const Duration(seconds: 5));
      attempts++;
    }

    throw Exception('Transcription timed out after ${maxAttempts * 5} seconds');
  }
}
