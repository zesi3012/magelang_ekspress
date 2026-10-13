USE magelang_express;

ALTER TABLE payments
  ADD COLUMN IF NOT EXISTS payment_url TEXT NULL,
  ADD COLUMN IF NOT EXISTS gateway_token VARCHAR(255) NULL;
