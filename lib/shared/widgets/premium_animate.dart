import 'package:flutter/material.dart';

enum AnimationType { fadeIn, slideIn, scaleIn }

class PremiumAnimate extends StatefulWidget {
  final Widget child;
  final AnimationType type;
  final Duration duration;
  final Duration delay;
  final Offset slideOffset;
  final double scaleOffset;
  final Curve curve;

  const PremiumAnimate({
    super.key,
    required this.child,
    this.type = AnimationType.fadeIn,
    this.duration = const Duration(milliseconds: 600),
    this.delay = Duration.zero,
    this.slideOffset = const Offset(0, 20),
    this.scaleOffset = 0.95,
    this.curve = Curves.easeOutQuart,
  });

  @override
  State<PremiumAnimate> createState() => _PremiumAnimateState();
}

class _PremiumAnimateState extends State<PremiumAnimate> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _opacity;
  late Animation<Offset> _slide;
  late Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: widget.duration);

    _opacity = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _controller, curve: widget.curve),
    );

    _slide = Tween<Offset>(begin: widget.slideOffset, end: Offset.zero).animate(
      CurvedAnimation(parent: _controller, curve: widget.curve),
    );

    _scale = Tween<double>(begin: widget.scaleOffset, end: 1.0).animate(
      CurvedAnimation(parent: _controller, curve: widget.curve),
    );

    Future.delayed(widget.delay, () {
      if (mounted) {
        _controller.forward();
      }
    });
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
        Widget current = Opacity(
          opacity: _opacity.value,
          child: child,
        );

        if (widget.type == AnimationType.slideIn) {
          current = Transform.translate(
            offset: _slide.value,
            child: current,
          );
        } else if (widget.type == AnimationType.scaleIn) {
          current = Transform.scale(
            scale: _scale.value,
            child: current,
          );
        }

        return current;
      },
      child: widget.child,
    );
  }
}
