import 'package:flutter/material.dart';
import 'package:rive/rive.dart';

class RiveCheckbox extends StatefulWidget {
  final bool isChecked;
  final ValueChanged<bool?> onChanged;
  final double size;

  const RiveCheckbox({
    super.key,
    required this.isChecked,
    required this.onChanged,
    this.size = 24,
  });

  @override
  State<RiveCheckbox> createState() => _RiveCheckboxState();
}

class _RiveCheckboxState extends State<RiveCheckbox> {
  FileLoader? _fileLoader;
  RiveWidgetController? _riveController;
  StateMachine? _stateMachine;
  BooleanInput? _isCheckedInput;

  @override
  void initState() {
    super.initState();
    _fileLoader = FileLoader.fromAsset(
      'assets/animations/todo_tick.riv',
      riveFactory: Factory.rive,
    );
  }

  String _normalizeInputName(String name) =>
      name.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');

  BooleanInput? _findBoolInputWithAliases(List<String> aliases) {
    final sm = _stateMachine;
    if (sm == null) return null;

    final normalizedAliases = aliases.map(_normalizeInputName).toSet();
    for (final input in sm.inputs.whereType<BooleanInput>()) {
      if (normalizedAliases.contains(_normalizeInputName(input.name))) {
        return input;
      }
    }
    return null;
  }

  void _bindCheckboxInput() {
    if (_stateMachine == null) return;

    _isCheckedInput =
        _stateMachine!.boolean('isTicked') ??
        _stateMachine!.boolean('active') ??
        _stateMachine!.boolean('checked') ??
        _stateMachine!.boolean('isChecked') ??
        _stateMachine!.boolean('Check') ??
        _findBoolInputWithAliases([
          'isTicked',
          'active',
          'checked',
          'isChecked',
          'Check'
        ]);

    if (_isCheckedInput != null) {
      _isCheckedInput!.value = widget.isChecked;
      debugPrint('Found isTicked input');
      debugPrint('Updated isTicked to: ${_isCheckedInput!.value}');
    }
  }

  RiveWidgetController _buildController(File file) {
    final selectors = <StateMachineSelector>[
      const StateMachineNamed('State Machine 1'),
      const StateMachineNamed('Layer 1'),
      const StateMachineDefault(),
    ];

    Object? lastError;
    for (final selector in selectors) {
      try {
        return RiveWidgetController(
          file,
          artboardSelector: const ArtboardDefault(),
          stateMachineSelector: selector,
        );
      } catch (error) {
        lastError = error;
      }
    }

    throw Exception('Failed to create checkbox Rive controller: $lastError');
  }

  void _onLoaded(RiveLoaded state) {
    if (identical(_riveController, state.controller)) {
      return;
    }

    _riveController = state.controller;
    _stateMachine = state.controller.stateMachine;

    debugPrint('Rive artboard initialized');
    debugPrint('State machine controller added');
    debugPrint(
      'Available inputs: ${_stateMachine!.inputs.map((i) => '${i.name} (${i.runtimeType})').toList()}',
    );

    _bindCheckboxInput();
  }

  @override
  void didUpdateWidget(RiveCheckbox oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isChecked != oldWidget.isChecked && _isCheckedInput != null) {
      _isCheckedInput!.value = widget.isChecked;
      debugPrint('Updated isTicked to: ${_isCheckedInput!.value}');
    }
  }

  @override
  void dispose() {
    _fileLoader?.dispose();
    _isCheckedInput = null;
    _stateMachine = null;
    _riveController = null;
    super.dispose();
  }

  Widget _placeholder() {
    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: const Color(0xFF1A1A1A), width: 1.2),
        borderRadius: BorderRadius.circular(4),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final loader = _fileLoader;
    if (loader == null) {
      return SizedBox(width: widget.size, height: widget.size, child: _placeholder());
    }

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () {
        final next = !widget.isChecked;
        if (_isCheckedInput != null) {
          _isCheckedInput!.value = next;
        }
        widget.onChanged(next);
      },
      child: SizedBox(
        width: widget.size,
        height: widget.size,
        child: RiveWidgetBuilder(
          fileLoader: loader,
          controller: _buildController,
          builder: (context, state) {
            if (state is RiveLoaded) {
              _onLoaded(state);
              return Transform.scale(
                scale: 1.2,
                child: RiveWidget(
                  controller: state.controller,
                  fit: Fit.contain,
                ),
              );
            }
            if (state is RiveFailed) {
              return _placeholder();
            }
            return _placeholder();
          },
        ),
      ),
    );
  }
}
