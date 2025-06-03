# Audio Visualization Integration with Rive Animation

This implementation provides a simplified audio visualization system that controls Rive animation bars with simulated frequency bands, demonstrating the concept without complex FFT processing.

## Overview

The system detects microphone permission/access and generates realistic frequency band simulations that control 7 bars in a Rive animation. Values are normalized to a 1-6 range and updated at 30Hz frequency.

## 🎯 Quick Start

1. **Your Rive file must have these inputs:**
   - `isRecord` (Boolean): When true, starts visualization
   - `Bar 1` through `Bar 7` (Number, range 1-6): Bar heights

2. **Test the system:**
   ```dart
   // Navigate to debug page
   Navigator.pushNamed(context, '/debug_audio');
   ```

3. **In your recording screen:**
   - When you click record, `isRecord` becomes true
   - Bars automatically start animating
   - Check console for debug logs

## Components

### 1. AudioFFTService (`lib/services/audio_fft_service.dart`)

A service class that handles:
- Microphone permission checking using existing `record` package
- Simulated frequency band generation for demonstration
- Rive animation bar control at 30Hz
- Realistic audio visualization patterns
- **Automatic Rive monitoring**: Listens to `isRecord` changes

#### Frequency Bands
The simulated audio spectrum is divided into 7 frequency bands with different response patterns:

1. **Bar 1**: Sub-bass simulation (lower response for speech)
2. **Bar 2**: Bass simulation (moderate response)  
3. **Bar 3**: Low midrange simulation (strong for speech)
4. **Bar 4**: Midrange simulation (very strong for speech)
5. **Bar 5**: Upper midrange simulation (strong for speech)
6. **Bar 6**: Presence simulation (moderate for speech)
7. **Bar 7**: Brilliance simulation (lower for normal speech)

#### Key Methods
- `initialize(debugMode: true)`: Initialize with debugging
- `setRiveController()`: Connect to Rive state machine (auto-starts monitoring)
- `testBars(testValue: 3.5)`: Test bar values directly
- `testIsRecord(value: true)`: Force start/stop recording
- `dispose()`: Clean up resources

### 2. RiveAudioVisualizer Widget (`lib/widgets/rive_audio_visualizer.dart`)

A comprehensive debug widget that:
- Loads and displays Rive animation
- Integrates with AudioFFTService
- **Full debug panel** with test controls
- Real-time frequency band display
- Debug log viewer

#### Usage
```dart
RiveAudioVisualizer(
  rivePath: 'assets/animations/record.riv',
  debugMode: true, // Shows debug controls
)
```

### 3. Updated Recording Screen (`lib/screens/recording_screen.dart`)

Enhanced recording screen that integrates the audio visualization alongside traditional audio recording.

## 🔧 Debug Features

### Debug Panel
The `RiveAudioVisualizer` includes a comprehensive debug panel:

- **Test Buttons**: Test min/mid/max bar values
- **Force Controls**: Manually start/stop recording
- **Real-time Status**: Shows recording state and audio levels
- **Frequency Display**: Live bar values
- **Debug Logs**: Real-time system messages

### Debug Route
Access the debug page directly:
```dart
Navigator.pushNamed(context, '/debug_audio');
```

### Console Logging
When `debugMode: true`, detailed logs show:
```
[AudioFFTService] 🎤 Initializing AudioFFTService...
[AudioFFTService] 🎯 Found isRecord input in Rive
[AudioFFTService] 👀 Starting Rive isRecord monitoring...
[AudioFFTService] 🟢 Rive isRecord became TRUE - Starting recording
[AudioFFTService] 🎵 Audio Level: 0.67 | Bars: 2.1, 3.4, 4.2, 5.1, 4.8, 3.9, 2.7
```

## Rive Animation Requirements

Your Rive animation must have:

### State Machine Variables
- `isRecord` (Boolean): Controls when visualization is active
- `Bar 1` through `Bar 7` (Number): Values from 1-6 representing frequency band intensities

### Example State Machine Setup
1. Create a state machine named "State Machine 1"
2. Add boolean input `isRecord`
3. Add number inputs `Bar 1`, `Bar 2`, ..., `Bar 7` with ranges 1-6
4. Connect these inputs to your visual elements (bar heights, colors, etc.)

## Dependencies

Uses existing dependencies in your project:
```yaml
dependencies:
  record: ^6.0.0
  permission_handler: ^11.3.0
  rive: ^0.13.20
```

## Permissions

