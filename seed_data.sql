-- =============================================================================
-- Données de démarrage POS Connect
-- Catégories, Fournisseurs, Clients, Produits + Stock initial
--
-- Utilisation :
--   MySQL  : mysql -u root -p pos_db < seed_data.sql
--   SQLite : sqlite3 pos_data.db < seed_data.sql
--
-- IMPORTANT : remplacer __TENANT_ID__ par l'UUID du tenant local.
--   Récupérer l'UUID avec :
--     SELECT id FROM tenants WHERE slug = '__local__';
--   Puis :
--     sed 's/__TENANT_ID__/ba809765-e8ec-46b3-9f41-58d5ba6febfe/g' seed_data.sql | mysql -u root -p pos_db
-- =============================================================================

-- -----------------------------------------------------------------------------
-- CATÉGORIES
-- -----------------------------------------------------------------------------
INSERT INTO categories (id, tenant_id, name, cat_description, created_at, updated_at) VALUES
  ('cat-001', '__TENANT_ID__', 'Alimentation',      'Produits alimentaires et épicerie',         NOW(), NOW()),
  ('cat-002', '__TENANT_ID__', 'Boissons',           'Eau, jus, sodas, boissons alcoolisées',     NOW(), NOW()),
  ('cat-003', '__TENANT_ID__', 'Hygiène & Beauté',   'Savons, shampoings, cosmétiques',           NOW(), NOW()),
  ('cat-004', '__TENANT_ID__', 'Ménage & Entretien', 'Produits de nettoyage, ustensiles',         NOW(), NOW()),
  ('cat-005', '__TENANT_ID__', 'Électronique',       'Accessoires téléphone, câbles, piles',      NOW(), NOW()),
  ('cat-006', '__TENANT_ID__', 'Vêtements',          'Habits, chaussures, accessoires',           NOW(), NOW()),
  ('cat-007', '__TENANT_ID__', 'Papeterie',          'Cahiers, stylos, fournitures scolaires',    NOW(), NOW()),
  ('cat-008', '__TENANT_ID__', 'Santé & Pharmacie',  'Médicaments sans ordonnance, vitamines',    NOW(), NOW())
ON DUPLICATE KEY UPDATE name = VALUES(name);

-- -----------------------------------------------------------------------------
-- FOURNISSEURS
-- -----------------------------------------------------------------------------
INSERT INTO suppliers (id, tenant_id, name, phone, email, address, created_at, updated_at) VALUES
  ('sup-001', '__TENANT_ID__', 'NATCOM Distribution',   '37001234', 'commandes@natcom.ht',    'Route de Frères, Pétion-Ville', NOW(), NOW()),
  ('sup-002', '__TENANT_ID__', 'Brana S.A.',            '34561234', 'ventes@brana.ht',        'Blvd La Saline, Port-au-Prince', NOW(), NOW()),
  ('sup-003', '__TENANT_ID__', 'Heineken Haïti',        '36781234', 'sales@heineken.ht',      'Zone Industrielle, PAP',         NOW(), NOW()),
  ('sup-004', '__TENANT_ID__', 'Importateur Général',   '29001234', 'info@importgen.ht',      'Rue des Miracles, PAP',          NOW(), NOW()),
  ('sup-005', '__TENANT_ID__', 'Pharmadis Haïti',       '38901234', 'commandes@pharmadis.ht', 'Ave Christophe, PAP',            NOW(), NOW()),
  ('sup-006', '__TENANT_ID__', 'Sovaco (produits Maggi)',  '36001234', 'sovaco@gmail.com',    'Route Nationale 1, PAP',         NOW(), NOW()),
  ('sup-007', '__TENANT_ID__', 'Tech Accessoires HT',   '32001234', 'tech@accessoires.ht',   'Rue Capois, Pétion-Ville',        NOW(), NOW()),
  ('sup-008', '__TENANT_ID__', 'Procter & Gamble Haïti','31001234', 'pg@haiti.ht',            'Delmas 60, PAP',                 NOW(), NOW())
ON DUPLICATE KEY UPDATE name = VALUES(name);

