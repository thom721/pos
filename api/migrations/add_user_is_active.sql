-- Migration: ajouter is_active sur la table users
-- Nouvelles DB: géré automatiquement par SQLAlchemy create_all
-- DB existantes: exécuter ce script manuellement

ALTER TABLE users ADD COLUMN is_active BOOLEAN NOT NULL DEFAULT 1;
