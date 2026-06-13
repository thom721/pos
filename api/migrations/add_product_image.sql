-- Add image_url column to products table
-- New databases: handled automatically by SQLAlchemy create_all
-- Existing databases: run this once
ALTER TABLE products ADD COLUMN IF NOT EXISTS image_url VARCHAR(500) NULL;
