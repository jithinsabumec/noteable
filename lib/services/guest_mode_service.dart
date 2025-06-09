import 'package:shared_preferences/shared_preferences.dart';

class GuestModeService {
  static const String _guestRecordingCountKey = 'guest_recording_count';
  static const int _maxGuestRecordings = 3;

  // Singleton pattern
  static final GuestModeService _instance = GuestModeService._internal();
  factory GuestModeService() => _instance;
  GuestModeService._internal();

  /// Get the current number of recordings used in guest mode
  Future<int> getRecordingCount() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getInt(_guestRecordingCountKey) ?? 0;
    } catch (e) {
      return 0;
    }
  }

  /// Increment the recording count (call when a recording is successfully processed)
  Future<bool> incrementRecordingCount() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final currentCount = await getRecordingCount();

      if (currentCount >= _maxGuestRecordings) {
        return false; // Already at max, don't increment
      }

      await prefs.setInt(_guestRecordingCountKey, currentCount + 1);
      return true;
    } catch (e) {
      return false;
    }
  }

  /// Check if the user can still record in guest mode
  Future<bool> canRecord() async {
    final currentCount = await getRecordingCount();
    return currentCount < _maxGuestRecordings;
  }

  /// Get how many recordings are left for guest mode
  Future<int> getRemainingRecordings() async {
    final currentCount = await getRecordingCount();
    return _maxGuestRecordings - currentCount;
  }

  /// Reset recording count (useful for testing or if user signs up)
  Future<void> resetRecordingCount() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_guestRecordingCountKey);
    } catch (e) {
      // Handle error silently
    }
  }

  /// Get maximum allowed recordings for guest mode
  int get maxRecordings => _maxGuestRecordings;
}
