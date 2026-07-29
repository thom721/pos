class ClientSabotageModel {
  final String id;
  final String nom;
  final String prenom;
  final String telephone;
  final String adresse;
  final String accountNumber;
  final String? warehouseId;
  final Map<String, String> extraFields;
  final bool isActive;
  final double balance;

  ClientSabotageModel({
    required this.id,
    required this.nom,
    required this.prenom,
    required this.telephone,
    required this.adresse,
    required this.accountNumber,
    this.warehouseId,
    this.extraFields = const {},
    this.isActive = true,
    this.balance = 0,
  });

  String get fullName => '$prenom $nom'.trim();

  factory ClientSabotageModel.fromJson(Map<String, dynamic> json) {
    final rawExtra = json['extra_fields'];
    Map<String, String> extra = const {};
    if (rawExtra is Map) {
      extra = rawExtra.map((k, v) => MapEntry(k.toString(), v?.toString() ?? ''));
    }
    return ClientSabotageModel(
      id: json['id']?.toString() ?? '',
      nom: json['nom']?.toString() ?? '',
      prenom: json['prenom']?.toString() ?? '',
      telephone: json['telephone']?.toString() ?? '',
      adresse: json['adresse']?.toString() ?? '',
      accountNumber: json['account_number']?.toString() ?? '',
      warehouseId: json['warehouse_id']?.toString(),
      extraFields: extra,
      isActive: json['is_active'] != false,
      balance: (json['balance'] as num?)?.toDouble() ?? 0,
    );
  }

  Map<String, dynamic> toJson() => {
        'nom': nom,
        'prenom': prenom,
        'telephone': telephone,
        'adresse': adresse,
        if (warehouseId != null) 'warehouse_id': warehouseId,
        if (extraFields.isNotEmpty) 'extra_fields': extraFields,
      };
}
