import 'dart:async';
import 'dart:io' as io;
import 'dart:math' as math;

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:record/record.dart';
import 'package:rive/rive.dart';

import '../models/timeline_models.dart';
import '../services/ai_analysis_service.dart';
import '../services/assembly_ai_service.dart';
import '../services/guest_mode_service.dart';
import '../services/item_management_service.dart';
import '../services/purchase_service.dart';
import '../widgets/bottom_sheets/add_item_bottom_sheet.dart';

class RiveAnimationWidget extends StatefulWidget {
  final Map<String, List<TimelineEntry>> timelineEntriesByDate;
  final DateTime selectedDate;
  final Function() onStateUpdate;
  final bool isGuestMode;
  final GuestModeService? guestModeService;
  final VoidCallback? onGuestRecordingCountUpdate;
  /// Called when guest hits recording limit - show paywall/subscription screen
  final VoidCallback? onShowPaywall;

  const RiveAnimationWidget({
    super.key,
    required this.timelineEntriesByDate,
    required this.selectedDate,
    required this.onStateUpdate,
    this.isGuestMode = false,
    this.guestModeService,
    this.onGuestRecordingCountUpdate,
    this.onShowPaywall,
  });

  @override
  State<RiveAnimationWidget> createState() => _RiveAnimationWidgetState();
}

class _RiveAnimationWidgetState extends State<RiveAnimationWidget> {
  // Rive runtime state
  FileLoader? _fileLoader;
  RiveWidgetController? _riveWidgetController;
  StateMachine? controller;
  ViewModelInstance? _viewModelInstance;
  int _riveRebuildNonce = 0;

  // Audio services
  // AudioRecorder is recreated for every recording cycle to prevent the
  // underlying recorder from getting stuck after the first use on some
  // devices.
  AudioRecorder _audioRecorder = AudioRecorder();
  final _assemblyAIService = AssemblyAIService();
  final _aiAnalysisService = AIAnalysisService();
  final _itemManagementService = ItemManagementService();
  final _purchaseService = PurchaseService();

  // Recording state
  bool _isRecording = false;
  String? _recordedFilePath;
  DateTime? _recordingStartTime;
  bool _isStartingRecording = false;
  bool _isStoppingRecording = false;
  bool _hasSubmitIntent = false;
  bool _isSubmitFlowActive = false;

  // Processing states
  bool _isTranscribing = false;
  bool _isAnalyzing = false;
  String _transcribedText = '';

  // Error tracking
  String? _lastError;
  bool _hasProcessingError = false;

  // Rive inputs
  BooleanInput? _isRecordInput;
  BooleanInput? _clickInput;
  BooleanInput? _isSubmitInput;
  BooleanInput? _isDoneInput;
  BooleanInput? _taskSelectedInput;
  BooleanInput? _noteSelectedInput;

  // Guard to prevent accidental triggers during animation loading
  bool _isInitializing = true;
  bool _isAddBottomSheetOpen = false;
  DateTime _lastRecordInteractionAt = DateTime.fromMillisecondsSinceEpoch(0);

  // Monitoring timer
  Timer? _monitoringTimer;

  // Audio-reactive bar visualization
  StreamSubscription<Amplitude>? _amplitudeSubscription;
  Timer? _barAnimationTimer;
  final math.Random _barRandom = math.Random();
  final List<double> _barNormalizedValues = List.filled(7, 0.0);
  final List<double> _barPhases =
      List<double>.generate(7, (index) => index * 0.65);
  final Map<int, List<NumberInput>> _barInputs = {};
  final Map<int, List<ViewModelInstanceNumber>> _barViewModelNumbers = {};
  double _latestAmplitudeDb = -50.0;

  // Audio player
  late AudioPlayer _audioPlayer;

  @override
  void initState() {
    super.initState();
    _loadRiveAnimation();
    _initAudioPlayer();
  }

  void _loadRiveAnimation() {
    _fileLoader = FileLoader.fromAsset(
      'assets/animations/bottom_bar.riv',
      riveFactory: Factory.rive,
    );
  }

  String _normalizeInputName(String name) =>
      name.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');

  BooleanInput? _findBoolInputWithAliases(List<String> aliases) {
    if (controller == null) return null;

    final normalizedAliases = aliases.map(_normalizeInputName).toSet();

    for (final input in controller!.inputs.whereType<BooleanInput>()) {
      if (normalizedAliases.contains(_normalizeInputName(input.name))) {
        return input;
      }
    }

    return null;
  }

  void _resetAllBoolInputsToFalse() {
    if (controller == null) return;
    for (final input in controller!.inputs.whereType<BooleanInput>()) {
      input.value = false;
    }
  }

  int? _barIndexFromName(String name) {
    final normalized = _normalizeInputName(name);
    final match = RegExp(r'bar([1-7])').firstMatch(normalized);
    if (match == null) return null;
    return int.tryParse(match.group(1)!);
  }

  void _registerBarInputBinding(int index, NumberInput input) {
    final bindings = _barInputs.putIfAbsent(index, () => <NumberInput>[]);
    if (!bindings.contains(input)) {
      bindings.add(input);
    }
  }

  void _registerBarViewModelBinding(
      int index, ViewModelInstanceNumber propertyValue) {
    final bindings = _barViewModelNumbers.putIfAbsent(
        index, () => <ViewModelInstanceNumber>[]);
    if (!bindings.contains(propertyValue)) {
      bindings.add(propertyValue);
    }
  }

  void _discoverBarInputsFromController(StateMachine stateMachine) {
    for (final input in stateMachine.inputs.whereType<NumberInput>()) {
      final index = _barIndexFromName(input.name);
      if (index != null) {
        _registerBarInputBinding(index, input);
      }
    }
  }

