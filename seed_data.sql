-- =============================================================================
-- Données de démarrage POS Connect
-- Catégories, Fournisseurs, Clients, Produits + Stock initial
--
-- Utilisation :
--   mysql -u root -p pos_db < seed_data.sql
--
-- IMPORTANT : remplacer __TENANT_ID__ par l'UUID du tenant local.
--   Récupérer l'UUID avec :
--     SELECT id FROM tenants WHERE slug = '__local__';
--   Puis :
--     sed 's/__TENANT_ID__/ba809765-e8ec-46b3-9f41-58d5ba6febfe/g' seed_data.sql | mysql -u root -p pos_db
-- =============================================================================
-- Nettoyage des anciennes données seed (IDs non-UUID comme pro-001)
DELETE FROM stock_movements WHERE id REGEXP '^[a-z]{2,3}-[0-9]+$';
DELETE FROM products      WHERE id REGEXP '^[a-z]{2,3}-[0-9]+$';
DELETE FROM customers     WHERE id REGEXP '^[a-z]{2,3}-[0-9]+$';
DELETE FROM suppliers     WHERE id REGEXP '^[a-z]{2,3}-[0-9]+$';
DELETE FROM categories    WHERE id REGEXP '^[a-z]{2,3}-[0-9]+$';

-- -----------------------------------------------------------------------------
-- CATÉGORIES
-- -----------------------------------------------------------------------------
INSERT INTO categories (id, tenant_id, name, cat_description, created_at, updated_at) VALUES
  ('47f22aab-a668-5f95-81f9-a2b10fc2e966', '__TENANT_ID__', 'Alimentation',      'Produits alimentaires et épicerie',         NOW(), NOW()),
  ('c705ab72-d6c4-550b-aa58-2fcc4a10af63', '__TENANT_ID__', 'Boissons',           'Eau, jus, sodas, boissons alcoolisées',     NOW(), NOW()),
  ('1a8b4bfc-633c-59a2-a3d6-d0b87b011f5d', '__TENANT_ID__', 'Hygiène & Beauté',   'Savons, shampoings, cosmétiques',           NOW(), NOW()),
  ('47027069-7d2b-558e-a26d-d04046844955', '__TENANT_ID__', 'Ménage & Entretien', 'Produits de nettoyage, ustensiles',         NOW(), NOW()),
  ('61613687-120d-5935-9410-01ab54025b99', '__TENANT_ID__', 'Électronique',       'Accessoires téléphone, câbles, piles',      NOW(), NOW()),
  ('92e779d4-2b57-5078-acb7-479817036f7b', '__TENANT_ID__', 'Vêtements',          'Habits, chaussures, accessoires',           NOW(), NOW()),
  ('3f595cd8-0fb5-5a54-a937-1c1756506ee9', '__TENANT_ID__', 'Papeterie',          'Cahiers, stylos, fournitures scolaires',    NOW(), NOW()),
  ('2ab8e1ee-8f7b-5d90-8e4d-8d57286ef417', '__TENANT_ID__', 'Santé & Pharmacie',  'Médicaments sans ordonnance, vitamines',    NOW(), NOW())
ON DUPLICATE KEY UPDATE name = VALUES(name);

