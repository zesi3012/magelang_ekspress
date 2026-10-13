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