  NumberInput? _findNumberInputWithCandidate(String candidate) {
    if (controller == null) return null;

    if (candidate.contains('/')) {
      final segments = candidate.split('/');
      if (segments.length >= 2) {
        final inputName = segments.last;
        final path = segments.sublist(0, segments.length - 1).join('/');
        return controller!.number(inputName, path: path);
      }
    }

    return controller!.number(candidate);
  }

  List<String> _barCandidatePathsFor(int index) {
    return <String>[
      'Bar $index',
      'Bar$index',
      'bar$index',
      'Bar Heights/Bar $index',
      'Bar Heights/Bar$index',
      'BarHeights/Bar $index',
      'BarHeights/Bar$index',
      'Bars/Bar $index',
      'Bars/Bar$index',
    ];
  }

  void _discoverBarInputsFromCandidates() {
    for (int index = 1; index <= 7; index++) {
      for (final candidate in _barCandidatePathsFor(index)) {
        final input = _findNumberInputWithCandidate(candidate);
        if (input != null) {
          _registerBarInputBinding(index, input);
        }
      }
    }
  }

  void _discoverBarViewModelBindingsRecursive(
    ViewModelInstance instance, {
    String parentPath = '',
  }) {
    final root = _viewModelInstance;
    if (root == null) return;

    for (final property in instance.properties) {
      final path =
          parentPath.isEmpty ? property.name : '$parentPath/${property.name}';

      if (property.type == DataType.number) {
        final index =
            _barIndexFromName(property.name) ?? _barIndexFromName(path);
        if (index != null) {
          final number = root.number(path);
          if (number != null) {
            _registerBarViewModelBinding(index, number);
          }
        }
      } else if (property.type == DataType.viewModel) {
        final nested = root.viewModel(path);
        if (nested != null) {
          _discoverBarViewModelBindingsRecursive(nested, parentPath: path);
        }
      }
    }
  }

  void _discoverBarViewModelFromCandidates() {
    final viewModel = _viewModelInstance;
    if (viewModel == null) return;

    for (int index = 1; index <= 7; index++) {
      for (final candidate in _barCandidatePathsFor(index)) {
        final number = viewModel.number(candidate);
        if (number != null) {
          _registerBarViewModelBinding(index, number);
        }
      }
    }
  }

  void _debugPrintBarCandidates() {
    if (controller != null) {
      for (final input in controller!.inputs) {
        final normalized = _normalizeInputName(input.name);
        if (normalized.contains('bar') || normalized.contains('height')) {
          debugPrint(
              '🎨 Rive bar input candidate: "${input.name}" (${input.runtimeType})');
        }
      }
    }

    final root = _viewModelInstance;
    if (root == null) return;

    void logViewModel(ViewModelInstance instance, {String parentPath = ''}) {
      for (final property in instance.properties) {
        final path = parentPath.isEmpty
            ? property.name
            : '$parentPath/${property.name}';
        final normalized = _normalizeInputName(path);
        if (normalized.contains('bar') || normalized.contains('height')) {
          debugPrint(
              '🎨 Rive bar viewModel candidate: "$path" (${property.type})');
        }

        if (property.type == DataType.viewModel) {
          final nested = root.viewModel(path);
          if (nested != null) {
            logViewModel(nested, parentPath: path);
          }
        }
      }
    }

    logViewModel(root);
  }

  int _activeBarCount() {
    final keys = <int>{..._barInputs.keys, ..._barViewModelNumbers.keys};
    if (keys.isEmpty) {
      return 0;
    }
    return keys.reduce(math.max).clamp(1, 7);
  }

  void _discoverBarBindings() {
    _barInputs.clear();
    _barViewModelNumbers.clear();

    if (controller != null) {
      _discoverBarInputsFromController(controller!);
    }
    _discoverBarInputsFromCandidates();

    if (_viewModelInstance != null) {
      _discoverBarViewModelBindingsRecursive(_viewModelInstance!);
      _discoverBarViewModelFromCandidates();
    }

    final int inputBindingCount =
        _barInputs.values.fold<int>(0, (sum, list) => sum + list.length);
    final int viewModelBindingCount = _barViewModelNumbers.values
        .fold<int>(0, (sum, list) => sum + list.length);

    debugPrint(
        '🎨 Rive bars: inputs=$inputBindingCount, viewModel=$viewModelBindingCount');
    if (inputBindingCount == 0 && viewModelBindingCount == 0) {
      _debugPrintBarCandidates();
    }
    _resetBarValues();
  }

  void _setBarValue(int index, double value) {
    final clamped = value.clamp(1.0, 6.0);

    final inputs = _barInputs[index];
    if (inputs != null) {
      for (final input in inputs) {
        input.value = clamped;
      }
    }

    final viewModelNumbers = _barViewModelNumbers[index];
    if (viewModelNumbers != null) {
      for (final viewModelNumber in viewModelNumbers) {
        viewModelNumber.value = clamped;
      }
    }
  }

  void _resetBarValues() {
    for (int i = 0; i < 7; i++) {
      _barNormalizedValues[i] = 0.0;
      _setBarValue(i + 1, 1.0);
    }
  }

  double _normalizeAmplitudeToUnit(double db) {
    // Map microphone dB range to 0..1 (rough speech range -50..0 dB).
    const minDb = -50.0;
    const maxDb = 0.0;
    return ((db - minDb) / (maxDb - minDb)).clamp(0.0, 1.0);
  }

