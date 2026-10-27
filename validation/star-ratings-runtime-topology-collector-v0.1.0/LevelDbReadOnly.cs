using System;
using System.Collections.Generic;
using System.IO;
using System.Text;

namespace SpotifyControlValidation
{
    public sealed class LevelDbEntry
    {
        public byte[] Key { get; set; }
        public byte[] Value { get; set; }
        public ulong Sequence { get; set; }
        public bool Deleted { get; set; }
        public string Source { get; set; }
    }

    public sealed class LevelDbReadResult
    {
        public List<LevelDbEntry> Records { get; set; }
        public List<string> Errors { get; set; }
        public bool Complete { get; set; }

        public LevelDbReadResult()
        {
            Records = new List<LevelDbEntry>();
            Errors = new List<string>();
            Complete = true;
        }
    }

    public sealed class ChromiumDatabaseNameInfo
    {
        public bool Success { get; set; }
        public ulong DatabaseId { get; set; }
        public string Origin { get; set; }
        public string Name { get; set; }
        public string Error { get; set; }
    }

    public sealed class ChromiumObjectStoreNameInfo
    {
        public bool Success { get; set; }
        public ulong ObjectStoreId { get; set; }
        public string Name { get; set; }
        public string Error { get; set; }
    }

    public sealed class ChromiumObjectStoreKeyInfo
    {
        public bool Success { get; set; }
        public string PrimaryKey { get; set; }
        public int ValuePayloadOffset { get; set; }
        public string Error { get; set; }
    }

    internal sealed class PrefixInfo
    {
        public ulong DatabaseId;
        public ulong ObjectStoreId;
        public ulong IndexId;
        public int BytesConsumed;
    }

    internal sealed class BlockHandle
    {
        public ulong Offset;
        public ulong Size;
    }

    internal sealed class BlockEntry
    {
        public byte[] Key;
        public byte[] Value;
    }

    public static class LevelDbReadOnly
    {
        private const ulong TableMagic = 0xdb4775248b80fb57UL;
        private const int FooterLength = 48;
        private const int BlockTrailerLength = 5;
        private const int LogBlockSize = 32768;
        private const int LogHeaderSize = 7;

        public static LevelDbReadResult ReadDirectory(string directory)
        {
            LevelDbReadResult result = new LevelDbReadResult();
            Dictionary<string, LevelDbEntry> latest = new Dictionary<string, LevelDbEntry>(StringComparer.Ordinal);

            if (String.IsNullOrWhiteSpace(directory) || !Directory.Exists(directory))
            {
                result.Complete = false;
                result.Errors.Add("leveldb-directory-missing");
                return result;
            }

            string[] tables = Directory.GetFiles(directory, "*.ldb", SearchOption.TopDirectoryOnly);
            string[] sst = Directory.GetFiles(directory, "*.sst", SearchOption.TopDirectoryOnly);
            string[] logs = Directory.GetFiles(directory, "*.log", SearchOption.TopDirectoryOnly);
            Array.Sort(tables, StringComparer.OrdinalIgnoreCase);
            Array.Sort(sst, StringComparer.OrdinalIgnoreCase);
            Array.Sort(logs, StringComparer.OrdinalIgnoreCase);

            for (int i = 0; i < tables.Length; i++)
                ParseFileSafely(tables[i], true, latest, result);
            for (int i = 0; i < sst.Length; i++)
                ParseFileSafely(sst[i], true, latest, result);
            for (int i = 0; i < logs.Length; i++)
                ParseFileSafely(logs[i], false, latest, result);

            foreach (KeyValuePair<string, LevelDbEntry> pair in latest)
                result.Records.Add(pair.Value);
            result.Records.Sort(delegate(LevelDbEntry a, LevelDbEntry b)
            {
                int cmp = ByteArrayCompare(a.Key, b.Key);
                if (cmp != 0) return cmp;
                return a.Sequence.CompareTo(b.Sequence);
            });
            return result;
        }

