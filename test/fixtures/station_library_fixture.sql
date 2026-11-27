PRAGMA foreign_keys=OFF;
BEGIN TRANSACTION;
CREATE TABLE station_meta (key TEXT PRIMARY KEY, value TEXT NOT NULL);
CREATE TABLE station_items (site_id TEXT PRIMARY KEY, kind TEXT NOT NULL, section TEXT NOT NULL, name TEXT NOT NULL, asset_path TEXT NOT NULL, source_type INTEGER, extra_json TEXT NOT NULL DEFAULT '{}', byte_len INTEGER NOT NULL, sha256 TEXT NOT NULL, content TEXT NOT NULL);
INSERT INTO station_meta (key, value) VALUES ('format', 'moyi-station-library');
INSERT INTO station_meta (key, value) VALUES ('format_version', '1');
INSERT INTO station_meta (key, value) VALUES ('library_version', 'fixture1');
INSERT INTO station_meta (key, value) VALUES ('required_core_version', '41');
INSERT INTO station_meta (key, value) VALUES ('required_core_label', '2026.11.27+41');
INSERT INTO station_meta (key, value) VALUES ('generated_at', '2026-11-27T00:00:00+08:00');
INSERT INTO station_meta (key, value) VALUES ('generator', 'gen_station_sql.py 1.1 (fixture)');
INSERT INTO station_meta (key, value) VALUES ('item_count', '2');
INSERT INTO station_meta (key, value) VALUES ('content_sha256', '6eb6fa56cce40edbcf5b77db036fff958c5f86b868fa408172b9ea7a80f8e762');
INSERT INTO station_meta (key, value) VALUES ('sign_alg', 'ed25519');
INSERT INTO station_meta (key, value) VALUES ('sign_pubkey', '2b3101912b442c89922075a11159eb67ca99f84e3ee09f59e91dfe8a95ebbde9');
INSERT INTO station_meta (key, value) VALUES ('signature', '456ee42f3086ed89d0993de6a2597fe57d450290d3beac7a6e62b91fa9eb0e4e25bbe696a4cff435d082117ca738a371194c5c92ecff0f5e8ad467aa4ddc6f0d');
INSERT INTO station_items (site_id, kind, section, name, asset_path, source_type, extra_json, byte_len, sha256, content) VALUES ('legado_8059_0', 'legado_json', 'novel', '978小说', 'assets/legado_sources/legado_8059_0.json', 0, '{}', 95, 'fee4eae17a171aeffc051918e133955731295511adb33bc8a4f0cc1fd2a6ae6e', '{"bookSourceName":"978小说","bookSourceUrl":"https://fixture.invalid/978","bookSourceType":0}');
INSERT INTO station_items (site_id, kind, section, name, asset_path, source_type, extra_json, byte_len, sha256, content) VALUES ('asmrhoney', 'audio_py', 'audio', '🔞ASMRHoney', 'assets/audio_spiders/asmrhoney.py', NULL, '{}', 50, '70c42da9c4440f1f310221ef742b991190aa4f43be541993fbd85e755aaaaac7', '# fixture spider for tests
class Spider:
    pass
');
COMMIT;
