from __future__ import annotations

import argparse
import json
import shutil
import struct
from pathlib import Path

MAGIC = 0xDB4775248B80FB57
INSTALLED_LIST = "marketplace:installed-extensions"
STAR_RECORD = "marketplace:installed:brimell/spicetify-star-ratings/dist/star-ratings.js"
MIGRATION = "internal:local-storage-migrated"
DB_NAME = "spicetify-marketplace"
STORE_NAME = "settings"
ORIGIN = "https://xpui.app"
DB_ID = 7
STORE_ID = 3


def varint(value: int) -> bytes:
    if value < 0:
        raise ValueError("negative varint")
    out = bytearray()
    while value >= 0x80:
        out.append((value & 0x7F) | 0x80)
        value >>= 7
    out.append(value)
    return bytes(out)


def fixed32(value: int) -> bytes:
    return struct.pack("<I", value)


def fixed64(value: int) -> bytes:
    return struct.pack("<Q", value)


def prefix(database_id: int, object_store_id: int, index_id: int) -> bytes:
    def enc_len(value: int, maximum: int) -> tuple[int, bytes]:
        width = max(1, (value.bit_length() + 7) // 8)
        if width > maximum:
            raise ValueError("prefix id too wide")
        return width, value.to_bytes(width, "little")

    dbw, db = enc_len(database_id, 8)
    osw, store = enc_len(object_store_id, 8)
    ixw, index = enc_len(index_id, 4)
    first = ((dbw - 1) << 5) | ((osw - 1) << 2) | (ixw - 1)
    return bytes([first]) + db + store + index


def string_with_length(text: str) -> bytes:
    encoded = text.encode("utf-16-be")
    return varint(len(encoded) // 2) + encoded


def database_name_key() -> bytes:
    return prefix(0, 0, 0) + bytes([201]) + string_with_length(ORIGIN) + string_with_length(DB_NAME)


def object_store_name_key() -> bytes:
    return prefix(DB_ID, 0, 0) + bytes([50]) + varint(STORE_ID) + b"\x00"


def object_store_data_key(primary: str) -> bytes:
    return prefix(DB_ID, STORE_ID, 1) + b"\x01" + string_with_length(primary)


def object_store_value(payload: bytes) -> bytes:
    return varint(1) + payload


def internal_key(user_key: bytes, sequence: int, value_type: int = 1) -> bytes:
    return user_key + fixed64((sequence << 8) | value_type)


def block(entries: list[tuple[bytes, bytes]]) -> bytes:
    body = bytearray()
    restart_offsets: list[int] = []
    previous = b""
    for key, value in entries:
        # One restart for every entry keeps the fixture simple and valid.
        restart_offsets.append(len(body))
        body += varint(0)
        body += varint(len(key))
        body += varint(len(value))
        body += key
        body += value
        previous = key
    if not entries:
        restart_offsets = [0]
    for offset in restart_offsets:
        body += fixed32(offset)
    body += fixed32(len(restart_offsets))
    return bytes(body)


def snappy_literal(raw: bytes) -> bytes:
    out = bytearray(varint(len(raw)))
    length_minus_one = len(raw) - 1
    if len(raw) <= 60:
        out.append(length_minus_one << 2)
    else:
        width = max(1, (length_minus_one.bit_length() + 7) // 8)
        if width > 4:
            raise ValueError("fixture literal too large")
        out.append((59 + width) << 2)
        out += length_minus_one.to_bytes(width, "little")
    out += raw
    return bytes(out)


def append_stored_block(file_bytes: bytearray, raw: bytes, compression: int) -> tuple[int, int]:
    offset = len(file_bytes)
    stored = raw if compression == 0 else snappy_literal(raw)
    file_bytes += stored
    file_bytes.append(compression)
    file_bytes += b"\x00\x00\x00\x00"  # CRC is intentionally ignored by the read-only validation reader.
    return offset, len(stored)


def block_handle(offset: int, size: int) -> bytes:
    return varint(offset) + varint(size)


def build_table(path: Path, records: list[tuple[bytes, bytes, int, int]], *, snappy: bool = False) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    # LevelDB sorts by internal comparator. For our unique user keys, byte sorting is sufficient.
    entries = sorted((internal_key(k, seq, typ), value if typ == 1 else b"") for k, value, seq, typ in records)
    data_raw = block(entries)
    file_bytes = bytearray()
    data_offset, data_size = append_stored_block(file_bytes, data_raw, 1 if snappy else 0)

    meta_raw = block([])
    meta_offset, meta_size = append_stored_block(file_bytes, meta_raw, 0)

    separator = entries[-1][0] if entries else b"\x00"
    index_raw = block([(separator, block_handle(data_offset, data_size))])
    index_offset, index_size = append_stored_block(file_bytes, index_raw, 0)

    footer_handles = block_handle(meta_offset, meta_size) + block_handle(index_offset, index_size)
    if len(footer_handles) > 40:
        raise ValueError("footer handles too long")
    file_bytes += footer_handles + (b"\x00" * (40 - len(footer_handles))) + fixed64(MAGIC)
    path.write_bytes(file_bytes)


def write_batch(sequence: int, operations: list[tuple[str, bytes, bytes | None]]) -> bytes:
    out = bytearray(fixed64(sequence) + fixed32(len(operations)))
    for kind, key, value in operations:
        if kind == "put":
            assert value is not None
            out.append(1)
            out += varint(len(key)) + key
            out += varint(len(value)) + value
        elif kind == "delete":
            out.append(0)
            out += varint(len(key)) + key
        else:
            raise ValueError(kind)
    return bytes(out)


def build_log(path: Path, batch: bytes) -> None:
    if len(batch) > 32000:
        raise ValueError("fixture batch too large")
    path.parent.mkdir(parents=True, exist_ok=True)
    header = b"\x00\x00\x00\x00" + struct.pack("<H", len(batch)) + b"\x01"
    path.write_bytes(header + batch)


def positive_records(sequence_base: int = 100) -> list[tuple[bytes, bytes, int, int]]:
    return [
        (database_name_key(), fixed64(DB_ID), sequence_base + 0, 1),
        (object_store_name_key(), STORE_NAME.encode("utf-16-be"), sequence_base + 1, 1),
        (object_store_data_key(MIGRATION), object_store_value(b"1"), sequence_base + 2, 1),
        (object_store_data_key(INSTALLED_LIST), object_store_value(json.dumps([STAR_RECORD]).encode("utf-8")), sequence_base + 3, 1),
        (object_store_data_key(STAR_RECORD), object_store_value(b'{"name":"Star Ratings","branch":"main"}'), sequence_base + 4, 1),
    ]


def negative_records(sequence_base: int = 100) -> list[tuple[bytes, bytes, int, int]]:
    other = "marketplace:installed:someone/other-extension/dist/other.js"
    return [
        (database_name_key(), fixed64(DB_ID), sequence_base + 0, 1),
        (object_store_name_key(), STORE_NAME.encode("utf-16-be"), sequence_base + 1, 1),
        (object_store_data_key(MIGRATION), object_store_value(b"1"), sequence_base + 2, 1),
        (object_store_data_key(INSTALLED_LIST), object_store_value(json.dumps([other]).encode("utf-8")), sequence_base + 3, 1),
        (object_store_data_key(other), object_store_value(b'{"name":"Other"}'), sequence_base + 4, 1),
    ]


def write_config(root: Path, configured: bool) -> None:
    path = root / "spicetify" / "config-xpui.ini"
    path.parent.mkdir(parents=True, exist_ok=True)
    extensions = "bookmark.js|sc-star-ratings.js|shuffle+.js" if configured else "bookmark.js|shuffle+.js"
    path.write_text(f"[Setting]\nextensions = {extensions}\ncustom_apps = marketplace\n", encoding="utf-8")


def write_active(root: Path, present: bool) -> None:
    if not present:
        return
    path = root / "Spotify" / "Apps" / "xpui" / "extensions" / "sc-star-ratings.js"
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_bytes(b"synthetic-active-star-ratings-fixture")


def indexeddb_dir(local: Path, profile: str = "Browser") -> Path:
    return local / "Spotify" / profile / "IndexedDB" / "https_xpui.app_0.indexeddb.leveldb"


def localstorage_dir(local: Path, profile: str = "Browser") -> Path:
    return local / "Spotify" / profile / "Local Storage" / "leveldb"


def build_fixture(root: Path, kind: str) -> None:
    app = root / "appdata"
    local = root / "localappdata"
    app.mkdir(parents=True, exist_ok=True)
    local.mkdir(parents=True, exist_ok=True)

    if kind == "dual":
        write_config(app, True)
        write_active(app, True)
        build_table(indexeddb_dir(local) / "000001.ldb", positive_records(), snappy=False)
    elif kind == "configured-only":
        write_config(app, True)
        write_active(app, True)
        build_table(indexeddb_dir(local) / "000001.ldb", negative_records(), snappy=False)
    elif kind == "marketplace-only":
        write_config(app, False)
        build_table(indexeddb_dir(local) / "000001.ldb", positive_records(), snappy=True)
    elif kind == "tombstoned":
        write_config(app, True)
        write_active(app, True)
        db = indexeddb_dir(local)
        build_table(db / "000001.ldb", positive_records(), snappy=False)
        batch = write_batch(300, [
            ("delete", object_store_data_key(INSTALLED_LIST), None),
            ("delete", object_store_data_key(STAR_RECORD), None),
        ])
        build_log(db / "000002.log", batch)
    elif kind == "corrupt":
        write_config(app, False)
        db = indexeddb_dir(local)
        build_table(db / "000001.ldb", positive_records(), snappy=False)
        (db / "000099.ldb").write_bytes(b"deliberately-corrupt-table")
    elif kind == "localstorage-only":
        write_config(app, False)
        db = localstorage_dir(local)
        records = [
            ((b"ls:" + INSTALLED_LIST.encode("utf-8")), json.dumps([STAR_RECORD]).encode("utf-8"), 100, 1),
            ((b"ls:" + STAR_RECORD.encode("utf-8")), b'{"name":"Star Ratings"}', 101, 1),
        ]
        build_table(db / "000001.ldb", records, snappy=False)
    else:
        raise ValueError(kind)


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--out", required=True, type=Path)
    args = parser.parse_args()
    if args.out.exists():
        shutil.rmtree(args.out)
    args.out.mkdir(parents=True)

    kinds = ["dual", "configured-only", "marketplace-only", "tombstoned", "corrupt", "localstorage-only"]
    for kind in kinds:
        build_fixture(args.out / kind, kind)
    (args.out / "expected.json").write_text(
        json.dumps(
            {
                "dual": "dual-owned-risk",
                "configured-only": "configured-only-likely",
                "marketplace-only": "marketplace-only-likely",
                "tombstoned": "configured-only-likely",
                "corrupt": "inconclusive",
                "localstorage-only": "marketplace-only-likely",
            },
            indent=2,
            sort_keys=True,
        ) + "\n",
        encoding="utf-8",
        newline="\n",
    )
    print("STAR_RATINGS_TOPOLOGY_FIXTURES_BUILT", args.out)


if __name__ == "__main__":
    main()