-- -----------------------------------------------------------------------------
-- CLIENTS
-- -----------------------------------------------------------------------------
INSERT INTO customers (id, tenant_id, name, phone, nif, email, address, credit_limit, created_at, updated_at) VALUES
  ('cli-001', '__TENANT_ID__', 'Marie Jeanne Florival', '37001111', NULL,         'marie.florival@gmail.com',   'Delmas 19, PAP',            5000.00, NOW(), NOW()),
  ('cli-002', '__TENANT_ID__', 'Jean Baptiste Pierre',  '36002222', '001234567',  'jbpierre@hotmail.com',       'Pétion-Ville, Rue Grégoire', 10000.00, NOW(), NOW()),
  ('cli-003', '__TENANT_ID__', 'Supermarché Bel Air',   '29003333', '009876543',  'belairsupermarche@gmail.com','Bel Air, PAP',               25000.00, NOW(), NOW()),
  ('cli-004', '__TENANT_ID__', 'Rosemide Théodore',     '38004444', NULL,         NULL,                          'Carrefour, Route de Frères', 2500.00,  NOW(), NOW()),
  ('cli-005', '__TENANT_ID__', 'Boutik Lakay Élodie',   '32005555', '005432198',  'lakay.elodie@yahoo.fr',      'Tabarre, Route Principale',  8000.00,  NOW(), NOW()),
  ('cli-006', '__TENANT_ID__', 'Frantz Désir',          '31006666', NULL,         NULL,                          'Croix-des-Bouquets',         3000.00,  NOW(), NOW()),
  ('cli-007', '__TENANT_ID__', 'Hôtel Oloffson',        '29007777', '007890123',  'reservations@oloffson.com',  'Ave Christophe, PAP',        50000.00, NOW(), NOW()),
  ('cli-008', '__TENANT_ID__', 'Pauline Cétoute',       '34008888', NULL,         NULL,                          'Kenscoff, Route Principale', 1500.00,  NOW(), NOW()),
  ('cli-009', '__TENANT_ID__', 'Lidio Casimir',         '37009999', '002345678',  NULL,                          'Delmas 33, PAP',             4000.00,  NOW(), NOW()),
  ('cli-010', '__TENANT_ID__', 'École Nationale de Pétion-Ville', '36010000', '003456789', 'dir@enp.edu.ht', 'Pétion-Ville', 15000.00, NOW(), NOW())
ON DUPLICATE KEY UPDATE name = VALUES(name);

