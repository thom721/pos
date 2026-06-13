class DebtModel {
  final String id;
  final String referenceType;
  final String referenceId;
  final String partnerType;
  final String partnerId;
  final double totalAmount;
  final double paidAmount;
  final double balance;
  final String status;
  final DateTime createdAt;
  final String? partnerName;

  DebtModel({
    required this.id,
    required this.referenceType,
    required this.referenceId,
    required this.partnerType,
    required this.partnerId,
    required this.totalAmount,
    required this.paidAmount,
    required this.balance,
    required this.status,
    required this.createdAt,
    this.partnerName,
  });

  factory DebtModel.fromJson(Map<String, dynamic> json) => DebtModel(
        id: json['id']?.toString() ?? '',
        referenceType: json['reference_type']?.toString() ?? '',
        referenceId: json['reference_id']?.toString() ?? '',
        partnerType: json['partner_type']?.toString() ?? '',
        partnerId: json['partner_id']?.toString() ?? '',
        totalAmount:
            double.tryParse(json['total_amount']?.toString() ?? '0') ?? 0,
        paidAmount:
            double.tryParse(json['paid_amount']?.toString() ?? '0') ?? 0,
        balance: double.tryParse(json['balance']?.toString() ?? '0') ?? 0,
        status: json['status']?.toString() ?? 'UNPAID',
        createdAt:
            DateTime.tryParse(json['created_at']?.toString() ?? '') ??
                DateTime.now(),
        partnerName: json['partner_name']?.toString(),
      );
}
