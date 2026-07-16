import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:pos_connect/data/models/warehouse_model.dart';
import 'package:pos_connect/data/repositories/warehouse_repository.dart';

const _kActiveWarehouseKey = 'active_warehouse';

// ── List of all warehouses for the tenant ────────────────────────────────────

final warehouseListProvider = FutureProvider.autoDispose<List<WarehouseModel>>((ref) async {
  return WarehouseRepository().listWarehouses();
});

// ── Active warehouse (persisted in SharedPreferences) ────────────────────────

class ActiveWarehouseNotifier extends StateNotifier<WarehouseModel?> {
  ActiveWarehouseNotifier() : super(null) {
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_kActiveWarehouseKey);
    if (raw != null) {
      try {
        state = WarehouseModel.fromJson(jsonDecode(raw));
      } catch (_) {
        await prefs.remove(_kActiveWarehouseKey);
      }
    }
  }

  Future<void> setWarehouse(WarehouseModel? warehouse) async {
    state = warehouse;
    final prefs = await SharedPreferences.getInstance();
    if (warehouse == null) {
      await prefs.remove(_kActiveWarehouseKey);
    } else {
      await prefs.setString(_kActiveWarehouseKey, jsonEncode(warehouse.toJson()));
    }
  }

  // Called after login to auto-select the default warehouse if none persisted
  Future<void> initFromList(List<WarehouseModel> warehouses) async {
    if (warehouses.isEmpty) return;
    // If persisted warehouse still exists in the list, keep it
    if (state != null && warehouses.any((w) => w.id == state!.id)) return;
    // Otherwise pick the default, fallback to first
    final def = warehouses.firstWhere(
      (w) => w.isDefault,
      orElse: () => warehouses.first,
    );
    await setWarehouse(def);
  }

  void clear() {
    state = null;
    SharedPreferences.getInstance().then((p) => p.remove(_kActiveWarehouseKey));
  }
}

final activeWarehouseProvider =
    StateNotifierProvider<ActiveWarehouseNotifier, WarehouseModel?>(
  (ref) => ActiveWarehouseNotifier(),
);