-- -----------------------------------------------------------------------------
-- PRODUITS
-- -----------------------------------------------------------------------------
INSERT INTO products (id, tenant_id, category_id, supplier_id, name, barcode, purchase_price, sale_price, alert_stock, description, is_active, created_at, updated_at) VALUES

  -- Alimentation
  ('pro-001', '__TENANT_ID__', 'cat-001', 'sup-006', 'Maggi Cube (boîte 60 cubes)',  '6001234000001',  150.00,  200.00, 5,  'Bouillon Maggi, boîte 60 cubes', 1, NOW(), NOW()),
  ('pro-002', '__TENANT_ID__', 'cat-001', 'sup-006', 'Riz blanc Préféré 5 kg',       '6001234000002',  450.00,  550.00, 10, 'Riz blanc qualité supérieure',   1, NOW(), NOW()),
  ('pro-003', '__TENANT_ID__', 'cat-001', 'sup-004', 'Huile végétale Mazola 1L',     '6001234000003',  250.00,  320.00, 8,  'Huile végétale 1 litre',         1, NOW(), NOW()),
  ('pro-004', '__TENANT_ID__', 'cat-001', 'sup-004', 'Sucre blanc 2 kg',             '6001234000004',  180.00,  230.00, 10, 'Sucre raffiné 2 kg',             1, NOW(), NOW()),
  ('pro-005', '__TENANT_ID__', 'cat-001', 'sup-004', 'Farine de blé 2 kg',           '6001234000005',  150.00,  200.00, 8,  'Farine tout usage',              1, NOW(), NOW()),
  ('pro-006', '__TENANT_ID__', 'cat-001', 'sup-004', 'Pâtes spaghetti 500g',         '6001234000006',   80.00,  110.00, 15, 'Pâtes alimentaires 500g',        1, NOW(), NOW()),
  ('pro-007', '__TENANT_ID__', 'cat-001', 'sup-004', 'Lait Nestlé en poudre 400g',   '6001234000007',  350.00,  450.00, 5,  'Lait en poudre entier 400g',     1, NOW(), NOW()),
  ('pro-008', '__TENANT_ID__', 'cat-001', 'sup-004', 'Sardine en boîte (Crown)',     '6001234000008',   55.00,   75.00, 20, 'Sardines à la tomate 125g',      1, NOW(), NOW()),

  -- Boissons
  ('pro-009', '__TENANT_ID__', 'cat-002', 'sup-002', 'Prestige 600ml',               '6001234000009',   65.00,   90.00, 24, 'Bière Prestige bouteille 600ml', 1, NOW(), NOW()),
  ('pro-010', '__TENANT_ID__', 'cat-002', 'sup-002', 'Couronne soda 2L',             '6001234000010',   80.00,  110.00, 12, 'Soda Couronne 2 litres',         1, NOW(), NOW()),
  ('pro-011', '__TENANT_ID__', 'cat-002', 'sup-004', 'Eau Culligan 1.5L',            '6001234000011',   30.00,   45.00, 48, 'Eau purifiée 1,5 litres',        1, NOW(), NOW()),
  ('pro-012', '__TENANT_ID__', 'cat-002', 'sup-003', 'Heineken 330ml',               '6001234000012',   75.00,  100.00, 24, 'Bière Heineken canette 330ml',   1, NOW(), NOW()),
  ('pro-013', '__TENANT_ID__', 'cat-002', 'sup-004', 'Jus Tampico 1L',               '6001234000013',  100.00,  140.00, 12, 'Jus de fruits Tampico 1 litre',  1, NOW(), NOW()),
  ('pro-014', '__TENANT_ID__', 'cat-002', 'sup-004', 'Nescafé soluble 200g',         '6001234000014',  280.00,  360.00, 6,  'Café soluble Nescafé 200g',      1, NOW(), NOW()),

  -- Hygiène & Beauté
  ('pro-015', '__TENANT_ID__', 'cat-003', 'sup-008', 'Savon Palmolive 100g',         '6001234000015',   25.00,   40.00, 30, 'Savon de toilette 100g',         1, NOW(), NOW()),
  ('pro-016', '__TENANT_ID__', 'cat-003', 'sup-008', 'Shampoing Head & Shoulders 200ml', '6001234000016', 180.00, 250.00, 10, 'Shampoing antipelliculaire',  1, NOW(), NOW()),
  ('pro-017', '__TENANT_ID__', 'cat-003', 'sup-008', 'Colgate dentifrice 100ml',     '6001234000017',   85.00,  120.00, 15, 'Dentifrice blancheur 100ml',     1, NOW(), NOW()),
  ('pro-018', '__TENANT_ID__', 'cat-003', 'sup-008', 'Déodorant Dove Roll-on 50ml',  '6001234000018',  150.00,  210.00, 10, 'Déodorant 48h pour femme',       1, NOW(), NOW()),
  ('pro-019', '__TENANT_ID__', 'cat-003', 'sup-004', 'Vaseline 250ml',               '6001234000019',  120.00,  170.00, 8,  'Crème hydratante Vaseline',      1, NOW(), NOW()),

  -- Ménage & Entretien
  ('pro-020', '__TENANT_ID__', 'cat-004', 'sup-004', 'Eau de Javel 1L',              '6001234000020',   35.00,   55.00, 20, 'Eau de Javel désinfectante 1L',  1, NOW(), NOW()),
  ('pro-021', '__TENANT_ID__', 'cat-004', 'sup-004', 'Détergent à lessive Ace 1kg',  '6001234000021',  180.00,  250.00, 10, 'Lessive en poudre Ace 1kg',      1, NOW(), NOW()),
  ('pro-022', '__TENANT_ID__', 'cat-004', 'sup-004', 'Liquide vaisselle Axion 500ml','6001234000022',   90.00,  130.00, 12, 'Produit vaisselle Axion 500ml',  1, NOW(), NOW()),
  ('pro-023', '__TENANT_ID__', 'cat-004', 'sup-004', 'Papier hygiénique 12 rouleaux','6001234000023',  180.00,  250.00, 10, 'Papier hygiénique 2 épaisseurs', 1, NOW(), NOW()),

  -- Électronique
  ('pro-024', '__TENANT_ID__', 'cat-005', 'sup-007', 'Câble USB-C 1m',               '6001234000024',  120.00,  200.00, 5,  'Câble charge rapide USB-C',      1, NOW(), NOW()),
  ('pro-025', '__TENANT_ID__', 'cat-005', 'sup-007', 'Piles AA Duracell (pack 4)',   '6001234000025',   80.00,  130.00, 10, 'Piles alcalines AA x4',          1, NOW(), NOW()),
  ('pro-026', '__TENANT_ID__', 'cat-005', 'sup-007', 'Coque Samsung A15',            '6001234000026',  200.00,  350.00, 5,  'Coque de protection Samsung A15',1, NOW(), NOW()),
  ('pro-027', '__TENANT_ID__', 'cat-005', 'sup-007', 'Écouteurs intra-auriculaires', '6001234000027',  350.00,  600.00, 3,  'Écouteurs filaires jack 3.5mm',  1, NOW(), NOW()),

  -- Papeterie
  ('pro-028', '__TENANT_ID__', 'cat-007', 'sup-004', 'Cahier 100 pages',             '6001234000028',   35.00,   55.00, 20, 'Cahier quadrillé 100 pages',     1, NOW(), NOW()),
  ('pro-029', '__TENANT_ID__', 'cat-007', 'sup-004', 'Stylo Bic bleu (lot 10)',      '6001234000029',   60.00,   90.00, 15, 'Stylos à bille Bic x10',         1, NOW(), NOW()),
  ('pro-030', '__TENANT_ID__', 'cat-007', 'sup-004', 'Règle plastique 30cm',         '6001234000030',   15.00,   25.00, 10, 'Règle transparente 30cm',        1, NOW(), NOW()),

  -- Santé
  ('pro-031', '__TENANT_ID__', 'cat-008', 'sup-005', 'Paracétamol 500mg (boîte 24)', '6001234000031',   80.00,  120.00, 8,  'Antidouleur paracétamol 500mg',  1, NOW(), NOW()),
  ('pro-032', '__TENANT_ID__', 'cat-008', 'sup-005', 'Vitamine C 1000mg (30 cp)',    '6001234000032',  150.00,  220.00, 5,  'Complément vitamines C 30 cp',   1, NOW(), NOW()),
  ('pro-033', '__TENANT_ID__', 'cat-008', 'sup-005', 'Sérum physiologique 250ml',    '6001234000033',   90.00,  140.00, 8,  'Solution saline isotonique',     1, NOW(), NOW())

