import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import '../config.dart';

class AssemblyAIService {
  static const String _baseUrl = 'https://api.assemblyai.com/v2';

  // Upload audio file and get transcription
  Future<String> transcribeAudio(String filePath) async {
    try {
      debugPrint('Starting AssemblyAI transcription for: $filePath');

      // Verify file exists and is readable
      final file = File(filePath);
      if (!await file.exists()) {
        debugPrint('❌ Audio file not found at path: $filePath');
        throw Exception('Audio file not found: $filePath');
      }

      // Step 1: Upload the audio file
      debugPrint('Step 1: Uploading audio file...');
      final uploadUrl = await _uploadAudioFile(filePath);
      debugPrint('Upload successful. URL: $uploadUrl');

      // Step 2: Request transcription
      debugPrint('Step 2: Requesting transcription...');
      final transcriptId = await _requestTranscription(uploadUrl);
      debugPrint('Transcription requested. ID: $transcriptId');

      // Step 3: Poll for completion and get result
      debugPrint('Step 3: Polling for completion...');
      final transcriptionText = await _getTranscriptionResult(transcriptId);
      debugPrint(
          'Transcription completed. Length: ${transcriptionText.length} characters');

      return transcriptionText;
    } catch (e) {
      debugPrint('❌ AssemblyAI transcription error: $e');
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
    debugPrint(
        'Audio file details: Path=$filePath, Size=${fileSizeKB}KB, Format=${filePath.split('.').last}');

    try {
      final response = await http
          .post(
        Uri.parse('$_baseUrl/upload'),
        headers: {
          'authorization': Config.assemblyAIKey,
          'content-type': 'application/octet-stream',
        },
        body: bytes,
      )
          .timeout(
        const Duration(seconds: 30),
        onTimeout: () {
          throw Exception('Upload request timed out after 30 seconds');
        },
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        debugPrint('Upload response: ${response.body}');
        return data['upload_url'];
      } else {
        debugPrint('❌ Upload failed with status ${response.statusCode}');
        debugPrint('❌ Upload error response: ${response.body}');
        throw Exception(
            'Failed to upload audio file: ${response.statusCode} - ${response.body}');
      }
    } catch (e) {
      debugPrint('❌ Exception during upload: $e');
      throw Exception('Upload failed: $e');
    }
  }

  // Step 2: Request transcription
  Future<String> _requestTranscription(String audioUrl) async {
    try {
      final response = await http
          .post(
        Uri.parse('$_baseUrl/transcript'),
        headers: {
          'authorization': Config.assemblyAIKey,
          'content-type': 'application/json',
        },
        body: json.encode({
          'audio_url': audioUrl,
          'language_detection': true, // Auto-detect language
        }),
      )
          .timeout(
        const Duration(seconds: 30),
        onTimeout: () {
          throw Exception('Transcription request timed out after 30 seconds');
        },
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        debugPrint('Transcription request response: ${response.body}');
        return data['id'];
      } else {
        debugPrint(
            '❌ Transcription request failed with status ${response.statusCode}');
        debugPrint('❌ Transcription request error response: ${response.body}');
        throw Exception(
            'Failed to request transcription: ${response.statusCode} - ${response.body}');
      }
    } catch (e) {
      debugPrint('❌ Exception during transcription request: $e');
      throw Exception('Transcription request failed: $e');
    }
  }

  // Step 3: Poll for transcription completion
  Future<String> _getTranscriptionResult(String transcriptId) async {
    const maxAttempts = 60; // Maximum 5 minutes (60 * 5 seconds)
    int attempts = 0;

    while (attempts < maxAttempts) {
      try {
        final response = await http.get(
          Uri.parse('$_baseUrl/transcript/$transcriptId'),
          headers: {
            'authorization': Config.assemblyAIKey,
          },
        ).timeout(
          const Duration(seconds: 15),
          onTimeout: () {
            debugPrint('⚠️ Polling request timed out, will retry');
            return http.Response('{"status": "timeout"}', 408);
          },
        );

        if (response.statusCode == 200) {
          final data = json.decode(response.body);
          final status = data['status'];

          debugPrint('Polling attempt ${attempts + 1}: Status = $status');

          if (status == 'completed') {
            final text = data['text'] ?? '';
            if (text.isEmpty) {
              debugPrint('⚠️ Transcription completed but text is empty');
              return 'No speech detected. Please try again with a clearer recording.';
            }

            debugPrint(
                'Transcription completed successfully. Text: ${text.substring(0, text.length > 100 ? 100 : text.length)}...');
            return text;
          } else if (status == 'error') {
            throw Exception('Transcription failed: ${data['error']}');
          } else if (status == 'timeout') {
            debugPrint('⚠️ Polling timed out, retrying...');
            // Continue to next attempt
          }
          // If status is 'queued' or 'processing', continue polling
        } else {
          debugPrint(
              '⚠️ Polling failed with status ${response.statusCode}, retrying...');
          debugPrint('⚠️ Error response: ${response.body}');
          // Don't throw exception here, just retry
        }
      } catch (e) {
        debugPrint('⚠️ Exception during polling: $e');
        // Don't throw exception here, just retry
      }

      // Wait 5 seconds before next attempt
      await Future.delayed(const Duration(seconds: 5));
      attempts++;
    }

    throw Exception('Transcription timed out after ${maxAttempts * 5} seconds');
  }
}