-- -----------------------------------------------------------------------------
-- FOURNISSEURS
-- -----------------------------------------------------------------------------
INSERT INTO suppliers (id, tenant_id, name, phone, email, address, created_at, updated_at) VALUES
  ('bb602e84-0c6e-54e8-85ef-ff7ff95ffd4b', '__TENANT_ID__', 'NATCOM Distribution',    '37001234', 'commandes@natcom.ht',    'Route de Frères, Pétion-Ville',  NOW(), NOW()),
  ('45c76ab8-ab47-5348-899e-4bff15faba97', '__TENANT_ID__', 'Brana S.A.',             '34561234', 'ventes@brana.ht',        'Blvd La Saline, Port-au-Prince', NOW(), NOW()),
  ('6bcd81cc-cbd2-50c8-8b81-f5405b1b8eac', '__TENANT_ID__', 'Heineken Haïti',         '36781234', 'sales@heineken.ht',      'Zone Industrielle, PAP',         NOW(), NOW()),
  ('fa7f2e51-2bbf-5a18-83d5-496e961eedd9', '__TENANT_ID__', 'Importateur Général',    '29001234', 'info@importgen.ht',      'Rue des Miracles, PAP',          NOW(), NOW()),
  ('da549511-7db3-5c1b-9a31-8bf25a3c0713', '__TENANT_ID__', 'Pharmadis Haïti',        '38901234', 'commandes@pharmadis.ht', 'Ave Christophe, PAP',            NOW(), NOW()),
  ('361383da-8cb3-5fdb-8806-c7c8719b9e19', '__TENANT_ID__', 'Sovaco (produits Maggi)','36001234', 'sovaco@gmail.com',       'Route Nationale 1, PAP',         NOW(), NOW()),
  ('616ee0b8-3db9-5b6d-9b1d-770dd930069c', '__TENANT_ID__', 'Tech Accessoires HT',   '32001234', 'tech@accessoires.ht',    'Rue Capois, Pétion-Ville',       NOW(), NOW()),
  ('85393c27-717d-52ac-9d8a-b25b17d7079c', '__TENANT_ID__', 'Procter & Gamble Haïti','31001234', 'pg@haiti.ht',            'Delmas 60, PAP',                  NOW(), NOW())
ON DUPLICATE KEY UPDATE name = VALUES(name);

-- -----------------------------------------------------------------------------
-- CLIENTS
-- -----------------------------------------------------------------------------
INSERT INTO customers (id, tenant_id, name, phone, nif, email, address, credit_limit, created_at, updated_at) VALUES
  ('13754c80-899c-5aa1-88c8-86cf4ecedfc3', '__TENANT_ID__', 'Marie Jeanne Florival',          '37001111', NULL,        'marie.florival@gmail.com',   'Delmas 19, PAP',             5000.00,  NOW(), NOW()),
  ('95294607-60c8-5188-b2fc-5f4ebec3e8ad', '__TENANT_ID__', 'Jean Baptiste Pierre',           '36002222', '001234567', 'jbpierre@hotmail.com',       'Pétion-Ville, Rue Grégoire', 10000.00, NOW(), NOW()),
  ('99d8bb97-621e-5514-9e14-67406c989c00', '__TENANT_ID__', 'Supermarché Bel Air',            '29003333', '009876543', 'belairsupermarche@gmail.com','Bel Air, PAP',               25000.00, NOW(), NOW()),
  ('c9a1993f-413e-5936-b5f6-eea55613c966', '__TENANT_ID__', 'Rosemide Théodore',              '38004444', NULL,        NULL,                          'Carrefour, Route de Frères', 2500.00,  NOW(), NOW()),
  ('5f625a38-eb31-5856-98a6-bd72d9572e4e', '__TENANT_ID__', 'Boutik Lakay Élodie',            '32005555', '005432198', 'lakay.elodie@yahoo.fr',      'Tabarre, Route Principale',  8000.00,  NOW(), NOW()),
  ('97be22c2-36e6-5cd2-9aec-af52a5a21157', '__TENANT_ID__', 'Frantz Désir',                   '31006666', NULL,        NULL,                          'Croix-des-Bouquets',         3000.00,  NOW(), NOW()),
  ('58affe64-8d01-57b5-b254-9a1b1eccbf5b', '__TENANT_ID__', 'Hôtel Oloffson',                 '29007777', '007890123', 'reservations@oloffson.com',  'Ave Christophe, PAP',        50000.00, NOW(), NOW()),
  ('a0b8c526-fb26-58b4-90c2-797a3d046892', '__TENANT_ID__', 'Pauline Cétoute',                '34008888', NULL,        NULL,                          'Kenscoff, Route Principale', 1500.00,  NOW(), NOW()),
  ('12baafb3-9bc4-5c92-949d-6423fc45ad7c', '__TENANT_ID__', 'Lidio Casimir',                  '37009999', '002345678', NULL,                          'Delmas 33, PAP',             4000.00,  NOW(), NOW()),
  ('e2dfc10d-b938-5e0b-86cb-1c0e7550cd17', '__TENANT_ID__', 'École Nationale de Pétion-Ville','36010000', '003456789', 'dir@enp.edu.ht',              'Pétion-Ville',               15000.00, NOW(), NOW())
