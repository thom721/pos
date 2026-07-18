import 'package:flutter_test/flutter_test.dart';
import 'package:pos_connect/data/models/sale_model.dart';

void main() {
  group('SaleModel deduplication', () {
    test('items avec ids dupliqués sont dédupliqués', () {
      final json = {
        'id': 'sale-1',
        'reference': 'VNT-001',
        'total_amount': 100,
        'discount': 0,
        'final_amount': 100,
        'paid_amount': 100,
        'status': 'PAID',
        'created_at': '2024-01-01T10:00:00',
        'items': [
          {'id': 'item-1', 'product_id': 'p1', 'quantity': 2, 'unit_price': 50, 'subtotal': 100},
          {'id': 'item-1', 'product_id': 'p1', 'quantity': 2, 'unit_price': 50, 'subtotal': 100}, // doublon
          {'id': 'item-2', 'product_id': 'p2', 'quantity': 1, 'unit_price': 0, 'subtotal': 0},
        ],
        'payments': [
          {'id': 'pay-1', 'amount': 100, 'method': 'CASH', 'created_at': '2024-01-01T10:00:00'},
          {'id': 'pay-1', 'amount': 100, 'method': 'CASH', 'created_at': '2024-01-01T10:00:00'}, // doublon
        ],
      };
      final sale = SaleModel.fromJson(json);
      expect(sale.items.length, equals(2));    // dédupliqué
      expect(sale.payments.length, equals(1)); // dédupliqué
    });

    test('items sans id sont exclus', () {
      final json = {
        'id': 'sale-2', 'reference': 'VNT-002',
        'total_amount': 0, 'discount': 0, 'final_amount': 0, 'paid_amount': 0,
        'status': 'PAID', 'created_at': '2024-01-01T10:00:00',
        'items': [
          {'id': '', 'product_id': 'p1', 'quantity': 1, 'unit_price': 10, 'subtotal': 10},
        ],
        'payments': [],
      };
      final sale = SaleModel.fromJson(json);
      expect(sale.items.length, equals(0)); // id vide exclu
    });
  });
}
