import 'package:flutter/material.dart';

class InteractiveHover extends StatefulWidget {
  final Widget child;
  final double scale;
  final double elevation;
  final Duration duration;
  final Curve curve;
  final VoidCallback? onTap;
  final BorderRadius? borderRadius;

  const InteractiveHover({
    super.key,
    required this.child,
    this.scale = 1.02,
    this.elevation = 4.0,
    this.duration = const Duration(milliseconds: 200),
    this.curve = Curves.easeInOut,
    this.onTap,
    this.borderRadius,
  });

  @override
  State<InteractiveHover> createState() => _InteractiveHoverState();
}

class _InteractiveHoverState extends State<InteractiveHover> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedScale(
          scale: _isHovered ? widget.scale : 1.0,
          duration: widget.duration,
          curve: widget.curve,
          child: AnimatedPhysicalModel(
            duration: widget.duration,
            curve: widget.curve,
            shape: BoxShape.rectangle,
            borderRadius: widget.borderRadius ?? BorderRadius.zero,
            elevation: _isHovered ? widget.elevation : 0.0,
            color: Colors.transparent,
            shadowColor: Colors.black.withValues(alpha: 0.1),
            child: widget.child,
          ),
        ),
      ),
    );
  }
}