        private static void ParseFileSafely(string path, bool table, Dictionary<string, LevelDbEntry> latest, LevelDbReadResult result)
        {
            try
            {
                byte[] bytes = ReadAllBytesShared(path);
                List<LevelDbEntry> entries = table ? ParseTable(bytes, Path.GetFileName(path)) : ParseLog(bytes, Path.GetFileName(path));
                for (int i = 0; i < entries.Count; i++)
                    AddLatest(latest, entries[i]);
            }
            catch (Exception ex)
            {
                result.Complete = false;
                result.Errors.Add(Path.GetFileName(path) + ":" + ex.GetType().Name + ":" + ex.Message);
            }
        }

        private static byte[] ReadAllBytesShared(string path)
        {
            using (FileStream stream = new FileStream(path, FileMode.Open, FileAccess.Read, FileShare.ReadWrite | FileShare.Delete))
            {
                if (stream.Length > Int32.MaxValue) throw new InvalidDataException("file-too-large");
                byte[] bytes = new byte[(int)stream.Length];
                int offset = 0;
                while (offset < bytes.Length)
                {
                    int read = stream.Read(bytes, offset, bytes.Length - offset);
                    if (read <= 0) throw new EndOfStreamException("short-read");
                    offset += read;
                }
                return bytes;
            }
        }

        private static void AddLatest(Dictionary<string, LevelDbEntry> latest, LevelDbEntry entry)
        {
            string key = ToHex(entry.Key);
            LevelDbEntry current;
            if (!latest.TryGetValue(key, out current) || entry.Sequence > current.Sequence ||
                (entry.Sequence == current.Sequence && String.CompareOrdinal(entry.Source, current.Source) > 0))
            {
                latest[key] = entry;
            }
        }

        private static List<LevelDbEntry> ParseTable(byte[] file, string source)
        {
            if (file.Length < FooterLength) throw new InvalidDataException("sst-footer-too-short");
            int footer = file.Length - FooterLength;
            ulong magic = ReadFixed64(file, file.Length - 8);
            if (magic != TableMagic) throw new InvalidDataException("sst-bad-magic");

            int pos = footer;
            BlockHandle meta = ReadBlockHandle(file, ref pos, footer + 40);
            BlockHandle index = ReadBlockHandle(file, ref pos, footer + 40);
            if (meta == null || index == null) throw new InvalidDataException("sst-footer-handles-invalid");

            byte[] indexBlock = ReadBlock(file, index);
            List<BlockEntry> indexEntries = ParsePrefixBlock(indexBlock);
            HashSet<ulong> seenOffsets = new HashSet<ulong>();
            List<LevelDbEntry> output = new List<LevelDbEntry>();

            for (int i = 0; i < indexEntries.Count; i++)
            {
                int hp = 0;
                BlockHandle dataHandle = ReadBlockHandle(indexEntries[i].Value, ref hp, indexEntries[i].Value.Length);
                if (dataHandle == null || hp != indexEntries[i].Value.Length)
                    throw new InvalidDataException("sst-index-handle-invalid");
                if (seenOffsets.Contains(dataHandle.Offset)) continue;
                seenOffsets.Add(dataHandle.Offset);

                byte[] dataBlock = ReadBlock(file, dataHandle);
                List<BlockEntry> dataEntries = ParsePrefixBlock(dataBlock);
                for (int j = 0; j < dataEntries.Count; j++)
                {
                    byte[] internalKey = dataEntries[j].Key;
                    if (internalKey.Length < 8) throw new InvalidDataException("sst-internal-key-too-short");
                    ulong tag = ReadFixed64(internalKey, internalKey.Length - 8);
                    ulong sequence = tag >> 8;
                    byte valueType = (byte)(tag & 0xff);
                    if (valueType != 0 && valueType != 1) throw new InvalidDataException("sst-internal-value-type-invalid");
                    byte[] userKey = Slice(internalKey, 0, internalKey.Length - 8);
                    output.Add(new LevelDbEntry
                    {
                        Key = userKey,
                        Value = valueType == 1 ? dataEntries[j].Value : new byte[0],
                        Sequence = sequence,
                        Deleted = valueType == 0,
                        Source = source
                    });
                }
            }
            return output;
        }

