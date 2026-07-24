import 'package:intl/intl.dart';
import 'package:pos_connect/core/date_utils.dart' show parseApiDate;

class ProformaItemModel {
  final String id;
  final String? productId;
  final String name;
  final double quantity;
  final double unitPrice;
  final double subtotal;

  ProformaItemModel({
    required this.id,
    this.productId,
    required this.name,
    required this.quantity,
    required this.unitPrice,
    required this.subtotal,
  });

  factory ProformaItemModel.fromJson(Map<String, dynamic> j) => ProformaItemModel(
        id: j['id']?.toString() ?? '',
        productId: j['product_id']?.toString(),
        name: j['name']?.toString() ?? '',
        quantity: double.tryParse(j['quantity']?.toString() ?? '0') ?? 0,
        unitPrice: double.tryParse(j['unit_price']?.toString() ?? '0') ?? 0,
        subtotal: double.tryParse(j['subtotal']?.toString() ?? '0') ?? 0,
      );

  Map<String, dynamic> toJson() => {
        'product_id': productId,
        'name': name,
        'quantity': quantity,
        'unit_price': unitPrice,
        'subtotal': subtotal,
      };
}

class ProformaModel {
  final String id;
  final String reference;
  final DateTime date;
  final String? clientId;
  final String? clientName;
  final double discount;
  final String? notes;
  final String currency;
  String status;
  final List<ProformaItemModel> items;
  final DateTime createdAt;

  ProformaModel({
    required this.id,
    required this.reference,
    required this.date,
    this.clientId,
    this.clientName,
    this.discount = 0,
    this.notes,
    this.currency = 'HTG',
    this.status = 'draft',
    required this.items,
    required this.createdAt,
  });

  double get subtotal => items.fold(0, (s, i) => s + i.subtotal);
  double get total => subtotal - discount;

  factory ProformaModel.fromJson(Map<String, dynamic> j) => ProformaModel(
        id: j['id']?.toString() ?? '',
        reference: j['reference']?.toString() ?? '',
        date: parseApiDate(j['date']?.toString()),
        clientId: j['client_id']?.toString(),
        clientName: j['client_name']?.toString(),
        discount: double.tryParse(j['discount']?.toString() ?? '0') ?? 0,
        notes: j['notes']?.toString(),
        currency: j['currency']?.toString() ?? 'HTG',
        status: j['status']?.toString() ?? 'draft',
        items: (j['items'] as List? ?? [])
            .map((e) => ProformaItemModel.fromJson(e))
            .toList(),
        createdAt: parseApiDate(j['created_at']?.toString()),
      );
}
