USE magelang_express;

CREATE TABLE IF NOT EXISTS auth_sessions (
  token_hash CHAR(64) PRIMARY KEY,
  email VARCHAR(190) NOT NULL,
  role VARCHAR(40) NOT NULL,
  expires_at DATETIME NOT NULL,
  is_admin BOOLEAN NOT NULL DEFAULT FALSE,
  subscriber BOOLEAN NOT NULL DEFAULT FALSE,
  INDEX idx_auth_sessions_expiry (expires_at),
  INDEX idx_auth_sessions_email (email)
) ENGINE=InnoDB;