        private static byte[] ReadBlock(byte[] file, BlockHandle handle)
        {
            if (handle.Offset > (ulong)file.Length || handle.Size > (ulong)Int32.MaxValue)
                throw new InvalidDataException("sst-block-range-invalid");
            ulong end = handle.Offset + handle.Size + BlockTrailerLength;
            if (end > (ulong)file.Length || end < handle.Offset)
                throw new InvalidDataException("sst-block-range-invalid");
            int offset = checked((int)handle.Offset);
            int size = checked((int)handle.Size);
            byte compression = file[offset + size];
            byte[] payload = Slice(file, offset, size);
            if (compression == 0) return payload;
            if (compression == 1) return SnappyDecompress(payload);
            throw new InvalidDataException("sst-unsupported-compression-" + compression.ToString());
        }

        private static List<BlockEntry> ParsePrefixBlock(byte[] block)
        {
            if (block.Length < 4) throw new InvalidDataException("sst-block-too-short");
            uint restartCount = ReadFixed32(block, block.Length - 4);
            ulong restartBytes = ((ulong)restartCount + 1UL) * 4UL;
            if (restartCount == 0 || restartBytes > (ulong)block.Length)
                throw new InvalidDataException("sst-restart-array-invalid");
            int entriesEnd = block.Length - checked((int)restartBytes);
            int pos = 0;
            byte[] previous = new byte[0];
            List<BlockEntry> entries = new List<BlockEntry>();

            while (pos < entriesEnd)
            {
                ulong shared = ReadVarint(block, ref pos, entriesEnd);
                ulong nonShared = ReadVarint(block, ref pos, entriesEnd);
                ulong valueLength = ReadVarint(block, ref pos, entriesEnd);
                if (shared > (ulong)previous.Length || nonShared > (ulong)(entriesEnd - pos))
                    throw new InvalidDataException("sst-entry-key-length-invalid");
                if (valueLength > (ulong)(entriesEnd - pos) - nonShared)
                    throw new InvalidDataException("sst-entry-value-length-invalid");

                int ns = checked((int)nonShared);
                int vl = checked((int)valueLength);
                byte[] key = new byte[checked((int)shared) + ns];
                if (shared > 0) Buffer.BlockCopy(previous, 0, key, 0, checked((int)shared));
                if (ns > 0) Buffer.BlockCopy(block, pos, key, checked((int)shared), ns);
                pos += ns;
                byte[] value = Slice(block, pos, vl);
                pos += vl;
                entries.Add(new BlockEntry { Key = key, Value = value });
                previous = key;
            }
            if (pos != entriesEnd) throw new InvalidDataException("sst-entry-region-misaligned");
            return entries;
        }

