import 'package:flutter/material.dart';
import '../../../../theme/app_theme.dart';

class LocationBadge extends StatelessWidget {
  final String location;

  const LocationBadge({super.key, required this.location});

  @override
  Widget build(BuildContext context) {
    final cleanLoc = location.trim().toLowerCase();
    String text = location;
    Color bg = Colors.grey.withValues(alpha: 0.1);
    Color fg = Colors.grey;

    if (cleanLoc == 'clinic' || cleanLoc == 'main' || cleanLoc == 'hub' || cleanLoc == 'clinic dispense') {
      text = 'Clinic Dispense';
      bg = AppTheme.indigo.withValues(alpha: 0.1);
      fg = AppTheme.indigo;
    } else if (cleanLoc == 'store' || cleanLoc == 'store pos') {
      text = 'Store POS';
      bg = const Color(0xFF14B8A6).withValues(alpha: 0.1);
      fg = const Color(0xFF14B8A6);
    } else if (cleanLoc == 'bulkclinic' || cleanLoc == 'clinic bulk') {
      text = 'Clinic Bulk';
      bg = Colors.deepPurple.withValues(alpha: 0.1);
      fg = Colors.deepPurple;
    } else if (cleanLoc == 'bulkstore' || cleanLoc == 'store bulk') {
      text = 'Store Bulk';
      bg = Colors.teal.withValues(alpha: 0.1);
      fg = Colors.teal;
    } else if (cleanLoc.isEmpty) {
      text = 'Hub/Clinic';
      bg = AppTheme.indigo.withValues(alpha: 0.1);
      fg = AppTheme.indigo;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: fg.withValues(alpha: 0.3), width: 1),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: fg,
          fontWeight: FontWeight.bold,
          fontSize: 12,
        ),
      ),
    );
  }
}
