import '../../../shared/models/sale.dart';
import '../../../shared/providers/sales_provider.dart';
import '../../../shared/services/sales_fact_service.dart';
import '../../../shared/utils/consumption_aggregator.dart';

/// Shared helper for Android analysis hub — prefer facts, else ranged sales.
ConsumptionResult loadAnalysisConsumption(
  SalesProvider salesProvider, {
  int days = 90,
}) {
  try {
    if (SalesFactService.instance.hasAnyFacts) {
      return SalesFactService.instance.consumptionLastDays(days);
    }
  } catch (_) {}
  final List<Sale> window = salesProvider.salesForAnalytics(days: days);
  return ConsumptionAggregator.build(window);
}
