# Dev-only (tests/ is not shipped). A small reader for the game's local CASC storage and its DB2 (WDC5) tables, with
# only the Python standard library. Reads, never writes, the WoW folder.
#   python -I tests/casc_read.py [product] [table ...]        e.g. python -I tests/casc_read.py wowf GameObjects
# Prints each table's row count and a few rows. Used by tests/make_object_models.py (R106-99).
# Steps: .build.info -> build config (root, encoding keys) -> local .idx indexes (encoded key -> data.### place) ->
# BLTE blocks (raw / zlib; encrypted blocks come back as zeros) -> encoding file (content key -> encoded key) ->
# root file (file data id -> content key) -> DB2 file -> WDC5 rows.
import os, struct, sys, zlib

WOW = r"D:\BattleNet\World of Warcraft"
LOCALE_ENUS = 0x2
# file data ids of the tables we read (wago.tools listfile; checked by name hash below when the root has names)
FDIDS = {"GameObjects": 841620, "GameObjectDisplayInfo": 1266277}


# ---------------------------------------------------------------- Jenkins lookup3 hashlittle2 (root name hashes)
def _rot(x, k): return ((x << k) | (x >> (32 - k))) & 0xFFFFFFFF


def hashlittle2(data, pc=0, pb=0):
    M = 0xFFFFFFFF
    length = len(data)
    a = b = c = (0xDEADBEEF + length + pc) & M
    c = (c + pb) & M
    i = 0
    while length > 12:
        a = (a + struct.unpack_from("<I", data, i)[0]) & M
        b = (b + struct.unpack_from("<I", data, i + 4)[0]) & M
        c = (c + struct.unpack_from("<I", data, i + 8)[0]) & M
        a = (a - c) & M; a ^= _rot(c, 4); c = (c + b) & M
        b = (b - a) & M; b ^= _rot(a, 6); a = (a + c) & M
        c = (c - b) & M; c ^= _rot(b, 8); b = (b + a) & M
        a = (a - c) & M; a ^= _rot(c, 16); c = (c + b) & M
        b = (b - a) & M; b ^= _rot(a, 19); a = (a + c) & M
        c = (c - b) & M; c ^= _rot(b, 4); b = (b + a) & M
        length -= 12
        i += 12
    if length == 0:
        return c, b
    tail = data[i:] + b"\0" * (12 - length)
    a = (a + struct.unpack_from("<I", tail, 0)[0]) & M
    b = (b + struct.unpack_from("<I", tail, 4)[0]) & M
    c = (c + struct.unpack_from("<I", tail, 8)[0]) & M
    c ^= b; c = (c - _rot(b, 14)) & M
    a ^= c; a = (a - _rot(c, 11)) & M
    b ^= a; b = (b - _rot(a, 25)) & M
    c ^= b; c = (c - _rot(b, 16)) & M
    a ^= c; a = (a - _rot(c, 4)) & M
    b ^= a; b = (b - _rot(a, 14)) & M
    c ^= b; c = (c - _rot(b, 24)) & M
    return c, b


def name_hash(path):
    c, b = hashlittle2(path.upper().replace("/", "\\").encode())
    return (c << 32) | b