  void _driveBarsFromAudioLevel() {
    final int discoveredBarCount = _activeBarCount();
    final int barCount = discoveredBarCount == 0 ? 6 : discoveredBarCount;
    final double baseUnit = _normalizeAmplitudeToUnit(_latestAmplitudeDb);

    for (int i = 0; i < 7; i++) {
      final index = i + 1;

      if (i < barCount) {
        _barPhases[i] += 0.22 + (i * 0.03);
        final wave = (math.sin(_barPhases[i]) + 1.0) / 2.0;
        final jitter = _barRandom.nextDouble() * 0.18;
        final target =
            (baseUnit * (0.55 + (wave * 0.45)) + jitter).clamp(0.0, 1.0);
        _barNormalizedValues[i] =
            (_barNormalizedValues[i] * 0.72) + (target * 0.28);
      } else {
        _barNormalizedValues[i] *= 0.82;
      }

      // Quantize to integer steps so value-change driven Rive transitions
      // reliably fire (1,2...6) and never collapse to zero height.
      final barValue = (1.0 + (_barNormalizedValues[i] * 5.0)).clamp(1.0, 6.0);
      _setBarValue(index, barValue.roundToDouble());
    }
  }

  void _stopBarVisualization({bool resetBars = true}) {
    _amplitudeSubscription?.cancel();
    _amplitudeSubscription = null;

    _barAnimationTimer?.cancel();
    _barAnimationTimer = null;

    if (resetBars) {
      _resetBarValues();
    }
  }

  void _startBarVisualization() {
    _stopBarVisualization(resetBars: false);

    _latestAmplitudeDb = -50.0;
    for (int i = 0; i < 7; i++) {
      _barNormalizedValues[i] = 0.0;
    }

    _amplitudeSubscription = _audioRecorder
        .onAmplitudeChanged(const Duration(milliseconds: 35))
        .listen(
      (amplitude) {
        _latestAmplitudeDb = amplitude.current;
      },
      onError: (error) {
        debugPrint('🎨 Rive bars amplitude error: $error');
      },
    );

    _barAnimationTimer =
        Timer.periodic(const Duration(milliseconds: 33), (timer) {
      if (!_isRecording || !mounted) {
        return;
      }
      _driveBarsFromAudioLevel();
    });
  }

  void _markRecordInteraction() {
    _lastRecordInteractionAt = DateTime.now();
  }

  bool _canOpenAddBottomSheet() {
    if (!mounted) return false;
    if (_isInitializing) return false;
    if (_isAddBottomSheetOpen) return false;
    if (_isStartingRecording || _isStoppingRecording) return false;
    if (_isSubmitFlowActive) return false;
    if (_isRecording) return false;
    if (_hasSubmitIntent) return false;
    if (_isTranscribing || _isAnalyzing) return false;
    if ((_isRecordInput?.value ?? false) || (_isSubmitInput?.value ?? false)) {
      return false;
    }
    return true;
  }

  void _resetRecordIntentInputs() {
    if (_isRecordInput != null) {
      _isRecordInput!.value = false;
    }
    if (_isSubmitInput != null) {
      _isSubmitInput!.value = false;
    }
    if (_clickInput != null) {
      _clickInput!.value = false;
    }
  }

  Future<void> _requestStartRecording() async {
    if (_isStartingRecording || _isStoppingRecording || _isRecording) {
      return;
    }

    if (_isTranscribing || _isAnalyzing) {
      debugPrint('⏳ Ignoring record request while processing previous audio');
      _resetRecordIntentInputs();
      _showInfoSnackBar('Please wait for processing to finish.');
      return;
    }

    _markRecordInteraction();
    _hasSubmitIntent = false;
    _isSubmitFlowActive = false;
    unawaited(_playStartRecordingSound());
    await _startRecording();
  }

  Future<void> _requestStopRecording({bool forceProcess = false}) async {
    if (_isStartingRecording || _isStoppingRecording) {
      return;
    }

    if (!_isRecording) {
      _resetRecordIntentInputs();
      return;
    }

    _markRecordInteraction();
    final shouldProcess =
        forceProcess || _hasSubmitIntent || (_isSubmitInput?.value ?? false);
    unawaited(_playEndRecordingSound());
    await _stopRecording(shouldProcess: shouldProcess);
  }

  void _detachRiveStateMachineListeners() {
    _monitoringTimer?.cancel();
    _monitoringTimer = null;

    if (controller != null) {
      controller!.removeEventListener(_onRiveEvent);
    }
  }

  void _forceRebuildRiveToInitial() {
    debugPrint('🔄 Forcing hard Rive rebuild to initial state');
    _detachRiveStateMachineListeners();
    _riveWidgetController = null;
    controller = null;
    _viewModelInstance = null;
    _isRecordInput = null;
    _clickInput = null;
    _isSubmitInput = null;
    _isDoneInput = null;
    _taskSelectedInput = null;
    _noteSelectedInput = null;

    if (!mounted) return;
    setState(() {
      _isInitializing = true;
      _riveRebuildNonce++;
    });
  }

  void _resetAfterError() {
    _immediateStateReset();
    _forceRebuildRiveToInitial();
  }

  void _configureInputsFromController() {
    if (controller == null) return;

    _isRecordInput =
        controller!.boolean('isRecord') ?? _findBoolInputWithAliases(['record']);
    _clickInput =
        controller!.boolean('Click') ?? _findBoolInputWithAliases(['click']);
    _isSubmitInput = controller!.boolean('isSubmit') ??
        _findBoolInputWithAliases(['submit']);
    _isDoneInput =
        controller!.boolean('isDone') ?? _findBoolInputWithAliases(['done']);
    _taskSelectedInput = controller!.boolean('Task Selected') ??
        _findBoolInputWithAliases(
            ['Task Selected', 'TaskSelected', 'taskSelected']);
    _noteSelectedInput = controller!.boolean('Note Selected') ??
        _findBoolInputWithAliases(
            ['Note Selected', 'NoteSelected', 'noteSelected']);
  }

