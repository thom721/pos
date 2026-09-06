class ExpenseModel {
  final String id;
  final String description;
  final String? category;
  final double amount;
  final DateTime expenseDate;
  final String? warehouseId;
  final String? warehouseName;
  final String? userName;
  final DateTime createdAt;

  ExpenseModel({
    required this.id,
    required this.description,
    this.category,
    required this.amount,
    required this.expenseDate,
    this.warehouseId,
    this.warehouseName,
    this.userName,
    required this.createdAt,
  });

  factory ExpenseModel.fromJson(Map<String, dynamic> json) => ExpenseModel(
        id: json['id']?.toString() ?? '',
        description: json['description']?.toString() ?? '',
        category: json['category']?.toString(),
        amount: (json['amount'] as num?)?.toDouble() ?? 0,
        expenseDate: DateTime.parse(json['expense_date']),
        warehouseId: json['warehouse_id']?.toString(),
        warehouseName: json['warehouse_name']?.toString(),
        userName: json['user_name']?.toString(),
        createdAt: DateTime.parse(json['created_at']),
      );
}
