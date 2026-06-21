import 'package:flutter/material.dart';

// Lightweight shimmer-style skeleton placeholder shown while a network
// image is loading. No external package — just a gradient sweeping left
// to right on a loop via ShaderMask. Drop in anywhere an Image.network's
// loadingBuilder needs a placeholder.
class SkeletonBox extends StatefulWidget {
  const SkeletonBox({super.key});

  @override
  State<SkeletonBox> createState() => _SkeletonBoxState();
}

class _SkeletonBoxState extends State<SkeletonBox> with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        final dx = _controller.value;
        return ShaderMask(
          blendMode: BlendMode.srcATop,
          shaderCallback: (rect) {
            return LinearGradient(
              colors: const [
                Color(0xFF3C3541),
                Color(0xFF55485F),
                Color(0xFF3C3541),
              ],
              stops: const [0.0, 0.5, 1.0],
              begin: Alignment(-1 + dx * 2, 0),
              end: Alignment(0 + dx * 2, 0),
            ).createShader(rect);
          },
          child: Container(color: const Color(0xFF3C3541)),
        );
      },
    );
  }
}