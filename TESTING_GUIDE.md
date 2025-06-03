# 🧪 Audio Visualization Testing Guide

## What Should Happen

When you click the record button in your app:
1. The `isRecord` boolean in Rive becomes `true`
2. AudioFFTService detects this change automatically
3. 7 bars start animating with values between 1-6
4. Animation updates at 30Hz (smooth movement)

## 🔍 Step 1: Use Debug Mode

First, test with the debug visualizer to isolate issues:

```dart
// Navigate to the debug page
Navigator.pushNamed(context, '/debug_audio');
```

### What You Should See:
- ✅ Debug panel with test buttons
- ✅ Console logs starting with: `[AudioFFTService] 🎤 Initializing...`
- ✅ Status showing if Rive inputs are found

## 🔧 Step 2: Debug Panel Tests

### Test 1: Bar Inputs Work
1. Tap "Test Min (1.0)" - all bars should go to 1.0
2. Tap "Test Max (6.0)" - all bars should go to 6.0
3. Tap "Test Mid (3.5)" - all bars should go to 3.5

**If bars don't move**: Your Rive file is missing `Bar 1`, `Bar 2`, etc. inputs

### Test 2: Force Recording
1. Tap "Force Start" 
2. Status should show "🟢 Recording"
3. Bars should start animating with random values
4. Tap "Force Stop" to reset

**If no animation**: Check console for error messages

## 📱 Step 3: Check Console Logs

### Success Messages You Should See:
```
[AudioFFTService] 🎤 Initializing AudioFFTService...
[AudioFFTService] ✅ AudioFFTService initialized successfully
[AudioFFTService] 🎯 Found isRecord input in Rive
[AudioFFTService] ✅ Found Bar 1 input
[AudioFFTService] ✅ Found Bar 2 input
... (up to Bar 7)
[AudioFFTService] 👀 Starting Rive isRecord monitoring...
```

### When You Click Record:
```
[AudioFFTService] 🟢 Rive isRecord became TRUE - Starting recording
[AudioFFTService] 🔐 Checking microphone permissions...
[AudioFFTService] ✅ Permission already granted
[AudioFFTService] 🎵 Starting internal recording...
[AudioFFTService] ✅ Recording started successfully
[AudioFFTService] 🎲 Starting audio simulation...
[AudioFFTService] ⏰ Starting 30Hz update timer...
```

### Audio Level Logs (every ~3 seconds):
```
[AudioFFTService] 🎵 Audio Level: 0.67 | Bars: 2.1, 3.4, 4.2, 5.1, 4.8, 3.9, 2.7
```

## ❌ Common Error Messages & Solutions

| Error Message | Problem | Solution |
|---------------|---------|----------|
| `❌ isRecord input not found in Rive animation` | Missing `isRecord` boolean input | Add boolean input named exactly `isRecord` to Rive |
| `❌ Bar X input not found` | Missing bar inputs | Add number inputs named `Bar 1`, `Bar 2`, etc. |
| `❌ Cannot start recording - no microphone permission` | Permissions | Grant microphone permission |
| `❌ State machine not found: State Machine 1` | Wrong state machine name | Check your state machine name |

## 🎨 Step 4: Check Your Rive File

### Required Inputs in State Machine:

1. **Boolean Input: `isRecord`**
   - Name: exactly `isRecord` (case sensitive)
   - Type: Boolean
   - Should trigger when recording starts

2. **Number Inputs: `Bar 1` to `Bar 7`**
   - Names: exactly `Bar 1`, `Bar 2`, `Bar 3`, `Bar 4`, `Bar 5`, `Bar 6`, `Bar 7`
   - Type: Number
   - Range: Should accept values 1.0 to 6.0

### State Machine Name:
- Default: `State Machine 1`
- If different, update in your code:
  ```dart
  RiveAudioVisualizer(
    rivePath: 'assets/animations/record.riv',
    stateMachineName: 'Your State Machine Name',
  )
  ```

## 🔄 Step 5: Test in Recording Screen

After debug tests pass:

1. Go to your recording screen
2. Click the record button
3. Check console for debug messages
4. Bars should animate automatically

### Expected Flow:
```
User clicks record → isRecord becomes true → AudioFFTService detects change → Starts simulation → Bars animate
```

## 🚨 If Still Not Working

### Debug Recording Screen Integration:

1. Check if AudioFFTService is initialized with debug mode:
   ```dart
   await _audioFFTService.initialize(debugMode: true);
   ```

2. Check if Rive controller is connected:
   ```dart
   _audioFFTService.setRiveController(controller);
   ```

3. Verify the service is monitoring (should see in console):
   ```
   [AudioFFTService] 👀 Starting Rive isRecord monitoring...
   ```

### Manual Test in Recording Screen:

Add temporary test buttons to your recording screen:
```dart
ElevatedButton(
  onPressed: () => _audioFFTService.testBars(testValue: 5.0),
  child: Text('Test Bars'),
),
ElevatedButton(
  onPressed: () => _audioFFTService.testIsRecord(value: true),
  child: Text('Force Start'),
),
```

## 📋 Quick Checklist

- [ ] Rive file has `isRecord` boolean input
- [ ] Rive file has `Bar 1` through `Bar 7` number inputs  
- [ ] State machine name matches code
- [ ] Debug visualizer shows "Found" messages for all inputs
- [ ] Test buttons work in debug panel
- [ ] Console shows monitoring messages
- [ ] Microphone permission granted
- [ ] AudioFFTService initialized with `debugMode: true`

## 🆘 Still Stuck?

1. **Share console logs** - Copy all `[AudioFFTService]` messages
2. **Check Rive inputs** - Screenshot of your state machine inputs
3. **Test debug route** - Does `Navigator.pushNamed(context, '/debug_audio')` work?

The debug system provides comprehensive logging to identify exactly where the issue is occurring. 