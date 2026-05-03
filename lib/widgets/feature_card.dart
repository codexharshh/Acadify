import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../Services/theme_provider.dart';

class FeatureCard extends StatefulWidget {
  final String title;
  final IconData icon;
  final Widget page;

  const FeatureCard({
    super.key,
    required this.title,
    required this.icon,
    required this.page,
  });

  @override
  State<FeatureCard> createState() => _FeatureCardState();
}

class _FeatureCardState extends State<FeatureCard> {
  bool _pressed = false;
  ThemeProvider get _t => Provider.of<ThemeProvider>(context, listen: false);

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => setState(() => _pressed = true),
      onTapUp: (_) {
        setState(() => _pressed = false);
        Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => widget.page),
        );
      },
      onTapCancel: () => setState(() => _pressed = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        decoration: BoxDecoration(
          color: _t.cardColor,
          borderRadius: BorderRadius.circular(24),
          boxShadow: _pressed
              ? [
                  BoxShadow(
                      color: _t.shadowDark,
                      offset: const Offset(2, 2),
                      blurRadius: 5),
                  BoxShadow(
                      color: _t.shadowLight,
                      offset: const Offset(-2, -2),
                      blurRadius: 5),
                ]
              : [
                  BoxShadow(
                      color: _t.shadowDark,
                      offset: const Offset(7, 7),
                      blurRadius: 15,
                      spreadRadius: 1),
                  BoxShadow(
                      color: _t.shadowLight,
                      offset: const Offset(-7, -7),
                      blurRadius: 15,
                      spreadRadius: 1),
                ],
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 120),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: _t.cardColor,
                shape: BoxShape.circle,
                boxShadow: _pressed
                    ? []
                    : [
                        BoxShadow(
                            color: _t.shadowDark,
                            offset: const Offset(4, 4),
                            blurRadius: 8),
                        BoxShadow(
                            color: _t.shadowLight,
                            offset: const Offset(-4, -4),
                            blurRadius: 8),
                      ],
              ),
              child: Icon(widget.icon, size: 36, color: _t.accentColor),
            ),
            const SizedBox(height: 16),
            Text(
              widget.title,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.bold,
                color: _t.textPrimary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