# ---------------------------------------------------------------- storage
class Casc:
    def __init__(self, product="wowf", wow=WOW):
        self.data_dir = os.path.join(wow, "Data")
        self.build_key = self._build_key(os.path.join(wow, ".build.info"), product)
        cfg = self._config(self.build_key)
        self.root_ckey = bytes.fromhex(cfg["root"].split()[0])
        self.encoding_ekey = bytes.fromhex(cfg["encoding"].split()[1])
        self.build_name = cfg.get("build-name", "?")
        self.index = {}
        self._load_indexes()
        self.ckey_to_ekey = {}
        self._load_encoding()
        self.roots = {}  # fdid -> [(locale, content flags, ckey)]
        self.names = {}  # name hash -> fdid
        self._load_root()

    @staticmethod
    def _build_key(path, product):
        with open(path, encoding="utf-8") as f:
            lines = [l.rstrip("\n") for l in f if l.strip()]
        head = [h.split("!")[0] for h in lines[0].split("|")]
        for line in lines[1:]:
            row = dict(zip(head, line.split("|")))
            if row.get("Product") == product:
                return row["Build Key"]
        raise SystemExit("product %s not in .build.info" % product)

    def _config(self, key):
        path = os.path.join(self.data_dir, "config", key[0:2], key[2:4], key)
        out = {}
        with open(path, encoding="utf-8") as f:
            for line in f:
                if " = " in line and not line.startswith("#"):
                    k, v = line.rstrip("\n").split(" = ", 1)
                    out[k] = v
        return out

    def _load_indexes(self):
        folder = os.path.join(self.data_dir, "data")
        latest = {}
        for name in os.listdir(folder):
            if name.endswith(".idx") and len(name) == 14:
                bucket, version = int(name[0:2], 16), int(name[2:10], 16)
                if bucket not in latest or version > latest[bucket][0]:
                    latest[bucket] = (version, name)
        for _, name in latest.values():
            with open(os.path.join(folder, name), "rb") as f:
                raw = f.read()
            header_size = struct.unpack_from("<I", raw, 0)[0]
            key_bytes = raw[8 + 6]   # version u16, bucket u8, unk u8, size bytes, offset bytes, key bytes
            size_bytes, offset_bytes = raw[8 + 4], raw[8 + 5]
            pos = (8 + header_size + 15) & ~15
            entries_size = struct.unpack_from("<I", raw, pos)[0]
            pos += 8
            step = key_bytes + offset_bytes + size_bytes
            for i in range(pos, pos + entries_size - step + 1, step):
                key = raw[i:i + key_bytes]
                packed = int.from_bytes(raw[i + key_bytes:i + key_bytes + offset_bytes], "big")
                size = int.from_bytes(raw[i + key_bytes + offset_bytes:i + step], "little")
                if key not in self.index:
                    self.index[key] = (packed >> 30, packed & 0x3FFFFFFF, size)

    def read_ekey(self, ekey):
        place = self.index.get(ekey[:9])
        if not place:
            return None
        archive, offset, size = place
        with open(os.path.join(self.data_dir, "data", "data.%03d" % archive), "rb") as f:
            f.seek(offset)
            blob = f.read(size)
        return blte(blob[30:])

    def read_ckey(self, ckey):
        ekey = self.ckey_to_ekey.get(ckey)
        return ekey and self.read_ekey(ekey)

    def _load_encoding(self):
        raw = self.read_ekey(self.encoding_ekey)
        assert raw[:2] == b"EN", "not an encoding file"
        ckey_size, ekey_size = raw[3], raw[4]
        ce_page_kb = struct.unpack_from(">H", raw, 5)[0]
        ce_pages = struct.unpack_from(">I", raw, 9)[0]
        espec_size = struct.unpack_from(">I", raw, 18)[0]
        pos = 22 + espec_size + ce_pages * 32
        page_size = ce_page_kb * 1024
        for p in range(ce_pages):
            start = pos + p * page_size
            i = start
            while i < start + page_size - (6 + ckey_size):
                count = raw[i]
                if count == 0:
                    break
                ckey = raw[i + 6:i + 6 + ckey_size]
                ekey = raw[i + 6 + ckey_size:i + 6 + ckey_size + ekey_size]
                self.ckey_to_ekey[ckey] = ekey
                i += 6 + ckey_size + ekey_size * count

    def _load_root(self):
        raw = self.read_ckey(self.root_ckey)
        pos, version = 0, 0
        if raw[:4] == b"TSFM":
            header_size, version = struct.unpack_from("<II", raw, 4)
            if header_size < 0x18 or header_size > 0x100:  # the oldest MFST: no header size, no version
                header_size, version = 12, 0
            pos = header_size
        while pos + 12 <= len(raw):
            if version >= 2:
                count, locale, f1, f2 = struct.unpack_from("<IIII", raw, pos)
                f3 = raw[pos + 16]
                flags = f1 | f2 | (f3 << 17)
                pos += 17
            else:
                count, flags, locale = struct.unpack_from("<III", raw, pos)
                pos += 12
            deltas = struct.unpack_from("<%di" % count, raw, pos)
            pos += 4 * count
            fdid = -1
            ids = []
            for d in deltas:
                fdid = fdid + 1 + d
                ids.append(fdid)
            for k, fid in enumerate(ids):
                ckey = raw[pos + 16 * k:pos + 16 * k + 16]
                self.roots.setdefault(fid, []).append((locale, flags, ckey))
            pos += 16 * count
            if not flags & 0x10000000:  # names present
                for k, fid in enumerate(ids):
                    self.names[struct.unpack_from("<Q", raw, pos + 8 * k)[0]] = fid
                pos += 8 * count

    def fdid_for(self, path):
        return self.names.get(name_hash(path))

    def read_fdid(self, fdid):
        entries = self.roots.get(fdid) or []
        for locale, flags, ckey in entries:
            if locale & LOCALE_ENUS and not flags & 0x80:  # enUS, not the low-violence copy
                return self.read_ckey(ckey)
        return entries and self.read_ckey(entries[0][2])

    def table(self, name):
        fdid = self.fdid_for("DBFilesClient\\%s.db2" % name) or FDIDS.get(name)
        raw = fdid and self.read_fdid(fdid)
        if not raw:
            raise SystemExit("table %s not found (fdid %s)" % (name, fdid))
        return Wdc5(raw)


