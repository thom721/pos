import 'package:flutter_test/flutter_test.dart';
import 'package:pos_connect/data/models/price_tier_change_model.dart';
import 'package:pos_connect/data/models/price_tier_model.dart';

void main() {
  group('PriceTierChangeModel.buildSnapshot', () {
    test('regroupe les paliers par produit avec le nom et les seuils', () {
      final snapshot = PriceTierChangeModel.buildSnapshot([
        const PriceTier(productId: 'p1', productName: 'Fiesta', minQuantity: 1, price: 100),
        const PriceTier(productId: 'p1', productName: 'Fiesta', minQuantity: 12, price: 90),
        const PriceTier(productId: 'p2', productName: 'Prorade', minQuantity: 1, price: 50),
      ]);

      expect(snapshot.keys, containsAll(['p1', 'p2']));
      expect(snapshot['p1']['name'], 'Fiesta');
      expect(snapshot['p1']['tiers'], [
        {'q': 1.0, 'p': 100.0},
        {'q': 12.0, 'p': 90.0},
      ]);
    });

    test('tiers vides pour un produit absent', () {
      final snapshot = PriceTierChangeModel.buildSnapshot(const []);
      expect(snapshot, isEmpty);
    });
  });

  group('PriceTierChangeModel.diffSnapshots', () {
    test('détecte un prix modifié sur un palier existant', () {
      final previous = {
        'p1': {'name': 'Fiesta', 'tiers': [
          {'q': 1, 'p': 100},
        ]},
      };
      final current = {
        'p1': {'name': 'Fiesta', 'tiers': [
          {'q': 1, 'p': 95},
        ]},
      };

      final changes = PriceTierChangeModel.diffSnapshots(previous, current, 'wh1');

      expect(changes, hasLength(1));
      expect(changes.first.productId, 'p1');
      expect(changes.first.oldTiers.single.price, 100);
      expect(changes.first.newTiers.single.price, 95);
    });

    test('ignore un produit dont les paliers sont identiques', () {
      final same = {
        'p1': {'name': 'Fiesta', 'tiers': [
          {'q': 1, 'p': 100},
        ]},
      };

      final changes = PriceTierChangeModel.diffSnapshots(same, same, 'wh1');

      expect(changes, isEmpty);
    });

    test('détecte un nouveau palier ajouté (le cloud en crée un)', () {
      final previous = {
        'p1': {'name': 'Fiesta', 'tiers': [
          {'q': 1, 'p': 100},
        ]},
      };
      final current = {
        'p1': {'name': 'Fiesta', 'tiers': [
          {'q': 1, 'p': 100},
          {'q': 12, 'p': 90},
        ]},
      };

      final changes = PriceTierChangeModel.diffSnapshots(previous, current, 'wh1');

      expect(changes, hasLength(1));
      expect(changes.first.oldTiers, hasLength(1));
      expect(changes.first.newTiers, hasLength(2));
    });

    test('détecte la suppression de tous les paliers d\'un produit', () {
      final previous = {
        'p1': {'name': 'Fiesta', 'tiers': [
          {'q': 1, 'p': 100},
        ]},
      };
      final current = <String, dynamic>{};

      final changes = PriceTierChangeModel.diffSnapshots(previous, current, 'wh1');

      expect(changes, hasLength(1));
      expect(changes.first.newTiers, isEmpty);
      // Le nom doit survivre même si le produit a disparu du relevé actuel.
      expect(changes.first.productName, 'Fiesta');
    });

    test('détecte un nouveau produit apparu côté cloud', () {
      final previous = <String, dynamic>{};
      final current = {
        'p2': {'name': 'Prorade', 'tiers': [
          {'q': 1, 'p': 50},
        ]},
      };

      final changes = PriceTierChangeModel.diffSnapshots(previous, current, 'wh1');

      expect(changes, hasLength(1));
      expect(changes.first.oldTiers, isEmpty);
      expect(changes.first.productName, 'Prorade');
    });

    test('aucun changement quand les deux relevés sont vides', () {
      final changes = PriceTierChangeModel.diffSnapshots({}, {}, 'wh1');
      expect(changes, isEmpty);
    });
  });
}
