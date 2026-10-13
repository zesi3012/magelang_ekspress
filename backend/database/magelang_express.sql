CREATE DATABASE IF NOT EXISTS magelang_express
  CHARACTER SET utf8mb4
  COLLATE utf8mb4_unicode_ci;
USE magelang_express;

CREATE TABLE IF NOT EXISTS users (
  id VARCHAR(190) PRIMARY KEY,
  email VARCHAR(190) NOT NULL UNIQUE,
  password_hash VARCHAR(255) NOT NULL,
  role VARCHAR(40) NOT NULL DEFAULT 'Reader',
  subscriber BOOLEAN NOT NULL DEFAULT FALSE,
  email_verified BOOLEAN NOT NULL DEFAULT FALSE,
  created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP
) ENGINE=InnoDB;

CREATE TABLE IF NOT EXISTS admin_users (
  id VARCHAR(190) PRIMARY KEY,
  email VARCHAR(190) NOT NULL UNIQUE,
  password_hash VARCHAR(255) NOT NULL,
  role VARCHAR(40) NOT NULL DEFAULT 'Author',
  status VARCHAR(20) NOT NULL DEFAULT 'active',
  created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP
) ENGINE=InnoDB;

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

CREATE TABLE IF NOT EXISTS categories (
  slug VARCHAR(100) PRIMARY KEY,
  name VARCHAR(150) NOT NULL,
  is_public BOOLEAN NOT NULL DEFAULT TRUE,
  created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP
) ENGINE=InnoDB;

CREATE TABLE IF NOT EXISTS articles (
  id VARCHAR(100) PRIMARY KEY,
  title VARCHAR(255) NOT NULL,
  slug VARCHAR(140) NOT NULL DEFAULT '',
  seo_title VARCHAR(70) NOT NULL DEFAULT '',
  seo_description VARCHAR(160) NOT NULL DEFAULT '',
  category VARCHAR(150) NOT NULL,
  excerpt TEXT NOT NULL,
  body LONGTEXT NOT NULL,
  main_image_url TEXT NULL,
  main_image_blur_url TEXT NULL,
  main_image_alt_text VARCHAR(180) NULL,
  is_premium BOOLEAN NOT NULL DEFAULT FALSE,
  status VARCHAR(30) NOT NULL DEFAULT 'draft',
  author VARCHAR(190) NOT NULL,
  updated_at DATETIME NULL,
  published_at DATETIME NULL,
  INDEX idx_articles_status (status),
  INDEX idx_articles_category (category)
) ENGINE=InnoDB;

CREATE TABLE IF NOT EXISTS article_revisions (
  id VARCHAR(100) PRIMARY KEY,
  article_id VARCHAR(100) NOT NULL,
  actor VARCHAR(190) NOT NULL,
  status VARCHAR(30) NOT NULL,
  note TEXT NOT NULL,
  snapshot JSON NOT NULL,
  created_at DATETIME NOT NULL,
  INDEX idx_article_revisions_article_created (article_id, created_at)
) ENGINE=InnoDB;

CREATE TABLE IF NOT EXISTS epapers (
  id VARCHAR(100) PRIMARY KEY,
  title VARCHAR(255) NOT NULL,
  edition VARCHAR(255) NOT NULL,
  edition_date VARCHAR(80) NOT NULL,
  total_pages INT NOT NULL DEFAULT 0,
  cover_image TEXT NULL,
  private_file_name VARCHAR(255) NULL,
  status VARCHAR(30) NOT NULL DEFAULT 'draft'
) ENGINE=InnoDB;

CREATE TABLE IF NOT EXISTS epaper_pages (
  issue_id VARCHAR(100) NOT NULL,
  page_number INT NOT NULL,
  label VARCHAR(150) NOT NULL,
  accent_color BIGINT NOT NULL,
  image TEXT NULL,
  article_ids JSON NOT NULL,
  PRIMARY KEY (issue_id, page_number),
  CONSTRAINT fk_epaper_pages_issue FOREIGN KEY (issue_id) REFERENCES epapers(id) ON DELETE CASCADE
) ENGINE=InnoDB;

CREATE TABLE IF NOT EXISTS epaper_articles (
  id VARCHAR(100) PRIMARY KEY,
  issue_id VARCHAR(100) NOT NULL,
  title VARCHAR(255) NOT NULL,
  category VARCHAR(150) NOT NULL,
  page_number INT NOT NULL,
  is_premium BOOLEAN NOT NULL DEFAULT FALSE,
  thumbnail TEXT NULL,
  content LONGTEXT NOT NULL,
  CONSTRAINT fk_epaper_articles_issue FOREIGN KEY (issue_id) REFERENCES epapers(id) ON DELETE CASCADE
) ENGINE=InnoDB;

CREATE TABLE IF NOT EXISTS subscription_packages (
  id VARCHAR(100) PRIMARY KEY,
  name VARCHAR(150) NOT NULL,
  duration_days INT NOT NULL,
  price INT NOT NULL,
  benefits JSON NOT NULL
) ENGINE=InnoDB;

CREATE TABLE IF NOT EXISTS subscriptions (
  user_id VARCHAR(190) NOT NULL,
  package_id VARCHAR(100) NOT NULL,
  start_date DATETIME NOT NULL,
  end_date DATETIME NOT NULL,
  status VARCHAR(30) NOT NULL DEFAULT 'active',
  PRIMARY KEY (user_id, package_id, start_date),
  CONSTRAINT fk_subscriptions_user FOREIGN KEY (user_id) REFERENCES users(email) ON DELETE CASCADE
) ENGINE=InnoDB;

