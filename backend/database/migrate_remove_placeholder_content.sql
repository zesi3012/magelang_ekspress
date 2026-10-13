USE magelang_express;

DELETE FROM articles
WHERE id IN (
  'welcome',
  'koran-sekolah-sample',
  'article-1788704071746',
  'article-1788838433073'
);

DELETE FROM epapers
WHERE id = 'edisi-2026-09-06';
