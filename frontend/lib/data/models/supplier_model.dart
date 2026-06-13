class SupplierModel {
  final String id;
  final String name;
  final String? phone;
  final String? email;
  final String? address;

  SupplierModel({
    required this.id,
    required this.name,
    this.phone,
    this.email,
    this.address,
  });

  factory SupplierModel.fromJson(Map<String, dynamic> json) => SupplierModel(
        id: json['id']?.toString() ?? '',
        name: json['name']?.toString() ?? '',
        phone: json['phone']?.toString(),
        email: json['email']?.toString(),
        address: json['address']?.toString(),
      );

  Map<String, dynamic> toJson() => {
        'name': name,
        'phone': phone,
        'email': email,
        'address': address,
      };
}