CREATE TABLE IF NOT EXISTS payments (
  id VARCHAR(100) PRIMARY KEY,
  user_id VARCHAR(190) NOT NULL,
  package_id VARCHAR(100) NOT NULL,
  amount INT NOT NULL,
  payment_method VARCHAR(40) NOT NULL,
  status VARCHAR(30) NOT NULL DEFAULT 'pending',
  transaction_reference VARCHAR(190) NULL,
  payment_url TEXT NULL,
  gateway_token VARCHAR(255) NULL,
  created_at DATETIME NOT NULL,
  paid_at DATETIME NULL,
  UNIQUE KEY uq_payment_reference (transaction_reference),
  INDEX idx_payments_user (user_id),
  CONSTRAINT fk_payments_user FOREIGN KEY (user_id) REFERENCES users(email) ON DELETE CASCADE,
  CONSTRAINT fk_payments_package FOREIGN KEY (package_id) REFERENCES subscription_packages(id)
) ENGINE=InnoDB;

CREATE TABLE IF NOT EXISTS notifications (
  id VARCHAR(100) PRIMARY KEY,
  type VARCHAR(60) NOT NULL,
  title VARCHAR(190) NOT NULL,
  message TEXT NOT NULL,
  actor VARCHAR(190) NULL,
  resource_id VARCHAR(190) NULL,
  is_read BOOLEAN NOT NULL DEFAULT FALSE,
  created_at DATETIME NOT NULL,
  INDEX idx_notifications_created_at (created_at),
  INDEX idx_notifications_read (is_read)
) ENGINE=InnoDB;

CREATE TABLE IF NOT EXISTS saved_items (
  user_id VARCHAR(190) NOT NULL,
  item_type VARCHAR(40) NOT NULL,
  item_id VARCHAR(100) NOT NULL,
  created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (user_id, item_type, item_id)
) ENGINE=InnoDB;

CREATE TABLE IF NOT EXISTS download_logs (
  id BIGINT PRIMARY KEY AUTO_INCREMENT,
  user_id VARCHAR(190) NOT NULL,
  epaper_edition_id VARCHAR(100) NOT NULL,
  file_url TEXT NOT NULL,
  ip_address VARCHAR(80) NULL,
  user_agent TEXT NULL,
  downloaded_at DATETIME NOT NULL,
  INDEX idx_download_logs_user_date (user_id, downloaded_at),
  CONSTRAINT fk_download_logs_user FOREIGN KEY (user_id) REFERENCES users(email) ON DELETE CASCADE,
  CONSTRAINT fk_download_logs_epaper FOREIGN KEY (epaper_edition_id) REFERENCES epapers(id) ON DELETE CASCADE
) ENGINE=InnoDB;

CREATE TABLE IF NOT EXISTS audit_logs (
  id BIGINT PRIMARY KEY AUTO_INCREMENT,
  action VARCHAR(100) NOT NULL,
  resource_id VARCHAR(100) NOT NULL,
  actor VARCHAR(190) NOT NULL,
  created_at DATETIME NOT NULL
) ENGINE=InnoDB;

CREATE TABLE IF NOT EXISTS app_settings (
  id TINYINT UNSIGNED PRIMARY KEY,
  settings JSON NOT NULL,
  updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  CONSTRAINT chk_app_settings_singleton CHECK (id = 1)
) ENGINE=InnoDB;

INSERT IGNORE INTO subscription_packages (id, name, duration_days, price, benefits) VALUES
('premium_1_month', 'Premium 1 Bulan', 30, 49000, '["Artikel premium","E-paper","Baca nanti"]'),
('premium_3_month', 'Premium 3 Bulan', 90, 129000, '["Artikel premium","E-paper","Baca nanti"]'),
('premium_6_month', 'Premium 6 Bulan', 180, 249000, '["Artikel premium","E-paper","Baca nanti"]'),
('premium_1_year', 'Premium 1 Tahun', 365, 499000, '["Artikel premium","E-paper","Baca nanti"]');

UPDATE admin_users
SET status = 'disabled'
WHERE password_hash IN (
  '53e3aa3dedddb8f2f634984c0c5bef0a0a6f94a80228e129c83a9e08a72eaa80',
  'ubah-password-development'
);

UPDATE users
SET password_hash = '', email_verified = FALSE
WHERE password_hash IN (
  '53e3aa3dedddb8f2f634984c0c5bef0a0a6f94a80228e129c83a9e08a72eaa80',
  'ubah-password-development'
);

INSERT IGNORE INTO categories (slug, name, is_public) VALUES
('berita-utama', 'BERITA UTAMA', TRUE),
('lokal', 'LOKAL', TRUE),
('terbaru', 'TERBARU', TRUE),
('e-paper', 'E-PAPER', TRUE),
('magelang-kota', 'MAGELANG KOTA', TRUE),
('kabupaten-magelang', 'KABUPATEN MAGELANG', TRUE),
('jateng', 'JATENG', TRUE),
('politik', 'POLITIK', TRUE),
('ekonomi', 'EKONOMI', TRUE),
('pendidikan', 'PENDIDIKAN', TRUE),
('olahraga', 'OLAHRAGA', TRUE),
('wisata', 'WISATA', TRUE),
('lifestyle', 'LIFESTYLE', TRUE),
('opini', 'OPINI', TRUE);
