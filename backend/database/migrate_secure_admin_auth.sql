USE magelang_express;

-- Disable only the legacy administrator account protected by the publicly
-- known development password hash/plaintext. Keep the row for audit history.
UPDATE admin_users
SET status = 'disabled'
WHERE password_hash IN (
  '53e3aa3dedddb8f2f634984c0c5bef0a0a6f94a80228e129c83a9e08a72eaa80',
  'ubah-password-development'
);

-- Revoke the same known development credential from reader accounts without
-- deleting their subscriptions, invoices, saved items, or audit references.
UPDATE users
SET password_hash = '', email_verified = FALSE
WHERE password_hash IN (
  '53e3aa3dedddb8f2f634984c0c5bef0a0a6f94a80228e129c83a9e08a72eaa80',
  'ubah-password-development'
);