ON DUPLICATE KEY UPDATE name = VALUES(name);

-- -----------------------------------------------------------------------------
-- STOCK INITIAL (mouvements d'entrée)
-- Les quantités reflètent un stock de démarrage réaliste.
-- -----------------------------------------------------------------------------
INSERT INTO stock_movements (id, tenant_id, product_id, type, quantity, source_type, note, created_at, updated_at) VALUES
  ('sm-001', '__TENANT_ID__', 'pro-001', 'in', 50,  'initial', 'Stock de démarrage', NOW(), NOW()),
  ('sm-002', '__TENANT_ID__', 'pro-002', 'in', 30,  'initial', 'Stock de démarrage', NOW(), NOW()),
  ('sm-003', '__TENANT_ID__', 'pro-003', 'in', 40,  'initial', 'Stock de démarrage', NOW(), NOW()),
  ('sm-004', '__TENANT_ID__', 'pro-004', 'in', 25,  'initial', 'Stock de démarrage', NOW(), NOW()),
  ('sm-005', '__TENANT_ID__', 'pro-005', 'in', 30,  'initial', 'Stock de démarrage', NOW(), NOW()),
  ('sm-006', '__TENANT_ID__', 'pro-006', 'in', 60,  'initial', 'Stock de démarrage', NOW(), NOW()),
  ('sm-007', '__TENANT_ID__', 'pro-007', 'in', 20,  'initial', 'Stock de démarrage', NOW(), NOW()),
  ('sm-008', '__TENANT_ID__', 'pro-008', 'in', 100, 'initial', 'Stock de démarrage', NOW(), NOW()),
  ('sm-009', '__TENANT_ID__', 'pro-009', 'in', 48,  'initial', 'Stock de démarrage', NOW(), NOW()),
  ('sm-010', '__TENANT_ID__', 'pro-010', 'in', 24,  'initial', 'Stock de démarrage', NOW(), NOW()),
  ('sm-011', '__TENANT_ID__', 'pro-011', 'in', 96,  'initial', 'Stock de démarrage', NOW(), NOW()),
  ('sm-012', '__TENANT_ID__', 'pro-012', 'in', 48,  'initial', 'Stock de démarrage', NOW(), NOW()),
  ('sm-013', '__TENANT_ID__', 'pro-013', 'in', 24,  'initial', 'Stock de démarrage', NOW(), NOW()),
  ('sm-014', '__TENANT_ID__', 'pro-014', 'in', 15,  'initial', 'Stock de démarrage', NOW(), NOW()),
  ('sm-015', '__TENANT_ID__', 'pro-015', 'in', 100, 'initial', 'Stock de démarrage', NOW(), NOW()),
  ('sm-016', '__TENANT_ID__', 'pro-016', 'in', 30,  'initial', 'Stock de démarrage', NOW(), NOW()),
  ('sm-017', '__TENANT_ID__', 'pro-017', 'in', 40,  'initial', 'Stock de démarrage', NOW(), NOW()),
  ('sm-018', '__TENANT_ID__', 'pro-018', 'in', 25,  'initial', 'Stock de démarrage', NOW(), NOW()),
  ('sm-019', '__TENANT_ID__', 'pro-019', 'in', 30,  'initial', 'Stock de démarrage', NOW(), NOW()),
  ('sm-020', '__TENANT_ID__', 'pro-020', 'in', 50,  'initial', 'Stock de démarrage', NOW(), NOW()),
  ('sm-021', '__TENANT_ID__', 'pro-021', 'in', 30,  'initial', 'Stock de démarrage', NOW(), NOW()),
  ('sm-022', '__TENANT_ID__', 'pro-022', 'in', 40,  'initial', 'Stock de démarrage', NOW(), NOW()),
  ('sm-023', '__TENANT_ID__', 'pro-023', 'in', 20,  'initial', 'Stock de démarrage', NOW(), NOW()),
  ('sm-024', '__TENANT_ID__', 'pro-024', 'in', 15,  'initial', 'Stock de démarrage', NOW(), NOW()),
  ('sm-025', '__TENANT_ID__', 'pro-025', 'in', 30,  'initial', 'Stock de démarrage', NOW(), NOW()),
  ('sm-026', '__TENANT_ID__', 'pro-026', 'in', 10,  'initial', 'Stock de démarrage', NOW(), NOW()),
  ('sm-027', '__TENANT_ID__', 'pro-027', 'in', 8,   'initial', 'Stock de démarrage', NOW(), NOW()),
  ('sm-028', '__TENANT_ID__', 'pro-028', 'in', 50,  'initial', 'Stock de démarrage', NOW(), NOW()),
  ('sm-029', '__TENANT_ID__', 'pro-029', 'in', 20,  'initial', 'Stock de démarrage', NOW(), NOW()),
  ('sm-030', '__TENANT_ID__', 'pro-030', 'in', 30,  'initial', 'Stock de démarrage', NOW(), NOW()),
  ('sm-031', '__TENANT_ID__', 'pro-031', 'in', 25,  'initial', 'Stock de démarrage', NOW(), NOW()),
  ('sm-032', '__TENANT_ID__', 'pro-032', 'in', 15,  'initial', 'Stock de démarrage', NOW(), NOW()),
  ('sm-033', '__TENANT_ID__', 'pro-033', 'in', 20,  'initial', 'Stock de démarrage', NOW(), NOW())
ON DUPLICATE KEY UPDATE quantity = VALUES(quantity);