        private static List<LevelDbEntry> ParseLog(byte[] file, string source)
        {
            List<LevelDbEntry> output = new List<LevelDbEntry>();
            MemoryStream fragmented = null;
            int pos = 0;
            while (pos < file.Length)
            {
                int inBlock = pos % LogBlockSize;
                int remainingInBlock = LogBlockSize - inBlock;
                if (remainingInBlock < LogHeaderSize)
                {
                    pos += remainingInBlock;
                    continue;
                }
                if (pos + LogHeaderSize > file.Length) break;

                ushort length = (ushort)(file[pos + 4] | (file[pos + 5] << 8));
                byte type = file[pos + 6];
                if (length == 0 && type == 0)
                {
                    pos += remainingInBlock;
                    continue;
                }
                if (length > remainingInBlock - LogHeaderSize || pos + LogHeaderSize + length > file.Length)
                    throw new InvalidDataException("log-physical-record-range-invalid");
                byte[] payload = Slice(file, pos + LogHeaderSize, length);
                pos += LogHeaderSize + length;

                if (type == 1)
                {
                    if (fragmented != null) throw new InvalidDataException("log-full-during-fragment");
                    ParseWriteBatch(payload, source, output);
                }
                else if (type == 2)
                {
                    if (fragmented != null) fragmented.Dispose();
                    fragmented = new MemoryStream();
                    fragmented.Write(payload, 0, payload.Length);
                }
                else if (type == 3)
                {
                    if (fragmented == null) throw new InvalidDataException("log-middle-without-first");
                    fragmented.Write(payload, 0, payload.Length);
                }
                else if (type == 4)
                {
                    if (fragmented == null) throw new InvalidDataException("log-last-without-first");
                    fragmented.Write(payload, 0, payload.Length);
                    byte[] logical = fragmented.ToArray();
                    fragmented.Dispose();
                    fragmented = null;
                    ParseWriteBatch(logical, source, output);
                }
                else
                {
                    throw new InvalidDataException("log-record-type-invalid-" + type.ToString());
                }
            }
            if (fragmented != null)
            {
                fragmented.Dispose();
                throw new InvalidDataException("log-incomplete-fragment");
            }
            return output;
        }

        private static void ParseWriteBatch(byte[] batch, string source, List<LevelDbEntry> output)
        {
            if (batch.Length < 12) throw new InvalidDataException("writebatch-too-short");
            ulong sequence = ReadFixed64(batch, 0);
            uint count = ReadFixed32(batch, 8);
            int pos = 12;
            uint parsed = 0;
            while (parsed < count)
            {
                if (pos >= batch.Length) throw new InvalidDataException("writebatch-truncated");
                byte type = batch[pos++];
                byte[] key = ReadLengthPrefixed(batch, ref pos, batch.Length);
                if (type == 1)
                {
                    byte[] value = ReadLengthPrefixed(batch, ref pos, batch.Length);
                    output.Add(new LevelDbEntry { Key = key, Value = value, Sequence = sequence + parsed, Deleted = false, Source = source });
                }
                else if (type == 0)
                {
                    output.Add(new LevelDbEntry { Key = key, Value = new byte[0], Sequence = sequence + parsed, Deleted = true, Source = source });
                }
                else
                {
                    throw new InvalidDataException("writebatch-entry-type-invalid-" + type.ToString());
                }
                parsed++;
            }
            if (pos != batch.Length) throw new InvalidDataException("writebatch-trailing-bytes");
        }

        private static byte[] SnappyDecompress(byte[] input)
        {
            int pos = 0;
            ulong expected64 = ReadVarint(input, ref pos, input.Length);
            if (expected64 > Int32.MaxValue) throw new InvalidDataException("snappy-output-too-large");
            int expected = (int)expected64;
            byte[] output = new byte[expected];
            int outPos = 0;

            while (pos < input.Length && outPos < expected)
            {
                byte tag = input[pos++];
                int kind = tag & 3;
                if (kind == 0)
                {
                    int code = tag >> 2;
                    ulong lengthMinusOne;
                    if (code < 60)
                    {
                        lengthMinusOne = (ulong)code;
                    }
                    else
                    {
                        int bytes = code - 59;
                        if (bytes < 1 || bytes > 4 || pos + bytes > input.Length)
                            throw new InvalidDataException("snappy-literal-length-invalid");
                        lengthMinusOne = 0;
                        for (int i = 0; i < bytes; i++)
                            lengthMinusOne |= ((ulong)input[pos++]) << (8 * i);
                    }
                    ulong length64 = lengthMinusOne + 1UL;
                    if (length64 > (ulong)(input.Length - pos) || length64 > (ulong)(expected - outPos))
                        throw new InvalidDataException("snappy-literal-range-invalid");
                    int length = checked((int)length64);
                    Buffer.BlockCopy(input, pos, output, outPos, length);
                    pos += length;
                    outPos += length;
                }
                else
                {
                    int length;
                    int offset;
                    if (kind == 1)
                    {
                        if (pos >= input.Length) throw new InvalidDataException("snappy-copy1-truncated");
                        length = 4 + ((tag >> 2) & 7);
                        offset = ((tag & 0xE0) << 3) | input[pos++];
                    }
                    else if (kind == 2)
                    {
                        if (pos + 2 > input.Length) throw new InvalidDataException("snappy-copy2-truncated");
                        length = 1 + (tag >> 2);
                        offset = input[pos] | (input[pos + 1] << 8);
                        pos += 2;
                    }
                    else
                    {
                        if (pos + 4 > input.Length) throw new InvalidDataException("snappy-copy4-truncated");
                        length = 1 + (tag >> 2);
                        uint off = ReadFixed32(input, pos);
                        pos += 4;
                        if (off > Int32.MaxValue) throw new InvalidDataException("snappy-copy-offset-too-large");
                        offset = (int)off;
                    }
                    if (offset <= 0 || offset > outPos || length > expected - outPos)
                        throw new InvalidDataException("snappy-copy-range-invalid");
                    for (int i = 0; i < length; i++)
                    {
                        output[outPos] = output[outPos - offset];
                        outPos++;
                    }
                }
            }
            if (pos != input.Length || outPos != expected)
                throw new InvalidDataException("snappy-length-mismatch");
            return output;
        }

