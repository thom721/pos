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

/// Clé de normalisation nom+prénom — aucune contrainte d'unicité n'existe
/// en base, donc plusieurs lignes peuvent légitimement porter le même nom
/// (créées séparément, notamment via la synchro hors-ligne). Insensible à
/// la casse et aux espaces superflus.
String customerNameKey(String fname, String name) =>
    '${fname.trim().toLowerCase()}|${name.trim().toLowerCase()}';

/// Ne garde qu'UN client par combinaison nom+prénom — pour l'affichage
/// uniquement (liste Clients, sélecteur de vente). Ne supprime rien en
/// base : un doublon peut être référencé par d'anciennes ventes, le
/// supprimer casserait leurs reçus/historique. Garde le premier rencontré.
List<CustomerModel> dedupCustomersByName(List<CustomerModel> customers) {
  final seen = <String>{};
  final result = <CustomerModel>[];
  for (final c in customers) {
    if (seen.add(customerNameKey(c.fname, c.name))) result.add(c);
  }
  return result;
}

/// Cherche un client existant avec exactement ce nom+prénom (avant création,
/// pour proposer de réutiliser un client déjà existant plutôt que d'en
/// créer un nouveau qui alimenterait encore le problème de doublons).
CustomerModel? findCustomerByName(
    List<CustomerModel> customers, String fname, String name) {
  final key = customerNameKey(fname, name);
  for (final c in customers) {
    if (customerNameKey(c.fname, c.name) == key) return c;
  }
  return null;
}
