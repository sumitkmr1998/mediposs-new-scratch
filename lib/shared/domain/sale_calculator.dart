import '../providers/cart_provider.dart';

class SaleTotals {
  final double subtotal;
  final double discount;
  final double taxRate;
  final double taxAmount;
  final double total;
  final double totalRounded;

  SaleTotals({
    required this.subtotal,
    required this.discount,
    required this.taxRate,
    required this.taxAmount,
    required this.total,
    required this.totalRounded,
  });
}

class SaleCalculator {
  static double calculateSubtotal(List<CartItem> items) {
    return items.fold(0.0, (sum, item) => sum + item.lineTotal);
  }

  static SaleTotals calculate({
    required List<CartItem> items,
    required double discountAmount,
    required double storeTaxRate,
    required bool isClinicalDispense,
    required bool isCompositionScheme,
  }) {
    final subtotal = calculateSubtotal(items);
    final taxRate = (isClinicalDispense || isCompositionScheme)
        ? 0.0
        : storeTaxRate / 100.0;
    final taxAmount = (subtotal - discountAmount).clamp(0.0, double.infinity) * taxRate;
    final total = (subtotal - discountAmount + taxAmount).clamp(0.0, double.infinity);
    final totalRounded = (total * 10).round() / 10.0;

    return SaleTotals(
      subtotal: subtotal,
      discount: discountAmount,
      taxRate: taxRate,
      taxAmount: taxAmount,
      total: total,
      totalRounded: totalRounded,
    );
  }
}