        private static BlockHandle ReadBlockHandle(byte[] bytes, ref int pos, int limit)
        {
            ulong offset = ReadVarint(bytes, ref pos, limit);
            ulong size = ReadVarint(bytes, ref pos, limit);
            return new BlockHandle { Offset = offset, Size = size };
        }

        private static byte[] ReadLengthPrefixed(byte[] bytes, ref int pos, int limit)
        {
            ulong len64 = ReadVarint(bytes, ref pos, limit);
            if (len64 > (ulong)(limit - pos)) throw new InvalidDataException("length-prefixed-range-invalid");
            int len = checked((int)len64);
            byte[] value = Slice(bytes, pos, len);
            pos += len;
            return value;
        }

        internal static ulong ReadVarint(byte[] bytes, ref int pos, int limit)
        {
            ulong value = 0;
            int shift = 0;
            for (int i = 0; i < 10; i++)
            {
                if (pos >= limit) throw new InvalidDataException("varint-truncated");
                byte b = bytes[pos++];
                if (i == 9 && (b & 0xfe) != 0) throw new InvalidDataException("varint-overflow");
                value |= ((ulong)(b & 0x7f)) << shift;
                if ((b & 0x80) == 0) return value;
                shift += 7;
            }
            throw new InvalidDataException("varint-too-long");
        }

        internal static uint ReadFixed32(byte[] bytes, int offset)
        {
            if (offset < 0 || offset + 4 > bytes.Length) throw new InvalidDataException("fixed32-range-invalid");
            return (uint)(bytes[offset] | (bytes[offset + 1] << 8) | (bytes[offset + 2] << 16) | (bytes[offset + 3] << 24));
        }

        internal static ulong ReadFixed64(byte[] bytes, int offset)
        {
            if (offset < 0 || offset + 8 > bytes.Length) throw new InvalidDataException("fixed64-range-invalid");
            ulong value = 0;
            for (int i = 0; i < 8; i++) value |= ((ulong)bytes[offset + i]) << (8 * i);
            return value;
        }

        internal static byte[] Slice(byte[] bytes, int offset, int length)
        {
            if (offset < 0 || length < 0 || offset + length < offset || offset + length > bytes.Length)
                throw new InvalidDataException("slice-range-invalid");
            byte[] output = new byte[length];
            if (length > 0) Buffer.BlockCopy(bytes, offset, output, 0, length);
            return output;
        }

        internal static string ToHex(byte[] bytes)
        {
            StringBuilder sb = new StringBuilder(bytes.Length * 2);
            for (int i = 0; i < bytes.Length; i++) sb.Append(bytes[i].ToString("x2"));
            return sb.ToString();
        }

