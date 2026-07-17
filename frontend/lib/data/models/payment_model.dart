class PaymentModel {
  final String id;
  final String referenceType;
  final String referenceId;
  final double amount;
  final String method;
  final DateTime createdAt;
  final String? userFullName;

  PaymentModel({
    required this.id,
    required this.referenceType,
    required this.referenceId,
    required this.amount,
    required this.method,
    required this.createdAt,
    this.userFullName,
  });

  factory PaymentModel.fromJson(Map<String, dynamic> json) {
    final user = json['user'] as Map<String, dynamic>?;
    return PaymentModel(
      id: json['id']?.toString() ?? '',
      referenceType: json['reference_type']?.toString() ?? '',
      referenceId: json['reference_id']?.toString() ?? '',
      amount: double.tryParse(json['amount']?.toString() ?? '0') ?? 0,
      method: json['method']?.toString() ?? 'CASH',
      createdAt:
          DateTime.tryParse(json['created_at']?.toString() ?? '')?.toLocal() ??
              DateTime.now(),
      userFullName: user != null
          ? '${user['fname'] ?? ''} ${user['lname'] ?? ''}'.trim()
          : null,
    );
  }

  String get methodLabel {
    switch (method.toUpperCase()) {
      case 'CASH':
        return 'Espèces';
      case 'BANK':
        return 'Virement';
      case 'MOBILE':
        return 'Mobile';
      default:
        return method;
    }
  }
}