  void _onRiveLoaded(RiveLoaded loaded) {
    if (identical(_riveWidgetController, loaded.controller)) {
      return;
    }

    _detachRiveStateMachineListeners();

    _isInitializing = true;
    _riveWidgetController = loaded.controller;
    controller = loaded.controller.stateMachine;
    _viewModelInstance = loaded.viewModelInstance;
    if (_viewModelInstance == null) {
      try {
        _viewModelInstance = loaded.controller.dataBind(DataBind.auto());
      } catch (error) {
        debugPrint('🎨 Rive: No auto data binding available ($error)');
      }
    }

    debugPrint('🎨 Rive: Initializing artboard "${loaded.controller.artboard.name}"');
    debugPrint('🎨 Rive: Found state machine "${controller?.name}"');

    if (controller == null) {
      debugPrint('❌ Rive: No state machine available');
      return;
    }

    for (final input in controller!.inputs) {
      debugPrint(
          '🎨 Rive: Input found: "${input.name}" (Type: ${input.runtimeType})');
    }

    _configureInputsFromController();
    _discoverBarBindings();

    debugPrint('🎨 Rive: Initializing inputs to false...');
    _resetAllBoolInputsToFalse();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _resetAllBoolInputsToFalse();
      }
    });

    controller!.addEventListener(_onRiveEvent);
    _startIsRecordMonitoring();

    Timer(const Duration(milliseconds: 500), () {
      if (mounted) {
        setState(() {
          _isInitializing = false;
          debugPrint('🎨 Rive: Initialization complete, monitoring active');
        });
      }
    });
  }

  // Monitor state changes to detect when recording should start/stop, etc.
  void _startIsRecordMonitoring() {
    _monitoringTimer?.cancel();
    bool previousIsRecord = _isRecordInput?.value ?? false;
    bool previousIsSubmit = _isSubmitInput?.value ?? false;
    bool previousTaskSelected = _taskSelectedInput?.value ?? false;
    bool previousNoteSelected = _noteSelectedInput?.value ?? false;

    // Check input states every 100ms
    _monitoringTimer =
        Timer.periodic(const Duration(milliseconds: 100), (timer) {
      if (!mounted || _isRecordInput == null) {
        timer.cancel();
        return;
      }

      final currentIsRecord = _isRecordInput!.value;
      final currentIsSubmit = _isSubmitInput?.value ?? false;
      final currentTaskSelected = _taskSelectedInput?.value ?? false;
      final currentNoteSelected = _noteSelectedInput?.value ?? false;

      // During initialization, we only update previous values to sync with Rive
      // but we do not trigger any actions.
      if (_isInitializing) {
        _resetAllBoolInputsToFalse();
        previousIsRecord = currentIsRecord;
        previousIsSubmit = currentIsSubmit;
        previousTaskSelected = currentTaskSelected;
        previousNoteSelected = currentNoteSelected;
        return;
      }

      // Only act on state changes, not continuous states

      // Handle isRecord state changes
      if (currentIsRecord != previousIsRecord) {
        debugPrint('🎨 Rive isRecord changed: $currentIsRecord');
        _markRecordInteraction();
        if (currentIsRecord &&
            !_isRecording &&
            !_isTranscribing &&
            !_isAnalyzing) {
          // Start recording when isRecord becomes true
          unawaited(_requestStartRecording());
        } else if (!currentIsRecord && _isRecording) {
          // Record toggle off / cancel: stop recording without processing.
          unawaited(_requestStopRecording(forceProcess: false));
        } else if (currentIsRecord && (_isTranscribing || _isAnalyzing)) {
          _resetRecordIntentInputs();
        }
        previousIsRecord = currentIsRecord;
      }

      // Process recording when isSubmit becomes true (and we're recording)
      if (currentIsSubmit != previousIsSubmit) {
        debugPrint('🎨 Rive isSubmit changed: $currentIsSubmit');
        _markRecordInteraction();
        if (currentIsSubmit && _isRecording) {
          _hasSubmitIntent = true;
          _isSubmitFlowActive = true;
          _resetTaskSelected();
          _resetNoteSelected();
          unawaited(_requestStopRecording(forceProcess: true));
        } else if (currentIsSubmit && !_isRecording) {
          _hasSubmitIntent = false;
          _isSubmitFlowActive = false;
          _resetRecordIntentInputs();
        }
        previousIsSubmit = currentIsSubmit;
      }

      // Handle taskSelected state changes
      if (currentTaskSelected != previousTaskSelected) {
        debugPrint('🎨 Rive taskSelected changed: $currentTaskSelected');
        if (currentTaskSelected) {
          if (_isSubmitFlowActive ||
              _hasSubmitIntent ||
              _isTranscribing ||
              _isAnalyzing) {
            _resetTaskSelected();
          } else if (_canOpenAddBottomSheet()) {
            _showTaskBottomSheet();
          } else {
            debugPrint(
                '🎨 Rive: Ignoring Task Selected while recording flow is active');
            _resetTaskSelected();
          }
        }
        previousTaskSelected = currentTaskSelected;
      }

      // Handle noteSelected state changes
      if (currentNoteSelected != previousNoteSelected) {
        debugPrint('🎨 Rive noteSelected changed: $currentNoteSelected');
        if (currentNoteSelected) {
          if (_isSubmitFlowActive ||
              _hasSubmitIntent ||
              _isTranscribing ||
              _isAnalyzing) {
            _resetNoteSelected();
          } else if (_canOpenAddBottomSheet()) {
            _showNoteBottomSheet();
          } else {
            debugPrint(
                '🎨 Rive: Ignoring Note Selected while recording flow is active');
            _resetNoteSelected();
          }
        }
        previousNoteSelected = currentNoteSelected;
      }
    });
  }

  void _onRiveEvent(Event event) {
    if (_isInitializing) {
      debugPrint('🎨 Rive Event ignored during init: ${event.name}');
      return;
    }

    debugPrint('🎨 Rive Event triggered: ${event.name}');

    // Handle events directly. Sometimes Rive animations fire events on click
    // in addition to (or instead of) changing boolean input values.
    switch (event.name) {
      case 'isRecord':
      case 'RecordStart':
      case 'StartRecording':
        _markRecordInteraction();
        if (!_isRecording && !_isTranscribing && !_isAnalyzing) {
          unawaited(_requestStartRecording());
        } else {
          _resetRecordIntentInputs();
        }
        break;
      case 'isSubmit':
      case 'RecordEnd':
      case 'StopRecording':
        _markRecordInteraction();
        if (_isRecording) {
          _hasSubmitIntent = true;
          _isSubmitFlowActive = true;
          _resetTaskSelected();
          _resetNoteSelected();
          unawaited(_requestStopRecording(forceProcess: true));
        } else {
          _hasSubmitIntent = false;
          _isSubmitFlowActive = false;
          _resetRecordIntentInputs();
        }
        break;
      case 'Note Selected':
      case 'NoteSelected':
      case 'ShowNotes':
        if (_canOpenAddBottomSheet()) {
          _showNoteBottomSheet();
        } else {
          debugPrint(
              '🎨 Rive: Ignoring note event while recording flow is active');
          _resetNoteSelected();
        }
        break;
      case 'Task Selected':
      case 'TaskSelected':
      case 'ShowTasks':
        if (_canOpenAddBottomSheet()) {
          _showTaskBottomSheet();
        } else {
          debugPrint(
              '🎨 Rive: Ignoring task event while recording flow is active');
          _resetTaskSelected();
        }
        break;
      default:
        debugPrint('🎨 Rive: Unhandled event "${event.name}"');
    }
  }

  Future<void> _startRecording() async {
    if (_isRecording || _isStartingRecording || _isStoppingRecording) {
      return;
    }

    if (_isTranscribing || _isAnalyzing) {
      debugPrint('⏳ Start ignored: processing is still in progress');
      _resetRecordIntentInputs();
      return;
    }

    _isStartingRecording = true;
    _hasSubmitIntent = false;
    _isSubmitFlowActive = false;

    // Check guest mode recording limits
    try {
      if (widget.isGuestMode && widget.guestModeService != null && !_purchaseService.isPremium) {
        final canRecord = await widget.guestModeService!.canRecord();
        if (!canRecord) {
          debugPrint('❌ Guest mode recording limit reached');
          _resetRecordIntentInputs();
          _isStartingRecording = false;
          widget.onShowPaywall?.call();
          return;
        }
      }

      // Check permissions
      final hasPermission = await _checkPermissions();
      if (!hasPermission) {
        debugPrint('❌ Recording permission not granted');
        _resetRecordIntentInputs();
        return;
      }

      // Dispose any previous recorder instance and create a fresh one
      _stopBarVisualization(resetBars: true);
      try {
        await _audioRecorder.dispose();
      } catch (_) {}
      _audioRecorder = AudioRecorder();

      // Get temporary directory for saving the recording
      final directory = await getTemporaryDirectory();
      _recordedFilePath =
          '${directory.path}/recording_${DateTime.now().millisecondsSinceEpoch}.m4a';

      debugPrint('🎙️ Starting recording to: $_recordedFilePath');

      // Start recording
      await _audioRecorder.start(
        const RecordConfig(
          encoder: AudioEncoder.aacLc,
          bitRate: 128000,
          sampleRate: 44100,
        ),
        path: _recordedFilePath!,
      );

      _recordingStartTime = DateTime.now();
      _markRecordInteraction();

      setState(() {
        _isRecording = true;
        _isTranscribing = false;
        _isAnalyzing = false;
        _transcribedText = '';
        _hasProcessingError = false;
        _lastError = null;
      });

      // Reset isDone to false when starting new recording
      if (_isDoneInput != null) {
        _isDoneInput!.value = false;
      }

      _startBarVisualization();
      debugPrint('✅ Recording started successfully');
    } catch (e) {
      debugPrint('❌ Failed to start recording: $e');
      // Reset state on error
      setState(() {
        _isRecording = false;
      });
      _stopBarVisualization(resetBars: true);
      _resetRecordIntentInputs();
      _resetAfterError();
      _showErrorSnackBar(_toUserFriendlyErrorMessage(
        e,
        fallback:
            'Couldn\'t start recording. Please check microphone access and try again.',
      ));
    } finally {
      _isStartingRecording = false;
    }
  }

  Future<void> _stopRecording({required bool shouldProcess}) async {
    if (_isStoppingRecording || _isStartingRecording) {
      return;
    }

    if (!_isRecording) {
      debugPrint('⚠️ Stop recording called but not currently recording');
      _resetRecordIntentInputs();
      return;
    }

    _isStoppingRecording = true;
    setState(() {
      _isRecording = false;
    });
    _stopBarVisualization(resetBars: true);

    try {
      debugPrint('🛑 Stopping recording...');
      _markRecordInteraction();
      final path = await _audioRecorder.stop();
      debugPrint('✅ Recording stopped, path: $path');

      if (path != null) {
        if (shouldProcess) {
          // Comprehensive file validation
          await _validateAudioFile(path);
          debugPrint('✅ Audio file validation passed');

          // Start the transcription and processing workflow
          await _processRecording(path);
        } else {
          // Cancel flow: intentionally discard recording and skip processing.
          debugPrint('⏹️ Recording canceled - skipping transcription/analysis');
          try {
            final file = io.File(path);
            if (await file.exists()) {
              await file.delete();
            }
          } catch (_) {}
          _resetRecordIntentInputs();
        }
      } else {
        if (shouldProcess) {
          debugPrint('❌ Recording path is null');
          throw Exception('Recording failed - no file path returned');
        }
        _resetRecordIntentInputs();
      }

      // Dispose the recorder so we can recreate a fresh instance next time
      try {
        await _audioRecorder.dispose();
      } catch (_) {}
    } catch (e) {
      debugPrint('❌ Error stopping recording: $e');
      // Reset state on error
      setState(() {
        _isRecording = false;
        _isTranscribing = false;
        _isAnalyzing = false;
        _hasProcessingError = true;
        _lastError = e.toString();
      });
      _resetRecordIntentInputs();

      _resetAfterError();
      _showErrorSnackBar(_toUserFriendlyErrorMessage(
        e,
        fallback: 'Recording stopped unexpectedly. Please try again.',
      ));
    } finally {
      _isStoppingRecording = false;
      _hasSubmitIntent = false;
      if (!_isTranscribing && !_isAnalyzing) {
        _isSubmitFlowActive = false;
      }
    }
  }

  Future<void> _validateAudioFile(String filePath) async {
    try {
      final file = io.File(filePath);

      // Check if file exists
      if (!await file.exists()) {
        throw Exception('Recording file not found');
      }

      // Check file size
      final fileStats = await file.stat();

      // Validation checks
      if (fileStats.size == 0) {
        throw Exception('Recording file is empty (0 bytes)');
      }
    } catch (e) {
      rethrow;
    }
  }

  Future<void> _processRecording(String filePath) async {
    try {
      // Step 1: Transcribe audio
    setState(() {
      _isTranscribing = true;
      _isAnalyzing = false;
    });
    _isSubmitFlowActive = true;

      try {
        debugPrint('🎙️ Starting transcription for: $filePath');
        _transcribedText = await _assemblyAIService.transcribeAudio(filePath);
        debugPrint(
            '✅ Transcription successful. Length: ${_transcribedText.length} characters');
        debugPrint('📝 Transcribed text: $_transcribedText');

        if (_transcribedText.trim().isEmpty) {
          throw Exception(
              'Transcription returned empty text - no speech detected');
        }
      } catch (e) {
        debugPrint('❌ Transcription failed: $e');
        throw Exception('Transcription failed: $e');
      }

      // Continue with AI analysis
      await _processTranscriptionResult();
    } catch (e) {
      debugPrint('❌ Processing failed: $e');
      if (!mounted) return;

      setState(() {
        _isTranscribing = false;
        _isAnalyzing = false;
        _hasProcessingError = true;
        _lastError = e.toString();
      });

      _resetAfterError();
      _showErrorSnackBar(_toUserFriendlyErrorMessage(
        e,
        fallback: 'We couldn\'t process that recording. Please try again.',
      ));
    }
  }

  Future<void> _processTranscriptionResult() async {
    if (!mounted) return;

    // Step 2: Analyze with Mistral
    setState(() {
      _isTranscribing = false;
      _isAnalyzing = true;
    });
    _isSubmitFlowActive = true;

    try {
      debugPrint('🤖 Starting AI analysis with Mistral...');
      debugPrint('📝 Text to analyze: $_transcribedText');

      final result =
          await _aiAnalysisService.analyzeTranscription(_transcribedText);

      debugPrint('✅ AI analysis completed');
      debugPrint('📊 Analysis result: $result');

      if (!mounted) return;

      // Validate result structure
      if ((!result.containsKey('notes') && !result.containsKey('tasks'))) {
        throw Exception('Invalid response format from AI analysis');
      }

      // Check if we got any content
      final hasNotes =
          result['notes'] != null && (result['notes'] as List).isNotEmpty;
      final hasTasks =
          result['tasks'] != null && (result['tasks'] as List).isNotEmpty;

      if (!hasNotes && !hasTasks) {
        debugPrint('⚠️ No notes or tasks extracted from transcription');
      } else {
        debugPrint(
            '📝 Found ${result['notes']?.length ?? 0} notes and ${result['tasks']?.length ?? 0} tasks');
      }

      // Step 3: Add to timeline using ItemManagementService
      debugPrint('📅 Adding items to timeline...');
      await _addItemsToTimeline(result);

      debugPrint('✅ Processing completed successfully');

      // Set isDone to true to show completion
      if (_isDoneInput != null) {
        _isDoneInput!.value = true;
        debugPrint('✅ Set isDone to true');
      }

      // --------------------------------------------------------------
      // Fast-reset the inputs one second after the DONE animation is
      // shown so the user can immediately start a new recording.  We
      // still keep the existing _scheduleStateReset() (2 s) as a
      // fallback, but this makes the UX responsive without requiring
      // an app restart.
      // --------------------------------------------------------------
      Timer(const Duration(seconds: 1), () {
        if (mounted) {
          _immediateStateReset();
        }
      });

      // Schedule reset for next recording
      _scheduleStateReset();
    } catch (e) {
      debugPrint('❌ AI analysis failed: $e');
      if (!mounted) return;

      setState(() {
        _isTranscribing = false;
        _isAnalyzing = false;
        _hasProcessingError = true;
        _lastError = e.toString();
      });

      _resetAfterError();
      _showErrorSnackBar(_toUserFriendlyErrorMessage(
        e,
        fallback: 'We couldn\'t analyze that recording. Please try again.',
      ));
    }
  }

  Future<void> _addItemsToTimeline(Map<String, dynamic> result) async {
    try {
      debugPrint('📅 Adding items to timeline...');

      int notesAdded = 0;
      int tasksAdded = 0;

      // Add notes to timeline
      if (result['notes'] != null && result['notes'].isNotEmpty) {
        final notes = List<String>.from(result['notes']);
        debugPrint('📝 Adding ${notes.length} notes: $notes');

        for (final note in notes) {
          if (note.trim().isNotEmpty) {
            _itemManagementService.createNoteEntry(
              noteText: note.trim(),
              selectedDate: widget.selectedDate,
              timelineEntriesByDate: widget.timelineEntriesByDate,
              onStateUpdate: widget.onStateUpdate,
            );
            notesAdded++;
            debugPrint('✅ Added note: ${note.trim()}');
          }
        }
      }

      // Add tasks to timeline
      if (result['tasks'] != null && result['tasks'].isNotEmpty) {
        final tasks = List<String>.from(result['tasks']);
        debugPrint('✅ Adding ${tasks.length} tasks: $tasks');

        for (final task in tasks) {
          if (task.trim().isNotEmpty) {
            _itemManagementService.createTaskEntry(
              taskText: task.trim(),
              selectedDate: widget.selectedDate,
              timelineEntriesByDate: widget.timelineEntriesByDate,
              onStateUpdate: widget.onStateUpdate,
            );
            tasksAdded++;
            debugPrint('✅ Added task: ${task.trim()}');
          }
        }
      }

      debugPrint(
          '✅ Successfully added $notesAdded notes and $tasksAdded tasks to timeline');

      // Increment guest mode recording count if in guest mode and processing was successful
      if (widget.isGuestMode && widget.guestModeService != null) {
        await widget.guestModeService!.incrementRecordingCount();
        // Update the UI counter
        widget.onGuestRecordingCountUpdate?.call();
        debugPrint('✅ Incremented guest mode recording count');
      }
    } catch (e) {
      debugPrint('❌ Failed to add items to timeline: $e');
      throw Exception('Failed to add items to timeline: $e');
    }
  }

  // Immediately reset all states for the next recording cycle
  void _immediateStateReset() {
    if (!mounted) {
      debugPrint('⚠️ Widget not mounted, skipping immediate state reset');
      return;
    }

    debugPrint('🔄 Immediate state reset for next recording');
    // Reset all processing states
    setState(() {
      _isRecording = false;
      _isTranscribing = false;
      _isAnalyzing = false;
      _transcribedText = '';
      _recordingStartTime = null;
      _hasProcessingError = false;
      _lastError = null;
    });
    _isSubmitFlowActive = false;

    // Reset all Rive inputs
    if (_isRecordInput != null) {
      _isRecordInput!.value = false;
    }

    if (_isSubmitInput != null) {
      _isSubmitInput!.value = false;
    }

    if (_isDoneInput != null) {
      _isDoneInput!.value = false;
    }

    // Ensure the Click input is reset so that the button can be pressed again
    if (_clickInput != null) {
      _clickInput!.value = false;
      debugPrint('🔄 Reset click input');
    }
    _resetBarValues();

    debugPrint('✅ Immediate state reset complete - ready for next recording');
  }

  // Reset all states for the next recording cycle
  void _scheduleStateReset() {
    debugPrint('⏰ Scheduling state reset in 2 seconds...');
    Timer(const Duration(seconds: 2), () {
      if (!mounted) {
        debugPrint('⚠️ Widget not mounted, skipping state reset');
        return;
      }

      debugPrint('🔄 Resetting all states for next recording');
      // Reset all processing states
      setState(() {
        _isRecording = false;
        _isTranscribing = false;
        _isAnalyzing = false;
        _transcribedText = '';
        _recordingStartTime = null;
        _hasProcessingError = false;
        _lastError = null;
      });
      _isSubmitFlowActive = false;

      // Reset all Rive inputs
      if (_isRecordInput != null) {
        _isRecordInput!.value = false;
        debugPrint('🔄 Reset isRecord input');
      }

      if (_isSubmitInput != null) {
        _isSubmitInput!.value = false;
        debugPrint('🔄 Reset isSubmit input');
      }

      if (_isDoneInput != null) {
        _isDoneInput!.value = false;
        debugPrint('🔄 Reset isDone input');
      }

      // Ensure the Click input is reset so that the button can be pressed again
      if (_clickInput != null) {
        _clickInput!.value = false;
        debugPrint('🔄 Reset click input');
      }
      _resetBarValues();

      debugPrint('✅ State reset complete - ready for next recording');
    });
  }

  Future<bool> _checkPermissions() async {
    final status = await Permission.microphone.status;
    if (status.isGranted) {
      return true;
    }

    final result = await Permission.microphone.request();
    return result.isGranted;
  }

  void _initAudioPlayer() {
    _audioPlayer = AudioPlayer();
  }

  Future<void> _playStartRecordingSound() async {
    try {
      await _audioPlayer.play(AssetSource('sounds/record-start.mp3'));
    } catch (e) {
      // Handle error silently - don't break recording functionality if sound fails
      debugPrint('Failed to play start recording sound: $e');
    }
  }

  Future<void> _playEndRecordingSound() async {
    try {
      await _audioPlayer.play(AssetSource('sounds/record-end.mp3'));
    } catch (e) {
      // Handle error silently - don't break recording functionality if sound fails
      debugPrint('Failed to play end recording sound: $e');
    }
  }

  // Show task bottom sheet and reset the taskSelected boolean
  void _showTaskBottomSheet() {
    if (!_canOpenAddBottomSheet()) {
      _resetTaskSelected();
      return;
    }

    _isAddBottomSheetOpen = true;
    showAddItemBottomSheet(
      context: context,
      initialTab: 'Tasks',
      onAddItem: _handleAddItem,
      onReloadEntries: widget.onStateUpdate,
    ).whenComplete(() {
      _isAddBottomSheetOpen = false;
      _resetTaskSelected();
    });
    // Reset immediately after showing
    _resetTaskSelected();
  }

  // Show note bottom sheet and reset the noteSelected boolean
  void _showNoteBottomSheet() {
    if (!_canOpenAddBottomSheet()) {
      _resetNoteSelected();
      return;
    }

    _isAddBottomSheetOpen = true;
    showAddItemBottomSheet(
      context: context,
      initialTab: 'Notes',
      onAddItem: _handleAddItem,
      onReloadEntries: widget.onStateUpdate,
    ).whenComplete(() {
      _isAddBottomSheetOpen = false;
      _resetNoteSelected();
    });
    // Reset immediately after showing
    _resetNoteSelected();
  }

  // Handle adding an item from the bottom sheet
  void _handleAddItem(String content, String type) {
    if (type == 'Notes') {
      _itemManagementService.createNoteEntry(
        noteText: content,
        selectedDate: widget.selectedDate,
        timelineEntriesByDate: widget.timelineEntriesByDate,
        onStateUpdate: widget.onStateUpdate,
      );
      _resetNoteSelected();
    } else {
      _itemManagementService.createTaskEntry(
        taskText: content,
        selectedDate: widget.selectedDate,
        timelineEntriesByDate: widget.timelineEntriesByDate,
        onStateUpdate: widget.onStateUpdate,
      );
      _resetTaskSelected();
    }
  }

  // Reset taskSelected boolean in Rive
  void _resetTaskSelected() {
    if (_taskSelectedInput != null) {
      _taskSelectedInput!.value = false;
    }
  }

  // Reset noteSelected boolean in Rive
  void _resetNoteSelected() {
    if (_noteSelectedInput != null) {
      _noteSelectedInput!.value = false;
    }
  }

  @override
  void dispose() {
    _detachRiveStateMachineListeners();
    _stopBarVisualization(resetBars: false);
    _fileLoader?.dispose();
    _riveWidgetController = null;
    _viewModelInstance = null;
    controller = null;
    _audioRecorder.dispose();
    _audioPlayer.dispose();
    super.dispose();
  }

  RiveWidgetController _buildRiveController(File file) {
    final selectors = <(ArtboardSelector, StateMachineSelector)>[
      (const ArtboardNamed('Artboard'), const StateMachineNamed('Record')),
      (const ArtboardNamed('Artboard'), const StateMachineDefault()),
      (const ArtboardDefault(), const StateMachineNamed('Record')),
      (const ArtboardDefault(), const StateMachineDefault()),
    ];

    Object? lastError;
    for (final selector in selectors) {
      try {
        return RiveWidgetController(
          file,
          artboardSelector: selector.$1,
          stateMachineSelector: selector.$2,
        );
      } catch (error) {
        lastError = error;
      }
    }

    throw Exception('Failed to create Rive controller: $lastError');
  }

  Widget _buildRiveState(BuildContext context, RiveState state) {
    if (state is RiveLoading) {
      return const SizedBox(
        width: 600,
        height: 250,
        child: Center(child: CircularProgressIndicator()),
      );
    }

    if (state is RiveFailed) {
      debugPrint('❌ Rive: Failed to load bottom bar (${state.error})');
      return const SizedBox(
        width: 600,
        height: 250,
        child: Center(
          child: Text(
            'Animation failed to load',
            style: TextStyle(fontFamily: 'Geist'),
          ),
        ),
      );
    }

    if (state is RiveLoaded) {
      _onRiveLoaded(state);
      return RiveWidget(
        controller: state.controller,
        fit: Fit.contain,
      );
    }

    return const SizedBox.shrink();
  }

  @override
  Widget build(BuildContext context) {
    final loader = _fileLoader;
    if (loader == null) {
      return const SizedBox(
        width: 600,
        height: 250,
        child: Center(child: CircularProgressIndicator()),
      );
    }

    return RiveWidgetBuilder(
      key: ValueKey('bottom-rive-${_riveRebuildNonce}'),
      fileLoader: loader,
      controller: _buildRiveController,
      builder: _buildRiveState,
      onFailed: (error, stackTrace) {
        debugPrint('❌ Rive: Builder failure: $error');
      },
    );
  }

  // Helper methods for user feedback
  String _toUserFriendlyErrorMessage(
    Object error, {
    required String fallback,
  }) {
    final message = error.toString().toLowerCase();

    if (message.contains('permission') || message.contains('microphone')) {
      return 'Microphone access is required to record. Please enable it and try again.';
    }
    if (message.contains('401') ||
        message.contains('unauthorized') ||
        message.contains('forbidden') ||
        message.contains('invalid api key') ||
        message.contains('api key')) {
      return 'Audio service authentication failed. Please check the API key configuration and try again.';
    }
    if (message.contains('network') ||
        message.contains('socket') ||
        message.contains('timeout') ||
        message.contains('upload') ||
        message.contains('connection')) {
      return 'Network issue while processing audio. Please check your connection and try again.';
    }
    if (message.contains('empty text') ||
        message.contains('no speech') ||
        message.contains('empty')) {
      return 'We couldn\'t hear clear speech. Please record again.';
    }
    if (message.contains('recording file') ||
        message.contains('file not found') ||
        message.contains('file path') ||
        message.contains('0 bytes')) {
      return 'The recording could not be read. Please record again.';
    }
    if (message.contains('transcription failed')) {
      return 'We couldn\'t transcribe your recording right now. Please try again.';
    }
    if (message.contains('analysis failed') ||
        message.contains('invalid response format') ||
        message.contains('invalid response')) {
      return 'We couldn\'t analyze your recording right now. Please try again.';
    }

    return fallback;
  }

  void _showErrorSnackBar(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.red,
        duration: const Duration(seconds: 4),
        action: SnackBarAction(
          label: 'Dismiss',
          textColor: Colors.white,
          onPressed: () {
            ScaffoldMessenger.of(context).hideCurrentSnackBar();
          },
        ),
      ),
    );
  }

  void _showInfoSnackBar(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.blue,
        duration: const Duration(seconds: 3),
      ),
    );
  }
}
