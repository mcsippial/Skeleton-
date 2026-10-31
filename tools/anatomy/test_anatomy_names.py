"""Run: python3 tools/anatomy/test_anatomy_names.py"""
import json, pathlib, sys, unittest
sys.path.insert(0, str(pathlib.Path(__file__).parent))
from anatomy_names import classify, required_ids, side_of

ROOT = pathlib.Path(__file__).resolve().parents[2]

class Names(unittest.TestCase):
    def check(self, name, id, layer, x=None):
        r = classify(name, x)
        self.assertIsNotNone(r, name)
        self.assertEqual((r["id"], r["layer"]), (id, layer), name)

    def test_common_naming_styles(self):
        self.check("Gluteus_maximus.L", "glute_l", "muscles")
        self.check("Sciatic Nerve (R)", "sciatic_r", "nerves")
        self.check("Right Femur", "femur_r", "bones")
        self.check("M. psoas major sin", "psoas_l", "muscles")
        self.check("GastrocnemiusMedialHead_R", "calf_r", "muscles")
        self.check("Calcaneal tendon left", "achilles_l", "tendons")
        self.check("Iliotibial_tract.R", "itb_r", "tendons")
        self.check("Biceps femoris long head L", "ham_l", "muscles")
        self.check("Tibialis anterior.R", "tib_r", "muscles")
        self.check("Tibia_R", "tibia_r", "bones")
        self.check("Patella.L", "patella_l", "bones")
        self.check("Patellar ligament.L", "pattend_l", "tendons")
        self.check("Spinal cord", "cord", "nerves")
        self.check("Mandible", "mandible", "bones")
        self.check("Ilioinguinal nerve.R", "groinnerve_r", "nerves")

    def test_side_from_position_when_unnamed(self):
        self.check("Sciatic nerve", "sciatic_l", "nerves", x=0.1)
        self.check("Sciatic nerve", "sciatic_r", "nerves", x=-0.1)

    def test_unknown_structures_get_stable_ids(self):
        r = classify("Vastus intermedius.L")
        self.assertEqual(r["id"], "quad_l")
        r = classify("Flexor digitorum longus muscle.R")
        self.assertEqual((r["layer"], r["id"]), ("muscles", "anat.flexor_digitorum_longus_r"))
        r = classify("Radial nerve left")
        self.assertEqual((r["layer"], r["id"]), ("nerves", "anat.radial_l"))
        r = classify("L3 vertebra")
        self.assertEqual(r["layer"], "bones")

    def test_skin_organs_and_vessels_are_left_out(self):
        for n in ["Skin", "Femoral artery.L", "Great saphenous vein", "Heart", "Liver", "Body_surface"]:
            self.assertIsNone(classify(n), n)

    def test_side_markers(self):
        self.assertEqual(side_of("Deltoid_L"), "l")
        self.assertEqual(side_of("deltoid.R"), "r")
        self.assertEqual(side_of("Left deltoid"), "l")
        self.assertIsNone(side_of("Sternum"))

    def test_every_pathway_structure_has_a_rule(self):
        stems = {s.rsplit("_", 1)[0] for s in required_ids(json.load(open(ROOT / "data/pain-pathways.json")))}
        from anatomy_names import KNOWN
        self.assertTrue(stems <= {k[1] for k in KNOWN}, stems - {k[1] for k in KNOWN})

if __name__ == "__main__":
    unittest.main(verbosity=1)