def blte(data):
    assert data[:4] == b"BLTE", "not BLTE"
    header_size = struct.unpack_from(">I", data, 4)[0]
    if header_size == 0:
        return _chunk(data[8:])
    count = int.from_bytes(data[9:12], "big")
    pos, out = 12, []
    sizes = []
    for _ in range(count):
        comp, decomp = struct.unpack_from(">II", data, pos)
        sizes.append((comp, decomp))
        pos += 24
    pos = header_size
    for comp, decomp in sizes:
        out.append(_chunk(data[pos:pos + comp], decomp))
        pos += comp
    return b"".join(out)


def _chunk(c, decomp=None):
    mode = c[:1]
    if mode == b"N":
        return c[1:]
    if mode == b"Z":
        return zlib.decompress(c[1:])
    if mode == b"F":
        return blte(c[1:])
    if mode == b"E":  # encrypted: no key here
        return b"\0" * (decomp or 0)  # (the chunk's size without its mode byte)
    raise ValueError("BLTE mode %r" % mode)


# ---------------------------------------------------------------- DB2 (WDC5)
class Wdc5:
    def __init__(self, raw):
        magic = raw[:4]
        assert magic in (b"WDC5", b"WDC4", b"WDC3"), "not WDC3-5: %r" % magic
        pos = 4
        if magic == b"WDC5":
            pos += 4 + 128  # version, schema string
        (self.record_count, self.field_count, self.record_size, string_size, _thash, _lhash, _min, _max, _locale,
         self.flags, self.id_index, total_fields, _bp_offset, _lookup, fsi_size, common_size, pallet_size,
         section_count) = struct.unpack_from("<IIIIIIIIIHHIIIIIII", raw, pos)
        pos += 4 * 16 + 4
        sections = []
        for _ in range(section_count):
            sections.append(struct.unpack_from("<QIIIIIIII", raw, pos))
            pos += 40
        pos += 4 * self.field_count  # field structures (size, offset); the storage info says it all
        self.fields = []
        for _ in range(fsi_size // 24):
            off_bits, size_bits, add_size, comp, v1, v2, v3 = struct.unpack_from("<HHIIIII", raw, pos)
            self.fields.append({"off": off_bits, "bits": size_bits, "add": add_size, "comp": comp,
                                "v1": v1, "v2": v2, "v3": v3})
            pos += 24
        pallet = raw[pos:pos + pallet_size]
        pos += pallet_size
        common = raw[pos:pos + common_size]
        # each field's slice of the pallet and common blocks, in field order
        p_at = c_at = 0
        for f in self.fields:
            if f["comp"] in (3, 4):
                f["pallet"] = pallet[p_at:p_at + f["add"]]
                p_at += f["add"]
            elif f["comp"] == 2:
                block = common[c_at:c_at + f["add"]]
                f["common"] = {struct.unpack_from("<I", block, i)[0]: struct.unpack_from("<I", block, i + 4)[0]
                               for i in range(0, len(block), 8)}
                c_at += f["add"]
        self.rows = {}
        self.encrypted_skipped = 0
        for tact_key, file_offset, count, s_size, _end, id_size, rel_size, offmap_count, copy_count in sections:
            if count == 0:
                continue
            if self.flags & 1:
                raise SystemExit("offset-map (sparse) tables are not supported")
            recs = raw[file_offset:file_offset + count * self.record_size]
            p = file_offset + count * self.record_size + s_size
            ids = struct.unpack_from("<%dI" % (id_size // 4), raw, p) if id_size else None
            p += id_size
            copies = [struct.unpack_from("<II", raw, p + 8 * i) for i in range(copy_count)]
            if tact_key and not any(recs):
                self.encrypted_skipped += count
                continue
            for r in range(count):
                rec = recs[r * self.record_size:(r + 1) * self.record_size]
                values = [self._field(rec, f) for f in self.fields]
                rid = ids[r] if ids else values[self.id_index][0]
                self.rows[rid] = values
            for new_id, old_id in copies:
                if old_id in self.rows:
                    self.rows[new_id] = self.rows[old_id]

    @staticmethod
    def _bits(rec, off, size):
        start = off // 8
        end = (off + size + 7) // 8
        return (int.from_bytes(rec[start:end], "little") >> (off % 8)) & ((1 << size) - 1)

    def _field(self, rec, f):
        comp = f["comp"]
        if comp == 0:  # stored as is: 32-bit values (an array is several)
            n = max(1, f["bits"] // 32)
            return [self._bits(rec, f["off"] + 32 * i, 32) for i in range(n)]
        if comp in (1, 5):
            v = self._bits(rec, f["off"], f["bits"])  # (v1 is the offset inside the packed block, v2 its size)
            if comp == 5 and v & (1 << (f["bits"] - 1)):
                v -= 1 << f["bits"]
            return [v]
        if comp == 2:  # filled in per row id by the caller (common data): default here
            return [("common", f)]
        if comp == 3:
            i = self._bits(rec, f["off"], f["bits"])
            return [struct.unpack_from("<I", f["pallet"], 4 * i)[0]]
        if comp == 4:
            i = self._bits(rec, f["off"], f["bits"])
            n = f["v3"]
            return list(struct.unpack_from("<%dI" % n, f["pallet"], 4 * i * n))
        raise ValueError("compression %d" % comp)

    def value(self, rid, field, element=0):
        v = self.rows[rid][field][element]
        if isinstance(v, tuple):  # common data: this row's value, or the default
            f = v[1]
            return f["common"].get(rid, f["v1"])
        return v


# ---------------------------------------------------------------- the game's object cache (objects the server described)
def object_cache(wow=WOW, product_dir="_forever_", locale="enUS"):
    """{object id: (type, display id, name)} from Cache/WDB/<locale>/gameobjectcache.wdb.
    Layout: 24-byte header ("BOGW", build, locale, ...), then records: id u32, size u32, data[size]; data starts
    type u32, display id u32, then the names (zero-terminated)."""
    path = os.path.join(wow, product_dir, "Cache", "WDB", locale, "gameobjectcache.wdb")
    out = {}
    if not os.path.exists(path):
        return out
    with open(path, "rb") as f:
        raw = f.read()
    if raw[:4] != b"BOGW":
        return out
    pos = 24
    while pos + 8 <= len(raw):
        oid, size = struct.unpack_from("<II", raw, pos)
        if oid == 0 or size < 8 or pos + 8 + size > len(raw):
            break
        data = raw[pos + 8:pos + 8 + size]
        kind, display = struct.unpack_from("<II", data, 0)
        name = data[8:].split(b"\0", 1)[0].decode("utf-8", "replace")
        out[oid] = (kind, display, name)
        pos += 8 + size
    return out


if __name__ == "__main__":
    product = sys.argv[1] if len(sys.argv) > 1 else "wowf"
    casc = Casc(product)
    print("build", casc.build_name, "| index keys", len(casc.index), "| encoding", len(casc.ckey_to_ekey),
          "| root files", len(casc.roots), "| named", len(casc.names))
    for name in sys.argv[2:] or ["GameObjectDisplayInfo", "GameObjects"]:
        t = casc.table(name)
        print("%s: %d rows, %d fields, encrypted rows skipped %d" % (name, len(t.rows), len(t.fields),
                                                                     t.encrypted_skipped))
        for rid in sorted(t.rows)[:3]:
            print("  ", rid, [t.value(rid, i) for i in range(len(t.fields))])
