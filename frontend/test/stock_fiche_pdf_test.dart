import 'package:flutter_test/flutter_test.dart';
import 'package:pos_connect/data/models/price_tier_change_model.dart';
import 'package:pos_connect/data/models/price_tier_model.dart';
import 'package:pos_connect/data/models/product_model.dart';
import 'package:pos_connect/data/models/stock_movement_model.dart';
import 'package:pos_connect/providers/settings_provider.dart';
import 'package:pos_connect/shared/utils/stock_receipt_pdf.dart';

// Vérifie que les générateurs de PDF des fiches auto-imprimées (réception,
// ajustement de stock, paliers de prix) s'exécutent sans lever d'exception
// sur des données représentatives, y compris les cas limites introduits par
// ces fiches (quantité négative, relevé "avant" vide, paliers multiples).
void main() {
  const settings = AppSettings(); // logo désactivé par défaut (logoPath vide)

  group('buildStockReceiptFichePdf', () {
    test('fiche de réception standard (quantités positives)', () async {
      final movements = [
        StockMovementModel(
          id: 'm1', type: 'in_', quantity: 24, sourceType: 'purchase',
          createdAt: DateTime(2026, 11, 17, 10, 0), productName: 'Fiesta 20oz',
        ),
        StockMovementModel(
          id: 'm2', type: 'in_', quantity: 12, sourceType: 'purchase',
          createdAt: DateTime(2026, 11, 17, 10, 1), productName: 'Prorade 20oz',
        ),
      ];

      final bytes = await buildStockReceiptFichePdf(movements, settings);

      expect(bytes, isNotEmpty);
      expect(String.fromCharCodes(bytes.take(5)), '%PDF-');
    });

    test('fiche d\'ajustement avec titre personnalisé et quantité négative', () async {
      final movements = [
        StockMovementModel(
          id: 'm3', type: 'adjust', quantity: -3, sourceType: 'inventory',
          createdAt: DateTime(2026, 11, 17, 11, 0), productName: 'Fiesta 20oz',
        ),
        StockMovementModel(
          id: 'm4', type: 'adjust', quantity: 5, sourceType: 'inventory',
          createdAt: DateTime(2026, 11, 17, 11, 1), productName: 'Prorade 20oz',
        ),
      ];

      final bytes = await buildStockReceiptFichePdf(
        movements, settings, title: 'FICHE D\'AJUSTEMENT',
      );

      expect(bytes, isNotEmpty);
      expect(String.fromCharCodes(bytes.take(5)), '%PDF-');
    });

    test('produit sans nom (productName null) ne plante pas', () async {
      final movements = [
        StockMovementModel(
          id: 'm5', type: 'adjust', quantity: -1,
          createdAt: DateTime(2026, 11, 17, 12, 0),
        ),
      ];

      final bytes = await buildStockReceiptFichePdf(movements, settings);

      expect(bytes, isNotEmpty);
    });
  });

  group('buildPriceTierChangeFichePdf', () {
    test('changement avant/après avec paliers multiples', () async {
      final changes = [
        PriceTierChangeModel(
          productId: 'p1', productName: 'Fiesta 20oz', warehouseId: 'wh1',
          oldTiers: const [PriceTier(productId: 'p1', minQuantity: 1, price: 100)],
          newTiers: const [
            PriceTier(productId: 'p1', minQuantity: 1, price: 95),
            PriceTier(productId: 'p1', minQuantity: 12, price: 90),
          ],
          createdAt: DateTime(2026, 11, 17, 13, 0),
        ),
      ];

      final bytes = await buildPriceTierChangeFichePdf(changes, settings);

      expect(bytes, isNotEmpty);
      expect(String.fromCharCodes(bytes.take(5)), '%PDF-');
    });

    test('premier relevé : "avant" vide (nouveau produit avec paliers)', () async {
      final changes = [
        PriceTierChangeModel(
          productId: 'p2', productName: 'Prorade 20oz', warehouseId: 'wh1',
          oldTiers: const [],
          newTiers: const [PriceTier(productId: 'p2', minQuantity: 1, price: 50)],
          createdAt: DateTime(2026, 11, 17, 13, 5),
        ),
      ];

      final bytes = await buildPriceTierChangeFichePdf(changes, settings);

      expect(bytes, isNotEmpty);
    });

    test('paliers supprimés : "après" vide', () async {
      final changes = [
        PriceTierChangeModel(
          productId: 'p3', productName: 'Produit retiré', warehouseId: 'wh1',
          oldTiers: const [PriceTier(productId: 'p3', minQuantity: 1, price: 30)],
          newTiers: const [],
          createdAt: DateTime(2026, 11, 17, 13, 10),
        ),
      ];

      final bytes = await buildPriceTierChangeFichePdf(changes, settings);

      expect(bytes, isNotEmpty);
    });

    test('plusieurs produits changés dans la même fiche', () async {
      final changes = [
        PriceTierChangeModel(
          productId: 'p1', productName: 'Fiesta 20oz', warehouseId: 'wh1',
          oldTiers: const [PriceTier(productId: 'p1', minQuantity: 1, price: 100)],
          newTiers: const [PriceTier(productId: 'p1', minQuantity: 1, price: 95)],
          createdAt: DateTime(2026, 11, 17, 13, 0),
        ),
        PriceTierChangeModel(
          productId: 'p2', productName: 'Prorade 20oz', warehouseId: 'wh1',
          oldTiers: const [PriceTier(productId: 'p2', minQuantity: 1, price: 50)],
          newTiers: const [PriceTier(productId: 'p2', minQuantity: 1, price: 48)],
          createdAt: DateTime(2026, 11, 17, 13, 0),
        ),
      ];

      final bytes = await buildPriceTierChangeFichePdf(changes, settings);

      expect(bytes, isNotEmpty);
    });
  });

  group('buildNewProductFichePdf', () {
    test('produit simple avec toutes les informations', () async {
      final products = [
        ProductModel(
          id: 'p1', name: 'Sprite 20 OZ', barcode: '123456789',
          description: 'Boisson gazeuse', salePrice: 50, purchasePrice: 35,
          alertStock: 10, stock: 24,
          category: CategoryModel(id: 'c1', name: 'Boissons'),
          createdAt: DateTime(2026, 11, 20, 9, 0),
        ),
      ];

      final bytes = await buildNewProductFichePdf(products, settings);

      expect(bytes, isNotEmpty);
      expect(String.fromCharCodes(bytes.take(5)), '%PDF-');
    });

    test('service (pas de stock/prix d\'achat affichés)', () async {
      final products = [
        ProductModel(
          id: 'p2', name: 'Heure de lavage', salePrice: 100, purchasePrice: 0,
          alertStock: 0, isService: true,
          createdAt: DateTime(2026, 11, 20, 9, 5),
        ),
      ];

      final bytes = await buildNewProductFichePdf(products, settings);

      expect(bytes, isNotEmpty);
    });

    test('produit composé (type affiche le composant)', () async {
      final products = [
        ProductModel(
          id: 'p3', name: 'Caisse Sprite 20oz', salePrice: 1100,
          purchasePrice: 1000, alertStock: 2,
          componentProductId: 'p1', componentQuantity: 12,
          createdAt: DateTime(2026, 11, 20, 9, 10),
        ),
      ];

      final bytes = await buildNewProductFichePdf(products, settings);

      expect(bytes, isNotEmpty);
    });

    test('plusieurs produits, champs optionnels absents', () async {
      final products = [
        ProductModel(
          id: 'p4', name: 'Produit A', salePrice: 10, purchasePrice: 5,
          alertStock: 0, createdAt: DateTime(2026, 11, 20, 9, 15),
        ),
        ProductModel(
          id: 'p5', name: 'Produit B', salePrice: 20, purchasePrice: 15,
          alertStock: 0, createdAt: null,
        ),
      ];

      final bytes = await buildNewProductFichePdf(products, settings);

      expect(bytes, isNotEmpty);
    });
  });
}
