import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pos_connect/core/theme.dart';
import 'package:pos_connect/data/api/api_client.dart' show extractAnyError;
import 'package:pos_connect/data/models/restaurant_model.dart';
import 'package:pos_connect/data/repositories/restaurant_repository.dart';
import 'package:pos_connect/providers/restaurant_provider.dart';

class KitchenScreen extends ConsumerWidget {
  const KitchenScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ordersAsync = ref.watch(openOrdersProvider);

    return Scaffold(
      backgroundColor: const Color(0xFF1A1A2E),
      appBar: AppBar(
        backgroundColor: const Color(0xFF16213E),
        foregroundColor: Colors.white,
        title: const Text('Cuisine', style: TextStyle(fontWeight: FontWeight.w800, color: Colors.white)),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded, color: Colors.white70),
            onPressed: () => ref.invalidate(openOrdersProvider),
          ),
        ],
      ),
      body: ordersAsync.when(
        loading: () => const Center(child: CircularProgressIndicator(color: Colors.white)),
        error: (e, _) => Center(
          child: Text(extractAnyError(e), style: const TextStyle(color: Colors.red)),
        ),
        data: (orders) {
          final active = orders.where((o) => o.status != 'closed').toList();
          if (active.isEmpty) {
            return const Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.check_circle_outline_rounded, size: 64, color: Colors.green),
                  SizedBox(height: 16),
                  Text('Aucune commande en attente',
                      style: TextStyle(color: Colors.white70, fontSize: 18)),
                ],
              ),
            );
          }
          return RefreshIndicator(
            onRefresh: () async => ref.invalidate(openOrdersProvider),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: GridView.builder(
                gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                  maxCrossAxisExtent: 340,
                  mainAxisSpacing: 12,
                  crossAxisSpacing: 12,
                  childAspectRatio: 0.75,
                ),
                itemCount: active.length,
                itemBuilder: (_, i) => _KitchenOrderCard(order: active[i], ref: ref),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _KitchenOrderCard extends StatelessWidget {
  final RestaurantOrderModel order;
  final WidgetRef ref;
  const _KitchenOrderCard({required this.order, required this.ref});

  Color get _headerColor {
    if (order.isReady) return AppColors.success;
    if (order.sentToKitchen) return AppColors.warning;
    return AppColors.textSecondary;
  }

  String get _statusLabel {
    if (order.isReady) return 'PRÊT';
    if (order.sentToKitchen) return 'EN CUISINE';
    return 'EN ATTENTE';
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF16213E),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _headerColor, width: 2),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: _headerColor.withValues(alpha: 0.15),
              borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
            ),
            child: Row(
              children: [
                Text(order.tableName ?? 'Table',
                    style: const TextStyle(
                        color: Colors.white, fontWeight: FontWeight.w800, fontSize: 16)),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: _headerColor,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(_statusLabel,
                      style: const TextStyle(
                          color: Colors.white, fontSize: 10, fontWeight: FontWeight.w800)),
                ),
              ],
            ),
          ),

          // Items
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.all(10),
              itemCount: order.items.length,
              itemBuilder: (_, i) {
                final item = order.items[i];
                final isReady = item.status == 'ready';
                return Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Row(
                    children: [
                      Container(
                        width: 28, height: 28,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: isReady
                              ? AppColors.success.withValues(alpha: 0.2)
                              : Colors.white.withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          '${item.quantity.toStringAsFixed(item.quantity == item.quantity.roundToDouble() ? 0 : 1)}x',
                          style: TextStyle(
                              color: isReady ? AppColors.success : Colors.white70,
                              fontWeight: FontWeight.bold,
                              fontSize: 11),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(item.productName,
                                style: TextStyle(
                                    color: isReady ? Colors.white54 : Colors.white,
                                    fontWeight: FontWeight.w600,
                                    decoration: isReady ? TextDecoration.lineThrough : null)),
                            if (item.notes != null && item.notes!.isNotEmpty)
                              Text(item.notes!,
                                  style: const TextStyle(color: Colors.amber, fontSize: 11)),
                          ],
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),

          // Actions
          if (!order.isReady)
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 0, 10, 10),
              child: SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: () => _markReady(context),
                  style: FilledButton.styleFrom(backgroundColor: AppColors.success),
                  icon: const Icon(Icons.check_rounded),
                  label: const Text('Marquer comme prêt'),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Future<void> _markReady(BuildContext context) async {
    try {
      await RestaurantRepository().markReady(order.id);
      ref.invalidate(openOrdersProvider);
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(extractAnyError(e)),
          backgroundColor: AppColors.error,
        ));
      }
    }
  }
}
