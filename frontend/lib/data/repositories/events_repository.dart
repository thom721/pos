import 'package:pos_connect/data/api/api_client.dart';
import 'package:pos_connect/data/models/proforma_model.dart';
import 'package:pos_connect/data/models/invoice_model.dart';

class EventsRepository {
  // ── Proformas ────────────────────────────────────────────────────────────

  Future<List<ProformaModel>> getProformas({int page = 1, int limit = 50}) async {
    final res = await dio.get('/api/proformas/',
        queryParameters: {'page': page, 'limit': limit});
    final data = res.data['data'] as List? ?? [];
    return data.map((e) => ProformaModel.fromJson(e)).toList();
  }

  Future<ProformaModel> createProforma(Map<String, dynamic> data) async {
    final res = await dio.post('/api/proformas/', data: data);
    return ProformaModel.fromJson(res.data);
  }

  Future<ProformaModel> updateProforma(
      String id, Map<String, dynamic> data) async {
    final res = await dio.put('/api/proformas/$id', data: data);
    return ProformaModel.fromJson(res.data);
  }

  Future<void> deleteProforma(String id) async {
    await dio.delete('/api/proformas/$id');
  }

  // ── Invoices ─────────────────────────────────────────────────────────────

  Future<List<InvoiceModel>> getInvoices({int page = 1, int limit = 50}) async {
    final res = await dio.get('/api/invoices/',
        queryParameters: {'page': page, 'limit': limit});
    final data = res.data['data'] as List? ?? [];
    return data.map((e) => InvoiceModel.fromJson(e)).toList();
  }

  Future<InvoiceModel> createInvoice(Map<String, dynamic> data) async {
    final res = await dio.post('/api/invoices/', data: data);
    return InvoiceModel.fromJson(res.data);
  }

  Future<InvoiceModel> updateInvoice(
      String id, Map<String, dynamic> data) async {
    final res = await dio.put('/api/invoices/$id', data: data);
    return InvoiceModel.fromJson(res.data);
  }

  Future<InvoiceModel> recordPayment(String id, double amount) async {
    final res = await dio
        .post('/api/invoices/$id/payment', data: {'amount': amount});
    return InvoiceModel.fromJson(res.data);
  }

  Future<void> deleteInvoice(String id) async {
    await dio.delete('/api/invoices/$id');
  }
}
