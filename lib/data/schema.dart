/// 与桌面端 `src-tauri/src/db/schema.rs`（SCHEMA_VERSION = 12）**逐字对齐**的
/// 建表语句。唯一权威是那边的 Rust 文件；这里改任何一列都要回头核对。
///
/// 额外多一张 `media_ids`：桌面 schema 没有「MediaStore 行号」这个概念，但
/// Flutter 侧要拿它向系统要缩略图（`ContentResolver.loadThumbnail`）。它是
/// **本端私有**的映射表，用 `IF NOT EXISTS` 在每次打开时补建 —— 导入的桌面
/// 备份（v12）没有这张表，也不会因此打不开。
library;

const List<String> kSchemaV12 = [
  '''
  CREATE TABLE libraries (
      id              INTEGER PRIMARY KEY AUTOINCREMENT,
      path            TEXT    NOT NULL UNIQUE,
      name            TEXT    NOT NULL,
      created_at      INTEGER NOT NULL,
      last_scanned_at INTEGER
  )
  ''',
  '''
  CREATE TABLE images (
      id          INTEGER PRIMARY KEY AUTOINCREMENT,
      library_id  INTEGER NOT NULL REFERENCES libraries(id) ON DELETE CASCADE,
      path        TEXT    NOT NULL UNIQUE,
      filename    TEXT    NOT NULL,
      extension   TEXT    NOT NULL,
      width       INTEGER,
      height      INTEGER,
      file_size   INTEGER NOT NULL,
      modified_at INTEGER NOT NULL,
      taken_at    INTEGER,
      is_favorite INTEGER NOT NULL DEFAULT 0,
      rating      INTEGER NOT NULL DEFAULT 0,
      indexed_at  INTEGER NOT NULL,
      artist_uid  TEXT,
      pid         TEXT
  )
  ''',
  'CREATE INDEX idx_images_library ON images(library_id)',
  'CREATE INDEX idx_images_filename ON images(filename)',
  'CREATE INDEX idx_images_modified ON images(modified_at DESC)',
  'CREATE INDEX idx_images_favorite ON images(is_favorite) WHERE is_favorite = 1',
  'CREATE INDEX idx_images_artist ON images(artist_uid)',
  'CREATE INDEX idx_images_pid ON images(pid)',
  '''
  CREATE TABLE albums (
      id             INTEGER PRIMARY KEY AUTOINCREMENT,
      name           TEXT    NOT NULL UNIQUE,
      description    TEXT,
      cover_image_id INTEGER REFERENCES images(id) ON DELETE SET NULL,
      created_at     INTEGER NOT NULL
  )
  ''',
  '''
  CREATE TABLE album_images (
      album_id INTEGER NOT NULL REFERENCES albums(id) ON DELETE CASCADE,
      image_id INTEGER NOT NULL REFERENCES images(id) ON DELETE CASCADE,
      position INTEGER NOT NULL DEFAULT 0,
      added_at INTEGER NOT NULL,
      PRIMARY KEY (album_id, image_id)
  )
  ''',
  'CREATE INDEX idx_album_images_image ON album_images(image_id)',
  '''
  CREATE TABLE tags (
      id         INTEGER PRIMARY KEY AUTOINCREMENT,
      name       TEXT    NOT NULL UNIQUE,
      color      TEXT,
      created_at INTEGER NOT NULL
  )
  ''',
  '''
  CREATE TABLE image_tags (
      image_id INTEGER NOT NULL REFERENCES images(id) ON DELETE CASCADE,
      tag_id   INTEGER NOT NULL REFERENCES tags(id) ON DELETE CASCADE,
      PRIMARY KEY (image_id, tag_id)
  )
  ''',
  'CREATE INDEX idx_image_tags_tag ON image_tags(tag_id)',
  '''
  CREATE TABLE thumbnails (
      image_id     INTEGER NOT NULL REFERENCES images(id) ON DELETE CASCADE,
      size         INTEGER NOT NULL,
      path         TEXT    NOT NULL,
      width        INTEGER NOT NULL,
      height       INTEGER NOT NULL,
      generated_at INTEGER NOT NULL,
      PRIMARY KEY (image_id, size)
  )
  ''',
  '''
  CREATE TABLE settings (
      key   TEXT PRIMARY KEY,
      value TEXT NOT NULL
  )
  ''',
  '''
  CREATE TABLE artworks (
      id             INTEGER PRIMARY KEY AUTOINCREMENT,
      pid            TEXT    NOT NULL,
      original_path  TEXT    NOT NULL,
      thumbnail_path TEXT,
      page           INTEGER NOT NULL DEFAULT 0,
      created_at     INTEGER NOT NULL,
      artist_uid     TEXT,
      width          INTEGER,
      height         INTEGER
  )
  ''',
  'CREATE UNIQUE INDEX idx_artworks_pid_page ON artworks(pid, page)',
  'CREATE INDEX idx_artworks_pid ON artworks(pid)',
  'CREATE INDEX idx_artworks_artist ON artworks(artist_uid)',
  '''
  CREATE TABLE artwork_roots (
      path       TEXT PRIMARY KEY,
      created_at INTEGER NOT NULL
  )
  ''',
  '''
  CREATE TABLE ignored_artworks (
      pid        TEXT NOT NULL,
      page       INTEGER NOT NULL,
      created_at INTEGER NOT NULL,
      PRIMARY KEY (pid, page)
  )
  ''',
  '''
  CREATE TABLE artists (
      uid        TEXT PRIMARY KEY,
      name       TEXT NOT NULL,
      created_at INTEGER NOT NULL
  )
  ''',
  '''
  CREATE TABLE illust_meta (
      pid            TEXT PRIMARY KEY,
      title          TEXT NOT NULL DEFAULT '',
      artist_uid     TEXT,
      artist_name    TEXT,
      artist_account TEXT,
      page_count     INTEGER NOT NULL DEFAULT 0,
      x_restrict     INTEGER NOT NULL DEFAULT 0,
      sanity_level   INTEGER NOT NULL DEFAULT 0,
      illust_type    INTEGER NOT NULL DEFAULT 0,
      create_date    TEXT,
      fetched_at     INTEGER NOT NULL,
      error          TEXT,
      missing        INTEGER NOT NULL DEFAULT 0
  )
  ''',
  'CREATE INDEX idx_illust_meta_artist ON illust_meta(artist_uid)',
  'CREATE INDEX idx_illust_meta_missing ON illust_meta(missing)',
  '''
  CREATE TABLE illust_tags (
      pid TEXT NOT NULL,
      tag TEXT NOT NULL,
      PRIMARY KEY (pid, tag)
  )
  ''',
  'CREATE INDEX idx_illust_tags_tag ON illust_tags(tag)',
  '''
  CREATE TABLE tag_galleries (
      id         INTEGER PRIMARY KEY AUTOINCREMENT,
      name       TEXT NOT NULL,
      tags       TEXT NOT NULL DEFAULT '[]',
      rating     INTEGER NOT NULL DEFAULT -1,
      created_at INTEGER NOT NULL
  )
  ''',
  '''
  CREATE TABLE tag_gallery_pins (
      gallery_id INTEGER NOT NULL REFERENCES tag_galleries(id) ON DELETE CASCADE,
      artwork_id INTEGER NOT NULL REFERENCES artworks(id) ON DELETE CASCADE,
      created_at INTEGER NOT NULL,
      PRIMARY KEY (gallery_id, artwork_id)
  )
  ''',
  'CREATE INDEX idx_tag_gallery_pins_artwork ON tag_gallery_pins(artwork_id)',
];

/// 本端私有表：path → MediaStore 行号。缩略图要用行号去系统要，路径是两边
/// 唯一的稳定桥梁（桌面导入的行没有行号，此时 UI 退回文件解码）。
const String kMediaIdsTable = '''
CREATE TABLE IF NOT EXISTS media_ids (
    path     TEXT PRIMARY KEY,
    media_id INTEGER NOT NULL
)
''';

/// 桌面备份里必须存在的表（与 Kotlin 版 BackupImporter 的校验一致）。
const List<String> kRequiredTables = [
  'libraries', 'images', 'albums', 'album_images', 'tags', 'image_tags',
  'thumbnails', 'settings', 'artworks', 'artwork_roots', 'ignored_artworks',
  'artists', 'illust_meta', 'illust_tags', 'tag_galleries', 'tag_gallery_pins',
];
