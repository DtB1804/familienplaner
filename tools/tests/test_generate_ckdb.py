"""Tests für tools/generate_ckdb.py (Aufruf: python3 -m unittest discover tools/tests)."""
import os
import re
import sys
import unittest

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
sys.path.insert(0, os.path.join(ROOT, "tools"))
import generate_ckdb as g  # noqa: E402

MODEL = os.path.join(ROOT, "Sources", "Persistence", "Familienplaner.xcdatamodeld")
SCHEMA = os.path.join(ROOT, "CloudKit", "schema-development.ckdb")


def fields_by_type(statements):
    """{'CD_CDEvent': {'CD_title': 'STRING', ...}} aus RECORD-TYPE-Blöcken."""
    out = {}
    for stmt in statements:
        m = re.search(r"RECORD\s+TYPE\s+(\w+)\s*\((.*)\)", stmt, flags=re.S)
        if not m:
            continue
        fields = {}
        for line in m.group(2).split(","):
            parts = line.split()
            if len(parts) >= 2 and parts[0].startswith("CD_"):
                fields[parts[0]] = parts[1]
        out[m.group(1)] = fields
    return out


class GenerateCkdbTests(unittest.TestCase):

    def setUp(self):
        self.model = g.resolve_model(MODEL)
        self.generated = fields_by_type(g.record_types(self.model))

    def test_resolves_current_model_version(self):
        self.assertTrue(self.model.endswith(os.path.join("Familienplaner 2.xcdatamodel", "contents")))

    def test_only_cloud_entities(self):
        self.assertIn("CD_CDEvent", self.generated)
        self.assertIn("CD_CDHousehold", self.generated)
        for local in ("CD_CDCalendarSource", "CD_CDLocalEventMirror", "CD_CDDeviceRegistration"):
            self.assertNotIn(local, self.generated, "lokale Entität darf nicht nach CloudKit (Regel 3)")

    def test_type_mapping(self):
        event = self.generated["CD_CDEvent"]
        self.assertEqual(event["CD_title"], "STRING")
        self.assertEqual(event["CD_title_ckAsset"], "ASSET")
        self.assertEqual(event["CD_startAt"], "TIMESTAMP")
        self.assertEqual(event["CD_isAllDay"], "INT64")
        self.assertEqual(event["CD_household"], "STRING")      # to-one → recordName
        self.assertNotIn("CD_participations", event)           # to-many → kein Feld

    def test_new_field_of_version_2_present(self):
        self.assertEqual(self.generated["CD_CDHousehold"]["CD_childrenSeeAdultTitles"], "INT64")

    def test_deployed_schema_contains_every_model_field(self):
        """Regel 13: Jedes Feld des aktuellen Modells muss im Development-Schema stehen."""
        with open(SCHEMA, encoding="utf-8") as f:
            text = f.read()
        deployed = fields_by_type(re.split(r";", text))
        for record, fields in self.generated.items():
            self.assertIn(record, deployed, f"Record-Typ {record} fehlt im Schema")
            for name, typ in fields.items():
                self.assertIn(name, deployed[record], f"{record}.{name} fehlt im Schema")
                self.assertEqual(deployed[record][name], typ, f"{record}.{name} hat anderen Typ")

    def test_baseline_keeps_non_cd_types(self):
        base = 'DEFINE SCHEMA\n RECORD TYPE Users ("___recordID" REFERENCE, roles LIST<INT64>);\n' \
               ' RECORD TYPE CD_Old (CD_x STRING);'
        kept = g.baseline_statements(base)
        self.assertEqual(len(kept), 1)
        self.assertIn("Users", kept[0])


if __name__ == "__main__":
    unittest.main()