ON DUPLICATE KEY UPDATE name = VALUES(name);

-- -----------------------------------------------------------------------------
-- PRODUITS
-- -----------------------------------------------------------------------------
INSERT INTO products (id, tenant_id, category_id, supplier_id, name, barcode, purchase_price, sale_price, alert_stock, description, is_active, created_at, updated_at) VALUES

  -- Alimentation
  ('945359f0-c87f-5fa8-ad34-3e516668c617', '__TENANT_ID__', '47f22aab-a668-5f95-81f9-a2b10fc2e966', '361383da-8cb3-5fdb-8806-c7c8719b9e19', 'Maggi Cube (boîte 60 cubes)',       '6001234000001',  150.00,  200.00, 5,  'Bouillon Maggi, boîte 60 cubes',   1, NOW(), NOW()),
  ('79a6b17f-22c4-51d5-90dc-02ffeb27876b', '__TENANT_ID__', '47f22aab-a668-5f95-81f9-a2b10fc2e966', '361383da-8cb3-5fdb-8806-c7c8719b9e19', 'Riz blanc Préféré 5 kg',            '6001234000002',  450.00,  550.00, 10, 'Riz blanc qualité supérieure',     1, NOW(), NOW()),
  ('e59449c9-9d9f-568a-a168-ff83ec68a912', '__TENANT_ID__', '47f22aab-a668-5f95-81f9-a2b10fc2e966', 'fa7f2e51-2bbf-5a18-83d5-496e961eedd9', 'Huile végétale Mazola 1L',          '6001234000003',  250.00,  320.00, 8,  'Huile végétale 1 litre',           1, NOW(), NOW()),
  ('824756ac-efde-5537-a7bd-b4a6f78af954', '__TENANT_ID__', '47f22aab-a668-5f95-81f9-a2b10fc2e966', 'fa7f2e51-2bbf-5a18-83d5-496e961eedd9', 'Sucre blanc 2 kg',                  '6001234000004',  180.00,  230.00, 10, 'Sucre raffiné 2 kg',               1, NOW(), NOW()),
  ('5a876436-f7fc-5b60-a3ed-f005ef80c075', '__TENANT_ID__', '47f22aab-a668-5f95-81f9-a2b10fc2e966', 'fa7f2e51-2bbf-5a18-83d5-496e961eedd9', 'Farine de blé 2 kg',                '6001234000005',  150.00,  200.00, 8,  'Farine tout usage',                1, NOW(), NOW()),
  ('b5bd4273-2b59-52a7-923d-f3b7672d5295', '__TENANT_ID__', '47f22aab-a668-5f95-81f9-a2b10fc2e966', 'fa7f2e51-2bbf-5a18-83d5-496e961eedd9', 'Pâtes spaghetti 500g',              '6001234000006',   80.00,  110.00, 15, 'Pâtes alimentaires 500g',          1, NOW(), NOW()),
  ('af2ec6ff-c2d4-515c-a67c-cc98da3660b8', '__TENANT_ID__', '47f22aab-a668-5f95-81f9-a2b10fc2e966', 'fa7f2e51-2bbf-5a18-83d5-496e961eedd9', 'Lait Nestlé en poudre 400g',        '6001234000007',  350.00,  450.00, 5,  'Lait en poudre entier 400g',       1, NOW(), NOW()),
  ('010e40bc-b938-5f62-8a20-7689aca81c55', '__TENANT_ID__', '47f22aab-a668-5f95-81f9-a2b10fc2e966', 'fa7f2e51-2bbf-5a18-83d5-496e961eedd9', 'Sardine en boîte (Crown)',          '6001234000008',   55.00,   75.00, 20, 'Sardines à la tomate 125g',        1, NOW(), NOW()),

  -- Boissons
  ('bc449d99-4df6-5a88-a4b7-0df0539ef1ab', '__TENANT_ID__', 'c705ab72-d6c4-550b-aa58-2fcc4a10af63', '45c76ab8-ab47-5348-899e-4bff15faba97', 'Prestige 600ml',                    '6001234000009',   65.00,   90.00, 24, 'Bière Prestige bouteille 600ml',   1, NOW(), NOW()),
  ('3aeca332-6072-5fb2-ac31-571e62ab3b37', '__TENANT_ID__', 'c705ab72-d6c4-550b-aa58-2fcc4a10af63', '45c76ab8-ab47-5348-899e-4bff15faba97', 'Couronne soda 2L',                  '6001234000010',   80.00,  110.00, 12, 'Soda Couronne 2 litres',           1, NOW(), NOW()),
  ('c5d23bdb-018b-5071-8ec9-f54ba566e540', '__TENANT_ID__', 'c705ab72-d6c4-550b-aa58-2fcc4a10af63', 'fa7f2e51-2bbf-5a18-83d5-496e961eedd9', 'Eau Culligan 1.5L',                 '6001234000011',   30.00,   45.00, 48, 'Eau purifiée 1,5 litres',          1, NOW(), NOW()),
  ('1f63cb3e-5e4b-5b61-8fae-3817006f7193', '__TENANT_ID__', 'c705ab72-d6c4-550b-aa58-2fcc4a10af63', '6bcd81cc-cbd2-50c8-8b81-f5405b1b8eac', 'Heineken 330ml',                    '6001234000012',   75.00,  100.00, 24, 'Bière Heineken canette 330ml',     1, NOW(), NOW()),
  ('eb235ca1-5792-5ebe-8c99-1f1188b22682', '__TENANT_ID__', 'c705ab72-d6c4-550b-aa58-2fcc4a10af63', 'fa7f2e51-2bbf-5a18-83d5-496e961eedd9', 'Jus Tampico 1L',                    '6001234000013',  100.00,  140.00, 12, 'Jus de fruits Tampico 1 litre',    1, NOW(), NOW()),
  ('40ece8ee-9b2b-59ad-bb2c-7ec4d9bd9059', '__TENANT_ID__', 'c705ab72-d6c4-550b-aa58-2fcc4a10af63', 'fa7f2e51-2bbf-5a18-83d5-496e961eedd9', 'Nescafé soluble 200g',              '6001234000014',  280.00,  360.00, 6,  'Café soluble Nescafé 200g',        1, NOW(), NOW()),

  -- Hygiène & Beauté
  ('0d25643d-494b-5075-a100-078c8d65dec4', '__TENANT_ID__', '1a8b4bfc-633c-59a2-a3d6-d0b87b011f5d', '85393c27-717d-52ac-9d8a-b25b17d7079c', 'Savon Palmolive 100g',              '6001234000015',   25.00,   40.00, 30, 'Savon de toilette 100g',           1, NOW(), NOW()),
  ('a2dac529-afbc-51f9-b477-c82369c74dd4', '__TENANT_ID__', '1a8b4bfc-633c-59a2-a3d6-d0b87b011f5d', '85393c27-717d-52ac-9d8a-b25b17d7079c', 'Shampoing Head & Shoulders 200ml', '6001234000016',  180.00,  250.00, 10, 'Shampoing antipelliculaire',       1, NOW(), NOW()),
  ('0a783db1-ccf6-55fd-9e07-8c186e580ebe', '__TENANT_ID__', '1a8b4bfc-633c-59a2-a3d6-d0b87b011f5d', '85393c27-717d-52ac-9d8a-b25b17d7079c', 'Colgate dentifrice 100ml',          '6001234000017',   85.00,  120.00, 15, 'Dentifrice blancheur 100ml',       1, NOW(), NOW()),
  ('7ebc8c72-caf4-5a43-8038-161a676e9176', '__TENANT_ID__', '1a8b4bfc-633c-59a2-a3d6-d0b87b011f5d', '85393c27-717d-52ac-9d8a-b25b17d7079c', 'Déodorant Dove Roll-on 50ml',       '6001234000018',  150.00,  210.00, 10, 'Déodorant 48h pour femme',         1, NOW(), NOW()),
  ('e856c1bd-c79a-5720-b42d-4b41475f7448', '__TENANT_ID__', '1a8b4bfc-633c-59a2-a3d6-d0b87b011f5d', 'fa7f2e51-2bbf-5a18-83d5-496e961eedd9', 'Vaseline 250ml',                    '6001234000019',  120.00,  170.00, 8,  'Crème hydratante Vaseline',        1, NOW(), NOW()),

  -- Ménage & Entretien
  ('ce833a48-5f0a-5ed5-8727-98fa3efae723', '__TENANT_ID__', '47027069-7d2b-558e-a26d-d04046844955', 'fa7f2e51-2bbf-5a18-83d5-496e961eedd9', 'Eau de Javel 1L',                   '6001234000020',   35.00,   55.00, 20, 'Eau de Javel désinfectante 1L',    1, NOW(), NOW()),
  ('8876cffd-f3ff-5089-a989-9a075eb2b1a3', '__TENANT_ID__', '47027069-7d2b-558e-a26d-d04046844955', 'fa7f2e51-2bbf-5a18-83d5-496e961eedd9', 'Détergent à lessive Ace 1kg',       '6001234000021',  180.00,  250.00, 10, 'Lessive en poudre Ace 1kg',        1, NOW(), NOW()),
  ('c33fe290-3172-5df6-bd69-a79b07c0a339', '__TENANT_ID__', '47027069-7d2b-558e-a26d-d04046844955', 'fa7f2e51-2bbf-5a18-83d5-496e961eedd9', 'Liquide vaisselle Axion 500ml',     '6001234000022',   90.00,  130.00, 12, 'Produit vaisselle Axion 500ml',    1, NOW(), NOW()),
  ('5fd3c849-7f9f-5a88-8ba6-1c3ec43c7302', '__TENANT_ID__', '47027069-7d2b-558e-a26d-d04046844955', 'fa7f2e51-2bbf-5a18-83d5-496e961eedd9', 'Papier hygiénique 12 rouleaux',     '6001234000023',  180.00,  250.00, 10, 'Papier hygiénique 2 épaisseurs',   1, NOW(), NOW()),

  -- Électronique
  ('5faab25e-3495-5de5-bf30-b133897258da', '__TENANT_ID__', '61613687-120d-5935-9410-01ab54025b99', '616ee0b8-3db9-5b6d-9b1d-770dd930069c', 'Câble USB-C 1m',                    '6001234000024',  120.00,  200.00, 5,  'Câble charge rapide USB-C',        1, NOW(), NOW()),
  ('f23af518-ab3e-520b-bee3-17cb96bc8281', '__TENANT_ID__', '61613687-120d-5935-9410-01ab54025b99', '616ee0b8-3db9-5b6d-9b1d-770dd930069c', 'Piles AA Duracell (pack 4)',         '6001234000025',   80.00,  130.00, 10, 'Piles alcalines AA x4',            1, NOW(), NOW()),
  ('4c75d258-2bbd-55bd-8d32-fe3aa7a898b9', '__TENANT_ID__', '61613687-120d-5935-9410-01ab54025b99', '616ee0b8-3db9-5b6d-9b1d-770dd930069c', 'Coque Samsung A15',                 '6001234000026',  200.00,  350.00, 5,  'Coque de protection Samsung A15',  1, NOW(), NOW()),
  ('13402aa0-b167-59b0-99c8-4a3d98a60f27', '__TENANT_ID__', '61613687-120d-5935-9410-01ab54025b99', '616ee0b8-3db9-5b6d-9b1d-770dd930069c', 'Écouteurs intra-auriculaires',      '6001234000027',  350.00,  600.00, 3,  'Écouteurs filaires jack 3.5mm',    1, NOW(), NOW()),

  -- Papeterie
  ('1e5e1072-223c-5f87-8760-9072e621a6cc', '__TENANT_ID__', '3f595cd8-0fb5-5a54-a937-1c1756506ee9', 'fa7f2e51-2bbf-5a18-83d5-496e961eedd9', 'Cahier 100 pages',                  '6001234000028',   35.00,   55.00, 20, 'Cahier quadrillé 100 pages',       1, NOW(), NOW()),
  ('676b751b-f5f7-588c-b5d8-6ed7523dd131', '__TENANT_ID__', '3f595cd8-0fb5-5a54-a937-1c1756506ee9', 'fa7f2e51-2bbf-5a18-83d5-496e961eedd9', 'Stylo Bic bleu (lot 10)',           '6001234000029',   60.00,   90.00, 15, 'Stylos à bille Bic x10',           1, NOW(), NOW()),
  ('d5b64ffb-e950-5397-8933-3ef9b056f4a0', '__TENANT_ID__', '3f595cd8-0fb5-5a54-a937-1c1756506ee9', 'fa7f2e51-2bbf-5a18-83d5-496e961eedd9', 'Règle plastique 30cm',              '6001234000030',   15.00,   25.00, 10, 'Règle transparente 30cm',          1, NOW(), NOW()),

  -- Santé
  ('6f89945a-58c6-560b-a906-091732855e86', '__TENANT_ID__', '2ab8e1ee-8f7b-5d90-8e4d-8d57286ef417', 'da549511-7db3-5c1b-9a31-8bf25a3c0713', 'Paracétamol 500mg (boîte 24)',      '6001234000031',   80.00,  120.00, 8,  'Antidouleur paracétamol 500mg',    1, NOW(), NOW()),
  ('2a9a72ce-6043-5b06-b2e7-d2465528492a', '__TENANT_ID__', '2ab8e1ee-8f7b-5d90-8e4d-8d57286ef417', 'da549511-7db3-5c1b-9a31-8bf25a3c0713', 'Vitamine C 1000mg (30 cp)',         '6001234000032',  150.00,  220.00, 5,  'Complément vitamines C 30 cp',     1, NOW(), NOW()),
  ('2bb3063f-6116-5c91-a62f-47a400fb7c16', '__TENANT_ID__', '2ab8e1ee-8f7b-5d90-8e4d-8d57286ef417', 'da549511-7db3-5c1b-9a31-8bf25a3c0713', 'Sérum physiologique 250ml',         '6001234000033',   90.00,  140.00, 8,  'Solution saline isotonique',       1, NOW(), NOW())

