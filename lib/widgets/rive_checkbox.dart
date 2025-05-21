import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:rive/rive.dart' as rive;

// New Controller Class
class RiveCheckboxController {
  rive.SMITrigger? _trigger;

  // Called by _RiveCheckboxState to link the trigger
  void _setTrigger(rive.SMITrigger? trigger) {
    _trigger = trigger;
  }

  // Called by the parent to fire the animation
  void fire() {
    _trigger?.fire();
  }
}

class RiveCheckbox extends StatefulWidget {
  final bool isChecked;
  final ValueChanged<bool?>? onChanged;
  final double size;
  final RiveCheckboxController? controller; // Added controller

  const RiveCheckbox({
    super.key,
    required this.isChecked,
    required this.onChanged,
    this.size = 24.0,
    this.controller, // Added to constructor
  });

  @override
  State<RiveCheckbox> createState() => _RiveCheckboxState();
}

class _RiveCheckboxState extends State<RiveCheckbox> {
  rive.Artboard? _riveArtboard;
  rive.StateMachineController? _stateMachineController;
  rive.SMITrigger? _riveTrigger;

  bool _isRiveLoaded = false;
  bool _loadError = false;

  @override
  void initState() {
    super.initState();
    _loadRiveFile().then((_) {
      // Ensure controller is linked after _riveTrigger is potentially set
      if (_riveTrigger != null) {
        widget.controller?._setTrigger(_riveTrigger);
      }
    });
  }

  @override
  void didUpdateWidget(RiveCheckbox oldWidget) {
    super.didUpdateWidget(oldWidget);
    // If the controller instance changes or is newly provided, update its trigger link.
    // Also, if the Rive animation reloads (e.g. _riveTrigger changes), relink.
    if (widget.controller != oldWidget.controller ||
        (_riveTrigger != null && widget.controller?._trigger != _riveTrigger)) {
      widget.controller?._setTrigger(_riveTrigger);
    }
  }

  Future<void> _loadRiveFile() async {
    try {
      final data = await rootBundle.load('assets/animations/tick.riv');
      final file = rive.RiveFile.import(data);
      final artboard = file.mainArtboard;

      _stateMachineController = rive.StateMachineController.fromArtboard(
        artboard,
        'State Machine 1',
      );

      if (_stateMachineController != null) {
        artboard.addController(_stateMachineController!);
        final smiInput = _stateMachineController!.findSMI('isTicked');
        if (smiInput is rive.SMITrigger) {
          _riveTrigger = smiInput;
          // Link to controller if already available (e.g. on hot reload with state)
          widget.controller?._setTrigger(_riveTrigger);
        } else {
          debugPrint(
              "Rive input 'isTicked' was found but is not an SMITrigger. Actual type: ${smiInput?.runtimeType}");
          _loadError = true;
        }
      } else {
        debugPrint("Rive 'State Machine 1' not found");
        _loadError = true;
      }

      if (mounted) {
        setState(() {
          _riveArtboard = artboard;
          _isRiveLoaded = true;
          _loadError = _loadError ||
              _stateMachineController == null ||
              (_stateMachineController != null && _riveTrigger == null);
        });
      }
    } catch (e) {
      debugPrint('Error loading Rive file: $e');
      if (mounted) {
        setState(() {
          _isRiveLoaded = true;
          _loadError = true;
        });
      }
    }
  }

  @override
  void dispose() {
    _stateMachineController?.dispose();
    // It might be good to clear the controller's trigger link if the RiveCheckbox is disposed
    // widget.controller?._setTrigger(null); // Though controller lifecycle is managed by parent
    super.dispose();
  }

  void _handleTap() {
    if (_loadError || !_isRiveLoaded && _riveArtboard == null) {
      if (widget.onChanged != null) {
        widget.onChanged!(!widget.isChecked);
      }
      return;
    }

    if (widget.onChanged != null) {
      _riveTrigger?.fire();
      widget.onChanged!(!widget.isChecked);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_isRiveLoaded) {
      return SizedBox(
        width: widget.size,
        height: widget.size,
        child: const Center(
            child: CircularProgressIndicator(
          strokeWidth: 2.0,
        )),
      );
    }

    if (_loadError || _riveArtboard == null) {
      return GestureDetector(
        onTap: _handleTap,
        child: Container(
          width: widget.size,
          height: widget.size,
          decoration: BoxDecoration(
            border: Border.all(color: Colors.grey),
            borderRadius: BorderRadius.circular(4),
          ),
          child: widget.isChecked
              ? Icon(Icons.check_box,
                  size: widget.size * 0.8,
                  color: Theme.of(context).primaryColor)
              : Icon(Icons.check_box_outline_blank,
                  size: widget.size * 0.8, color: Colors.grey),
        ),
      );
    }

    return GestureDetector(
      onTap: _handleTap,
      child: SizedBox(
        width: widget.size,
        height: widget.size,
        child: rive.Rive(
          artboard: _riveArtboard!,
          fit: BoxFit.contain,
        ),
      ),
    );
  }
}