        private static int ByteArrayCompare(byte[] a, byte[] b)
        {
            int n = Math.Min(a.Length, b.Length);
            for (int i = 0; i < n; i++)
            {
                int cmp = a[i].CompareTo(b[i]);
                if (cmp != 0) return cmp;
            }
            return a.Length.CompareTo(b.Length);
        }
    }

    public static class ChromiumIndexedDb
    {
        public static ChromiumDatabaseNameInfo DecodeDatabaseName(LevelDbEntry entry)
        {
            ChromiumDatabaseNameInfo info = new ChromiumDatabaseNameInfo();
            try
            {
                if (entry == null || entry.Deleted) throw new InvalidDataException("entry-unavailable");
                int pos = 0;
                PrefixInfo prefix = DecodePrefix(entry.Key, ref pos);
                if (prefix.DatabaseId != 0 || prefix.ObjectStoreId != 0 || prefix.IndexId != 0)
                    throw new InvalidDataException("not-global-metadata");
                if (pos >= entry.Key.Length || entry.Key[pos++] != 201)
                    throw new InvalidDataException("not-database-name-metadata");
                string origin = ReadStringWithLength(entry.Key, ref pos, entry.Key.Length);
                string name = ReadStringWithLength(entry.Key, ref pos, entry.Key.Length);
                if (pos != entry.Key.Length) throw new InvalidDataException("database-name-key-trailing-bytes");
                if (entry.Value == null || entry.Value.Length != 8) throw new InvalidDataException("database-id-value-invalid");
                ulong id = LevelDbReadOnly.ReadFixed64(entry.Value, 0);
                info.Success = true;
                info.DatabaseId = id;
                info.Origin = origin;
                info.Name = name;
            }
            catch (Exception ex)
            {
                info.Success = false;
                info.Error = ex.Message;
            }
            return info;
        }

        public static ChromiumObjectStoreNameInfo DecodeObjectStoreName(LevelDbEntry entry, ulong databaseId)
        {
            ChromiumObjectStoreNameInfo info = new ChromiumObjectStoreNameInfo();
            try
            {
                if (entry == null || entry.Deleted) throw new InvalidDataException("entry-unavailable");
                int pos = 0;
                PrefixInfo prefix = DecodePrefix(entry.Key, ref pos);
                if (prefix.DatabaseId != databaseId || prefix.ObjectStoreId != 0 || prefix.IndexId != 0)
                    throw new InvalidDataException("not-database-metadata");
                if (pos >= entry.Key.Length || entry.Key[pos++] != 50)
                    throw new InvalidDataException("not-object-store-metadata");
                ulong objectStoreId = LevelDbReadOnly.ReadVarint(entry.Key, ref pos, entry.Key.Length);
                if (pos >= entry.Key.Length || entry.Key[pos++] != 0)
                    throw new InvalidDataException("not-object-store-name-metadata");
                if (pos != entry.Key.Length) throw new InvalidDataException("object-store-name-key-trailing-bytes");
                string name = ReadImplicitString(entry.Value);
                info.Success = true;
                info.ObjectStoreId = objectStoreId;
                info.Name = name;
            }
            catch (Exception ex)
            {
                info.Success = false;
                info.Error = ex.Message;
            }
            return info;
        }

        public static ChromiumObjectStoreKeyInfo DecodeObjectStoreStringKey(LevelDbEntry entry, ulong databaseId, ulong objectStoreId)
        {
            ChromiumObjectStoreKeyInfo info = new ChromiumObjectStoreKeyInfo();
            try
            {
                if (entry == null || entry.Deleted) throw new InvalidDataException("entry-unavailable");
                int pos = 0;
                PrefixInfo prefix = DecodePrefix(entry.Key, ref pos);
                if (prefix.DatabaseId != databaseId || prefix.ObjectStoreId != objectStoreId || prefix.IndexId != 1)
                    throw new InvalidDataException("not-object-store-data");
                if (pos >= entry.Key.Length || entry.Key[pos++] != 1)
                    throw new InvalidDataException("primary-key-not-string");
                string primary = ReadStringWithLength(entry.Key, ref pos, entry.Key.Length);
                if (pos != entry.Key.Length) throw new InvalidDataException("object-store-key-trailing-bytes");
                int valuePos = 0;
                LevelDbReadOnly.ReadVarint(entry.Value, ref valuePos, entry.Value.Length);
                info.Success = true;
                info.PrimaryKey = primary;
                info.ValuePayloadOffset = valuePos;
            }
            catch (Exception ex)
            {
                info.Success = false;
                info.Error = ex.Message;
            }
            return info;
        }

