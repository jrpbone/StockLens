import 'package:intl/intl.dart';

final pesoFormat = NumberFormat.currency(
  locale: 'en_PH',
  symbol: '₱',
  decimalDigits: 2,
);

String formatCentavos(int centavos) => pesoFormat.format(centavos / 100);
