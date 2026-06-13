-- Run once on existing database
-- 1. Change method column from ENUM to VARCHAR to support CARD + future methods
ALTER TABLE payments MODIFY COLUMN method VARCHAR(20);

-- 2. Add note column for storing approval codes and other payment metadata
ALTER TABLE payments ADD COLUMN IF NOT EXISTS note TEXT NULL;
