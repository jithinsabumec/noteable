import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:rive/rive.dart';

class RiveCheckbox extends StatefulWidget {
  final bool isChecked;
  final ValueChanged<bool>? onChanged;
  final double size;

  const RiveCheckbox({
    super.key,
    required this.isChecked,
    required this.onChanged,
    this.size = 24.0,
  });

  @override
  State<RiveCheckbox> createState() => _RiveCheckboxState();
}

class _RiveCheckboxState extends State<RiveCheckbox> {
  // Rive controller
  StateMachineController? _controller;
  RiveAnimation? _animation;

  // Rive inputs
  SMIInput<bool>? _isTickedInput;

  // Loading states
  bool _isLoading = true;
  bool _hasError = false;

  @override
  void initState() {
    super.initState();
    _loadRiveAnimation();
  }

  @override
  void didUpdateWidget(RiveCheckbox oldWidget) {
    super.didUpdateWidget(oldWidget);

    // Update Rive state when widget state changes
    if (widget.isChecked != oldWidget.isChecked) {
      _updateRiveState();
    }
  }

  void _loadRiveAnimation() {
    try {
      _animation = RiveAnimation.asset(
        'assets/animations/tick.riv',
        artboard: 'Artboard',
        fit: BoxFit.contain,
        onInit: _onRiveInit,
      );

      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('Error loading Rive animation: $e');
      if (mounted) {
        setState(() {
          _isLoading = false;
          _hasError = true;
        });
      }
    }
  }

  void _onRiveInit(Artboard artboard) {
    try {
      debugPrint('Rive artboard initialized');

      // Try different state machine names
      _controller =
          StateMachineController.fromArtboard(artboard, 'State Machine 1');

      if (_controller == null) {
        debugPrint('State Machine 1 not found, trying Layer 1');
        _controller = StateMachineController.fromArtboard(artboard, 'Layer 1');
      }

      if (_controller == null) {
        debugPrint('Layer 1 not found, trying default state machine');
        // Try to get any available state machine
        final stateMachines = artboard.stateMachines;
        debugPrint(
            'Available state machines: ${stateMachines.map((sm) => sm.name).toList()}');
        if (stateMachines.isNotEmpty) {
          _controller = StateMachineController.fromArtboard(
              artboard, stateMachines.first.name);
          debugPrint('Using state machine: ${stateMachines.first.name}');
        }
      }

      if (_controller != null) {
        artboard.addController(_controller!);
        debugPrint('State machine controller added');

        // List all available inputs
        final inputs = _controller!.inputs;
        debugPrint(
            'Available inputs: ${inputs.map((input) => '${input.name} (${input.runtimeType})').toList()}');

        // Find the isTicked boolean input
        _isTickedInput = _controller!.findInput<bool>('isTicked');

        if (_isTickedInput != null) {
          debugPrint('Found isTicked input');
          // Set initial state
          _updateRiveState();
        } else {
          debugPrint('isTicked input not found, trying alternative names');
          // Try alternative input names
          _isTickedInput = _controller!.findInput<bool>('isChecked');
          if (_isTickedInput == null) {
            _isTickedInput = _controller!.findInput<bool>('checked');
          }
          if (_isTickedInput == null) {
            _isTickedInput = _controller!.findInput<bool>('ticked');
          }
          if (_isTickedInput != null) {
            debugPrint('Found alternative input: ${_isTickedInput!.name}');
            _updateRiveState();
          }
        }
      } else {
        debugPrint('No state machine found');
        if (mounted) {
          setState(() {
            _hasError = true;
          });
        }
      }
    } catch (e) {
      debugPrint('Error in onRiveInit: $e');
      if (mounted) {
        setState(() {
          _hasError = true;
        });
      }
    }
  }

  void _updateRiveState() {
    if (_isTickedInput != null) {
      _isTickedInput!.value = widget.isChecked;
      debugPrint('Updated isTicked to: ${widget.isChecked}');
    }
  }

  void _handleTap() {
    if (widget.onChanged != null) {
      widget.onChanged!(!widget.isChecked);
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Show loading spinner
    if (_isLoading) {
      return SizedBox(
        width: widget.size,
        height: widget.size,
        child: const Center(
          child: CircularProgressIndicator(strokeWidth: 2.0),
        ),
      );
    }

    // Show fallback UI if error or animation is null
    if (_hasError || _animation == null) {
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
        child: _animation!,
      ),
    );
  }
}
