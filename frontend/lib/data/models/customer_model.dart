class CustomerModel {
  final String id;
  final String name;
  final String phone;
  final String? email;
  final String address;
  final double creditLimit;

  CustomerModel({
    required this.id,
    required this.name,
    required this.phone,
    this.email,
    required this.address,
    required this.creditLimit,
  });

  factory CustomerModel.fromJson(Map<String, dynamic> json) => CustomerModel(
        id: json['id']?.toString() ?? '',
        name: json['name']?.toString() ?? '',
        phone: json['phone']?.toString() ?? '',
        email: json['email']?.toString(),
        address: json['address']?.toString() ?? '',
        creditLimit:
            double.tryParse(json['credit_limit']?.toString() ?? '0') ?? 0,
      );

  Map<String, dynamic> toJson() => {
        'name': name,
        'phone': phone,
        'email': email,
        'address': address,
        'credit_limit': creditLimit,
      };
}
