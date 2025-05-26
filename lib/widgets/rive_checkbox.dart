import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:rive/rive.dart' as rive;

// New Controller Class
class RiveCheckboxController {
  rive.SMIBool? _isTickedInput;
  rive.SMITrigger? _checkTrigger;
  rive.SMITrigger? _uncheckTrigger;
  bool _isChecked = false;

  // Called by _RiveCheckboxState to link the inputs
  void _setInputs({
    rive.SMIBool? isTickedInput,
    rive.SMITrigger? checkTrigger,
    rive.SMITrigger? uncheckTrigger,
    required bool initialState,
  }) {
    _isTickedInput = isTickedInput;
    _checkTrigger = checkTrigger;
    _uncheckTrigger = uncheckTrigger;
    _isChecked = initialState;

    // Initialize the state
    if (_isTickedInput != null) {
      _isTickedInput!.value = _isChecked;
    }
  }

  // Called by the parent to fire the animation
  void fire() {
    if (_isChecked) {
      _uncheckTrigger?.fire();
    } else {
      _checkTrigger?.fire();
    }
    if (_isTickedInput != null) {
      _isChecked = !_isChecked;
      _isTickedInput!.value = _isChecked;
    }
  }

  // Method to update the state without animation
  void updateState(bool isChecked) {
    _isChecked = isChecked;
    if (_isTickedInput != null) {
      _isTickedInput!.value = isChecked;
    }
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
  rive.SMIBool? _isTickedInput;
  rive.SMITrigger? _checkTrigger;
  rive.SMITrigger? _uncheckTrigger;

  bool _isRiveLoaded = false;
  bool _loadError = false;

  @override
  void initState() {
    super.initState();
    _loadRiveFile();
  }

  @override
  void didUpdateWidget(RiveCheckbox oldWidget) {
    super.didUpdateWidget(oldWidget);

    // If checked state changed externally, update the Rive animation state
    if (widget.isChecked != oldWidget.isChecked) {
      _updateRiveState();
    }

    // If the controller instance changes, relink the inputs
    if (widget.controller != oldWidget.controller &&
        _isRiveLoaded &&
        !_loadError) {
      _linkController();
    }
  }

  void _updateRiveState() {
    // Update the is_ticked input directly
    if (_isTickedInput != null) {
      _isTickedInput!.value = widget.isChecked;
    }

    // Also update the controller's state
    widget.controller?.updateState(widget.isChecked);
  }

  void _linkController() {
    // Link the controller to the Rive inputs
    if (widget.controller != null && _isTickedInput != null) {
      widget.controller!._setInputs(
        isTickedInput: _isTickedInput,
        checkTrigger: _checkTrigger,
        uncheckTrigger: _uncheckTrigger,
        initialState: widget.isChecked,
      );
    }
  }

  Future<void> _loadRiveFile() async {
    try {
      final data = await rootBundle.load('assets/animations/todo_tick.riv');
      final file = rive.RiveFile.import(data);
      final artboard = file.mainArtboard;

      _stateMachineController = rive.StateMachineController.fromArtboard(
        artboard,
        'State Machine 1',
      );

      if (_stateMachineController != null) {
        artboard.addController(_stateMachineController!);

        // Find the isTicked boolean input (updated from is_ticked to isTicked)
        final isTickedInput = _stateMachineController!.findSMI('isTicked');
        if (isTickedInput is rive.SMIBool) {
          _isTickedInput = isTickedInput;
          // Set initial state
          _isTickedInput!.value = widget.isChecked;
        } else {
          debugPrint(
              "Rive input 'isTicked' was not found or is not an SMIBool");
        }

        // Find the check trigger
        final checkTrigger = _stateMachineController!.findSMI('check');
        if (checkTrigger is rive.SMITrigger) {
          _checkTrigger = checkTrigger;
        } else {
          debugPrint(
              "Rive trigger 'check' was not found or is not an SMITrigger");
        }

        // Find the uncheck trigger
        final uncheckTrigger = _stateMachineController!.findSMI('uncheck');
        if (uncheckTrigger is rive.SMITrigger) {
          _uncheckTrigger = uncheckTrigger;
        } else {
          debugPrint(
              "Rive trigger 'uncheck' was not found or is not an SMITrigger");
        }

        // Link with controller if available
        _linkController();
      } else {
        debugPrint("Rive 'State Machine 1' not found");
        _loadError = true;
      }

      if (mounted) {
        setState(() {
          _riveArtboard = artboard;
          _isRiveLoaded = true;
          _loadError = _loadError || _stateMachineController == null;
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
    super.dispose();
  }

  void _handleTap() {
    if (_loadError || !_isRiveLoaded) {
      if (widget.onChanged != null) {
        widget.onChanged!(!widget.isChecked);
      }
      return;
    }

    if (widget.onChanged != null) {
      // First update the boolean state
      if (_isTickedInput != null) {
        _isTickedInput!.value = !widget.isChecked;
      }

      // Then trigger the appropriate animation
      if (widget.isChecked) {
        _uncheckTrigger?.fire();
      } else {
        _checkTrigger?.fire();
      }

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
