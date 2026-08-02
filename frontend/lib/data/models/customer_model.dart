class CustomerModel {
  final String id;
  final String name;
  final String fname;
  final String? nif;
  final String phone;
  final String? email;
  final String address;
  final double creditLimit;
  // Solde de fidélisation — lecture seule, géré uniquement par le serveur
  // (jamais inclus dans toJson(), jamais éditable dans le formulaire client).
  final double loyaltyBalance;

  CustomerModel({
    required this.id,
    required this.name,
    this.fname = '',
    this.nif,
    required this.phone,
    this.email,
    required this.address,
    required this.creditLimit,
    this.loyaltyBalance = 0,
  });

  // Prénom + Nom si le prénom est renseigné, sinon juste Nom (clients créés
  // avant l'ajout du champ prénom — aucun découpage rétroactif tenté).
  String get fullName => fname.isEmpty ? name : '$fname $name';

  factory CustomerModel.fromJson(Map<String, dynamic> json) => CustomerModel(
        id: json['id']?.toString() ?? '',
        name: json['name']?.toString() ?? '',
        fname: json['fname']?.toString() ?? '',
        nif: json['nif']?.toString(),
        phone: json['phone']?.toString() ?? '',
        email: json['email']?.toString(),
        address: json['address']?.toString() ?? '',
        creditLimit:
            double.tryParse(json['credit_limit']?.toString() ?? '0') ?? 0,
        loyaltyBalance:
            double.tryParse(json['loyalty_balance']?.toString() ?? '0') ?? 0,
      );

  Map<String, dynamic> toJson() => {
        'name': name,
        'fname': fname,
        'nif': nif,
        'phone': phone,
        'email': email,
        'address': address,
        'credit_limit': creditLimit,
      };
}
