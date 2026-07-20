import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pos_connect/data/api/api_client.dart';

class ContactInfo {
  final String email;
  final String whatsapp;
  final String address;

  const ContactInfo({required this.email, required this.whatsapp, required this.address});

  factory ContactInfo.fromJson(Map<String, dynamic> j) => ContactInfo(
        email:    j['email']    as String? ?? '',
        whatsapp: j['whatsapp'] as String? ?? '',
        address:  j['address']  as String? ?? '',
      );

  static const fallback = ContactInfo(
    email:    'support@pos-connect.ht',
    whatsapp: '',
    address:  'Port-au-Prince, Haïti',
  );

  String get displayPhone => whatsapp.isNotEmpty ? whatsapp : '';
}

final contactInfoProvider = FutureProvider<ContactInfo>((ref) async {
  try {
    final res = await dio.get('/api/public/contact-info');
    return ContactInfo.fromJson(res.data as Map<String, dynamic>);
  } catch (_) {
    return ContactInfo.fallback;
  }
});