        public static bool ContainsEncodedText(byte[] bytes, string text)
        {
            if (bytes == null || text == null) return false;
            byte[][] needles = new byte[][]
            {
                Encoding.UTF8.GetBytes(text),
                Encoding.Unicode.GetBytes(text),
                BigEndianUnicode(text)
            };
            for (int n = 0; n < needles.Length; n++)
            {
                byte[] needle = needles[n];
                if (needle.Length == 0) return true;
                for (int i = 0; i <= bytes.Length - needle.Length; i++)
                {
                    bool match = true;
                    for (int j = 0; j < needle.Length; j++)
                    {
                        if (bytes[i + j] != needle[j]) { match = false; break; }
                    }
                    if (match) return true;
                }
            }
            return false;
        }

        private static PrefixInfo DecodePrefix(byte[] key, ref int pos)
        {
            if (key == null || key.Length < 4) throw new InvalidDataException("indexeddb-key-prefix-too-short");
            byte first = key[pos++];
            int dbBytes = ((first >> 5) & 7) + 1;
            int storeBytes = ((first >> 2) & 7) + 1;
            int indexBytes = (first & 3) + 1;
            if (pos + dbBytes + storeBytes + indexBytes > key.Length)
                throw new InvalidDataException("indexeddb-key-prefix-truncated");
            ulong db = ReadLittleEndianInteger(key, ref pos, dbBytes);
            ulong store = ReadLittleEndianInteger(key, ref pos, storeBytes);
            ulong index = ReadLittleEndianInteger(key, ref pos, indexBytes);
            return new PrefixInfo { DatabaseId = db, ObjectStoreId = store, IndexId = index, BytesConsumed = pos };
        }

        private static ulong ReadLittleEndianInteger(byte[] bytes, ref int pos, int count)
        {
            if (count < 1 || count > 8 || pos + count > bytes.Length)
                throw new InvalidDataException("little-endian-integer-range-invalid");
            ulong value = 0;
            for (int i = 0; i < count; i++) value |= ((ulong)bytes[pos++]) << (8 * i);
            return value;
        }

        private static string ReadStringWithLength(byte[] bytes, ref int pos, int limit)
        {
            ulong chars64 = LevelDbReadOnly.ReadVarint(bytes, ref pos, limit);
            if (chars64 > Int32.MaxValue) throw new InvalidDataException("utf16-string-too-long");
            int chars = (int)chars64;
            int byteCount = checked(chars * 2);
            if (pos + byteCount > limit) throw new InvalidDataException("utf16-string-truncated");
            string value = DecodeBigEndianUnicode(bytes, pos, byteCount);
            pos += byteCount;
            return value;
        }

        private static string ReadImplicitString(byte[] bytes)
        {
            if (bytes == null || (bytes.Length & 1) != 0) throw new InvalidDataException("implicit-utf16-string-invalid");
            return DecodeBigEndianUnicode(bytes, 0, bytes.Length);
        }

        private static string DecodeBigEndianUnicode(byte[] bytes, int offset, int count)
        {
            if ((count & 1) != 0) throw new InvalidDataException("utf16be-byte-count-odd");
            Encoding encoding = new UnicodeEncoding(true, false, true);
            return encoding.GetString(bytes, offset, count);
        }

        private static byte[] BigEndianUnicode(string text)
        {
            Encoding encoding = new UnicodeEncoding(true, false, true);
            return encoding.GetBytes(text);
        }
    }
}
