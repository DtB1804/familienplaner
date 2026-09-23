#!/usr/bin/env python3
"""Erzeugt das CloudKit-Schema (.ckdb) aus dem Core-Data-Modell.

Ersetzt `initializeCloudKitSchema`, das ein Gerät mit angemeldeter Apple-ID braucht.
Abbildung nach Apple, "Reading CloudKit Records for Core Data":
- Record-Typ  CD_<Entität>, Feld CD_entityName (STRING)
- Attribut    CD_<name>; String/Binary zusätzlich CD_<name>_ckAsset (ASSET)
- To-one      CD_<beziehung> als STRING (recordName des Ziels); to-many ohne Feld
Nur Entitäten der Konfiguration "Cloud".

Aufruf: generate_ckdb.py <Modell.xcdatamodeld|contents> <baseline.ckdb|-> > schema.ckdb
Die Baseline (Export aus Development) wird übernommen, vorhandene CD_-Typen werden
durch die neu erzeugten ersetzt, alles andere (z. B. Users) bleibt unverändert.
"""
import re
import sys
import xml.etree.ElementTree as ET

TYPE_MAP = {
    "String": "STRING", "UUID": "STRING", "URI": "STRING",
    "Date": "TIMESTAMP",
    "Boolean": "INT64", "Integer 16": "INT64", "Integer 32": "INT64", "Integer 64": "INT64",
    "Double": "DOUBLE", "Float": "DOUBLE", "Decimal": "DOUBLE",
    "Binary": "BYTES", "Transformable": "BYTES",
}
ASSET_TYPES = {"String", "Binary", "Transformable"}


def record_types(model_path):
    root = ET.parse(model_path).getroot()
    cloud = {m.get("name") for c in root.findall("configuration") if c.get("name") == "Cloud"
             for m in c.findall("memberEntity")}
    out = []
    for ent in root.findall("entity"):
        name = ent.get("name")
        if name not in cloud:
            continue
        if ent.get("parentEntity"):
            sys.exit(f"Vererbung ({name}) wird nicht unterstützt")
        fields = [("CD_entityName", "STRING")]
        for a in ent.findall("attribute"):
            t = a.get("attributeType")
            if t not in TYPE_MAP:
                sys.exit(f"Unbekannter Attributtyp {t} in {name}.{a.get('name')}")
            fields.append((f"CD_{a.get('name')}", TYPE_MAP[t]))
            if t in ASSET_TYPES:
                fields.append((f"CD_{a.get('name')}_ckAsset", "ASSET"))
        for r in ent.findall("relationship"):
            if r.get("toMany") == "YES":
                continue
            fields.append((f"CD_{r.get('name')}", "STRING"))
        fields.sort()
        body = ",\n".join(f"        {n} {t}" for n, t in fields)
        grants = ('        GRANT WRITE TO "_creator",\n'
                  '        GRANT CREATE TO "_icloud",\n'
                  '        GRANT READ TO "_world"')
        out.append(f"    RECORD TYPE CD_{name} (\n"
                   f"        \"___recordID\" REFERENCE QUERYABLE,\n{body},\n{grants}\n    )")
    return out


def baseline_statements(text):
    text = re.sub(r"/\*.*?\*/", "", text, flags=re.S)
    text = re.sub(r"(//|--)[^\n]*", "", text)
    text = re.sub(r"^\s*DEFINE\s+SCHEMA", "", text.strip(), flags=re.I)
    keep = []
    for stmt in text.split(";"):
        s = stmt.strip()
        if not s:
            continue
        if re.match(r"RECORD\s+TYPE\s+\"?CD_", s, flags=re.I):
            continue
        keep.append("    " + s)
    return keep


def resolve_model(path):
    """Akzeptiert die contents-Datei oder das .xcdatamodeld (dann aktuelle Version)."""
    import os, plistlib
    if path.endswith(".xcdatamodeld"):
        with open(os.path.join(path, ".xccurrentversion"), "rb") as f:
            current = plistlib.load(f)["_XCCurrentVersionName"]
        return os.path.join(path, current, "contents")
    return path


def main():
    model, baseline = resolve_model(sys.argv[1]), sys.argv[2]
    stmts = []
    if baseline != "-":
        stmts += baseline_statements(open(baseline, encoding="utf-8").read())
    stmts += record_types(model)
    print("DEFINE SCHEMA\n")
    print(";\n\n".join(stmts) + ";")


if __name__ == "__main__":
    main()
