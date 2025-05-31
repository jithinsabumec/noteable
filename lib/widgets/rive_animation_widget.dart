import 'package:flutter/material.dart';
import 'package:rive/rive.dart';

class RiveAnimationWidget extends StatefulWidget {
  const RiveAnimationWidget({super.key});

  @override
  State<RiveAnimationWidget> createState() => _RiveAnimationWidgetState();
}

class _RiveAnimationWidgetState extends State<RiveAnimationWidget> {
  // Rive controller
  late StateMachineController controller;
  late RiveAnimation anim;

  @override
  void initState() {
    super.initState();
    anim = RiveAnimation.asset('assets/animations/bottom_bar.riv',
        artboard: 'Artboard', fit: BoxFit.contain, onInit: onRiveInit);
  }

  void onRiveInit(Artboard artboard) {
    controller = StateMachineController.fromArtboard(artboard, 'Record')!;
    artboard.addController(controller);
  }

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return anim;
  }
}
