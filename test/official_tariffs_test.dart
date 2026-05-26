import 'package:flutter_test/flutter_test.dart';
import 'package:gestia_project/data/official_tariffs.dart';

void main() {
  testWidgets('Charge le catalogue officiel des tarifs', (tester) async {
    final tariffs = await OfficialTariffCatalog.load();

    expect(tariffs, isNotEmpty);
    expect(
      tariffs.any((tariff) => tariff.receiptType == RevenueReceiptType.impot),
      isTrue,
    );
    expect(
      tariffs.any((tariff) => tariff.receiptType == RevenueReceiptType.taxe),
      isTrue,
    );
    expect(
      tariffs.any(
        (tariff) => tariff.receiptType == RevenueReceiptType.redevance,
      ),
      isTrue,
    );
  });
}