ON DUPLICATE KEY UPDATE name = VALUES(name);

-- -----------------------------------------------------------------------------
-- STOCK INITIAL (mouvements d'entrée)
-- -----------------------------------------------------------------------------
INSERT INTO stock_movements (id, tenant_id, product_id, `type`, quantity, source_type, note, created_at, updated_at) VALUES
  ('7963cf19-cfce-5c27-92f4-912ebb1a5ab6', '__TENANT_ID__', '945359f0-c87f-5fa8-ad34-3e516668c617', 'in_', 50,  'initial', 'Stock de démarrage', NOW(), NOW()),
  ('fb9c0d35-9a0d-55b9-ba03-07b8241c621e', '__TENANT_ID__', '79a6b17f-22c4-51d5-90dc-02ffeb27876b', 'in_', 30,  'initial', 'Stock de démarrage', NOW(), NOW()),
  ('dfcbef45-820a-5309-8f4c-7ec4fdd4669d', '__TENANT_ID__', 'e59449c9-9d9f-568a-a168-ff83ec68a912', 'in_', 40,  'initial', 'Stock de démarrage', NOW(), NOW()),
  ('7c988d0d-2e6c-52df-8ac4-430d4c0adcd7', '__TENANT_ID__', '824756ac-efde-5537-a7bd-b4a6f78af954', 'in_', 25,  'initial', 'Stock de démarrage', NOW(), NOW()),
  ('8effe8d0-07c0-57f0-97a6-55d3118707d6', '__TENANT_ID__', '5a876436-f7fc-5b60-a3ed-f005ef80c075', 'in_', 30,  'initial', 'Stock de démarrage', NOW(), NOW()),
  ('2fe93ee2-e954-5b79-9da5-a1cbd20c70ca', '__TENANT_ID__', 'b5bd4273-2b59-52a7-923d-f3b7672d5295', 'in_', 60,  'initial', 'Stock de démarrage', NOW(), NOW()),
  ('38356999-ab0c-5efa-954d-3050f358df42', '__TENANT_ID__', 'af2ec6ff-c2d4-515c-a67c-cc98da3660b8', 'in_', 20,  'initial', 'Stock de démarrage', NOW(), NOW()),
  ('f0fdf122-24dc-5600-8e97-b22a6d355d21', '__TENANT_ID__', '010e40bc-b938-5f62-8a20-7689aca81c55', 'in_', 100, 'initial', 'Stock de démarrage', NOW(), NOW()),
  ('645b2f98-7022-5e5c-a446-41d015408776', '__TENANT_ID__', 'bc449d99-4df6-5a88-a4b7-0df0539ef1ab', 'in_', 48,  'initial', 'Stock de démarrage', NOW(), NOW()),
  ('435db155-fd45-5711-bcf4-089b0cc26748', '__TENANT_ID__', '3aeca332-6072-5fb2-ac31-571e62ab3b37', 'in_', 24,  'initial', 'Stock de démarrage', NOW(), NOW()),
  ('96d4b3f6-8f0f-55cf-b779-d929a2a907b7', '__TENANT_ID__', 'c5d23bdb-018b-5071-8ec9-f54ba566e540', 'in_', 96,  'initial', 'Stock de démarrage', NOW(), NOW()),
  ('9b80e206-e3b6-5c46-b7fd-09b8af6a5820', '__TENANT_ID__', '1f63cb3e-5e4b-5b61-8fae-3817006f7193', 'in_', 48,  'initial', 'Stock de démarrage', NOW(), NOW()),
  ('cad5fa2d-50e8-5262-883e-151166b4f64a', '__TENANT_ID__', 'eb235ca1-5792-5ebe-8c99-1f1188b22682', 'in_', 24,  'initial', 'Stock de démarrage', NOW(), NOW()),
  ('a40988aa-4704-59a7-b6e6-0ce015f3e142', '__TENANT_ID__', '40ece8ee-9b2b-59ad-bb2c-7ec4d9bd9059', 'in_', 15,  'initial', 'Stock de démarrage', NOW(), NOW()),
  ('9a3960c4-c643-5dd7-ba1e-4b7927adff53', '__TENANT_ID__', '0d25643d-494b-5075-a100-078c8d65dec4', 'in_', 100, 'initial', 'Stock de démarrage', NOW(), NOW()),
  ('c4f35864-68e0-5326-a177-5c9b131c23dd', '__TENANT_ID__', 'a2dac529-afbc-51f9-b477-c82369c74dd4', 'in_', 30,  'initial', 'Stock de démarrage', NOW(), NOW()),
  ('d935cc3b-dc8c-5ea6-8053-e991d99868c2', '__TENANT_ID__', '0a783db1-ccf6-55fd-9e07-8c186e580ebe', 'in_', 40,  'initial', 'Stock de démarrage', NOW(), NOW()),
  ('1c9770fe-15b7-5101-b800-cfaf6a74c1bc', '__TENANT_ID__', '7ebc8c72-caf4-5a43-8038-161a676e9176', 'in_', 25,  'initial', 'Stock de démarrage', NOW(), NOW()),
  ('0954376a-0e80-5c34-a38a-d1b51217c36d', '__TENANT_ID__', 'e856c1bd-c79a-5720-b42d-4b41475f7448', 'in_', 30,  'initial', 'Stock de démarrage', NOW(), NOW()),
  ('9727a2b5-a806-5062-9624-f9f59b0fc8b2', '__TENANT_ID__', 'ce833a48-5f0a-5ed5-8727-98fa3efae723', 'in_', 50,  'initial', 'Stock de démarrage', NOW(), NOW()),
  ('a5dcf7db-e623-5d6f-886c-7acf17267509', '__TENANT_ID__', '8876cffd-f3ff-5089-a989-9a075eb2b1a3', 'in_', 30,  'initial', 'Stock de démarrage', NOW(), NOW()),
  ('61d4b91b-fd29-5eaf-9916-7cf09a327917', '__TENANT_ID__', 'c33fe290-3172-5df6-bd69-a79b07c0a339', 'in_', 40,  'initial', 'Stock de démarrage', NOW(), NOW()),
  ('87f59354-a204-5793-aa07-ad91634e284c', '__TENANT_ID__', '5fd3c849-7f9f-5a88-8ba6-1c3ec43c7302', 'in_', 20,  'initial', 'Stock de démarrage', NOW(), NOW()),
  ('4c150e32-366e-58a8-a4c8-d25fae7dc56a', '__TENANT_ID__', '5faab25e-3495-5de5-bf30-b133897258da', 'in_', 15,  'initial', 'Stock de démarrage', NOW(), NOW()),
  ('cd312e56-43cb-59db-b471-b2df0be302d5', '__TENANT_ID__', 'f23af518-ab3e-520b-bee3-17cb96bc8281', 'in_', 30,  'initial', 'Stock de démarrage', NOW(), NOW()),
  ('3a1f557e-61ad-562b-af09-4a984759cf51', '__TENANT_ID__', '4c75d258-2bbd-55bd-8d32-fe3aa7a898b9', 'in_', 10,  'initial', 'Stock de démarrage', NOW(), NOW()),
  ('5d0b5333-3195-5d2a-9e8f-aa7739602c45', '__TENANT_ID__', '13402aa0-b167-59b0-99c8-4a3d98a60f27', 'in_', 8,   'initial', 'Stock de démarrage', NOW(), NOW()),
  ('c56715e1-d703-5a97-ae3f-e9789e640f7a', '__TENANT_ID__', '1e5e1072-223c-5f87-8760-9072e621a6cc', 'in_', 50,  'initial', 'Stock de démarrage', NOW(), NOW()),
  ('2a069a98-d15f-547f-b6ba-0a707609d88b', '__TENANT_ID__', '676b751b-f5f7-588c-b5d8-6ed7523dd131', 'in_', 20,  'initial', 'Stock de démarrage', NOW(), NOW()),
  ('10e754da-71b5-5a2d-868b-a057772dc908', '__TENANT_ID__', 'd5b64ffb-e950-5397-8933-3ef9b056f4a0', 'in_', 30,  'initial', 'Stock de démarrage', NOW(), NOW()),
  ('4bfcb03a-565c-5129-921a-a749a4d3ee19', '__TENANT_ID__', '6f89945a-58c6-560b-a906-091732855e86', 'in_', 25,  'initial', 'Stock de démarrage', NOW(), NOW()),
  ('b4a2222e-c5cf-58e7-b762-5e0d95158b95', '__TENANT_ID__', '2a9a72ce-6043-5b06-b2e7-d2465528492a', 'in_', 15,  'initial', 'Stock de démarrage', NOW(), NOW()),
  ('3e6f54d4-917c-5564-9cc4-dc7016c55245', '__TENANT_ID__', '2bb3063f-6116-5c91-a62f-47a400fb7c16', 'in_', 20,  'initial', 'Stock de démarrage', NOW(), NOW())
ON DUPLICATE KEY UPDATE quantity = VALUES(quantity);