### Android (`android/app/src/main/AndroidManifest.xml`)
```xml
<uses-permission android:name="android.permission.RECORD_AUDIO" />
```

### iOS (`ios/Runner/Info.plist`)
```xml
<key>NSMicrophoneUsageDescription</key>
<string>This app needs microphone access for audio visualization</string>
```

## Implementation Details

### Audio Simulation Pipeline
1. **Permission Check**: Verify microphone access using `record` package
2. **Rive Monitoring**: Check `isRecord` state every 50ms
3. **Level Generation**: Create random but realistic audio level variations
4. **Band Simulation**: Generate 7 frequency bands with speech-like characteristics
5. **Normalization**: Scale values to 1-6 range with frequency-specific modifiers
6. **Update**: Send values to Rive at 30Hz

### Simulation Features
- Realistic frequency response patterns for different bands
- Speech-optimized band characteristics
- Smooth value transitions
- Random but believable variations
- 30Hz update rate for smooth animation

## 🧪 Testing & Debugging

### Step-by-Step Testing

1. **Check Rive Setup:**
   ```dart
   // Use the debug visualizer
   Navigator.pushNamed(context, '/debug_audio');
   ```

2. **Verify Inputs:**
   - Debug panel shows "✅ Found isRecord input"
   - Debug panel shows "✅ Found Bar 1-7 inputs"

3. **Test Bar Response:**
   - Tap "Test Min (1.0)" - all bars should go to minimum
   - Tap "Test Max (6.0)" - all bars should go to maximum
   - Values should update in real-time

4. **Test Recording Flow:**
   - Tap "Force Start" - should see "🟢 Recording" status
   - Bars should animate with random values
   - Tap "Force Stop" - bars should return to 1.0

5. **Check in Recording Screen:**
   - Click record button in your app
   - Check console for debug messages
   - Bars should automatically start animating

### Common Issues & Solutions

| Issue | Debug Steps | Solution |
|-------|-------------|----------|
| Bars not moving | Check debug panel for missing inputs | Ensure Rive has `Bar 1-7` number inputs |
| No recording trigger | Check for `isRecord` input | Add boolean `isRecord` input to Rive |
| Permission errors | Check console logs | Add microphone permissions |
| No debug logs | Enable debug mode | Use `initialize(debugMode: true)` |

### Debug Console Messages

✅ **Success Messages:**
- `🎤 Initializing AudioFFTService...`
- `🎯 Found isRecord input in Rive`
- `✅ Found Bar X input`

❌ **Error Messages:**
- `❌ isRecord input not found in Rive animation`
- `❌ Bar X input not found`
- `❌ Cannot start recording - no microphone permission`

### Performance Monitoring

The debug system shows:
- **Audio Level**: Current simulated audio intensity (0.0-1.0)
- **Bar Values**: All 7 frequency bands (1.0-6.0)
- **Update Rate**: Should be ~30 updates per second
- **Memory**: Auto-cleans debug logs (keeps last 100)

## Integration with Existing Recording

The service integrates with your existing recording screen:
1. When `isRecord` becomes true in Rive, visualization starts
2. When recording stops, visualization stops
3. Bars return to minimum values (1.0) when not active

## Usage Example

```dart
class MyAudioVisualizerPage extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return RiveAudioVisualizer(
      rivePath: 'assets/animations/audio_bars.riv',
      stateMachineName: 'AudioViz',
      debugMode: true, // Enable full debugging
    );
  }
}
```

## Extending to Real FFT

To replace simulation with real audio analysis:
1. Add an FFT library like `fftea`
2. Replace `_simulateAudioLevel()` with real audio data processing
3. Add audio streaming capability
4. Implement real frequency band calculation
5. Keep the same Rive integration interface

## Architecture

```
┌─────────────────┐    ┌──────────────────┐    ┌─────────────────┐
│   Microphone    │───▶│  AudioFFTService │───▶│ Rive Animation  │
│   (Permission)  │    │   (Auto-Monitor) │    │  (7 Bars 1-6)   │
└─────────────────┘    └──────────────────┘    └─────────────────┘
                               │                        ▲
                               ▼                        │
                    ┌──────────────────┐                │
                    │ 7 Frequency Bands│     ┌──────────────────┐
                    │ (Simulated 1-6)  │────▶│  Debug Panel     │
                    └──────────────────┘     │  (Test Controls) │
                                             └──────────────────┘
```

This implementation provides a working foundation for audio visualization that can be easily extended with real FFT analysis when needed. 