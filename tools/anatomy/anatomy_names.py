"""Turns anatomy-model object names into Skeleton structure IDs and layers.

Pure Python (no Blender), so it can be unit-tested anywhere. Used by prepare_anatomy.py.

A purchased model names its parts things like "Gluteus_maximus.L", "Sciatic Nerve (R)",
"Right Femur" or "M. psoas major sin". `classify()` returns the layer, a stable structure ID
and a display name. Structures that the pathway library lights up (data/pain-pathways.json
`linked_structures`, e.g. `sciatic_l`, `psoas_r`) get exactly those IDs; everything else gets
an ID derived from its name (`anat.vastus_lateralis_l`).
"""
import re

LAYERS = ("skin", "muscles", "tendons", "nerves", "bones")

# (pattern, structure stem, layer) — first match wins, so specific names go first.
KNOWN = [
    # Nerves
    (r"sciatic", "sciatic", "nerves"),
    (r"femoral\s*nerve|\bn\.?\s*femoralis", "femoral", "nerves"),
    (r"ilio-?inguinal|genito-?femoral|iliohypogastric", "groinnerve", "nerves"),
    (r"brachial\s*plexus|plexus\s*brachialis", "brachial", "nerves"),
    (r"trigeminal|mandibular\s*nerve|\bv3\b", "trigeminal", "nerves"),
    (r"(greater|lesser)?\s*occipital\s*nerve", "occipital", "nerves"),
    (r"spinal\s*cord|medulla\s*spinalis", "cord", "nerves"),
    # Tendons, ligaments, fascia
    (r"achilles|calcaneal\s*tendon|tendo\s*calcaneus", "achilles", "tendons"),
    (r"patellar\s*(ligament|tendon)|ligamentum\s*patellae", "pattend", "tendons"),
    (r"ilio-?tibial|\bit\s*band\b|tractus\s*iliotibialis", "itb", "tendons"),
    (r"inguinal\s*ligament", "inguinal", "tendons"),
    (r"plantar\s*(aponeurosis|fascia)", "plantar", "tendons"),
    (r"temporomandibular\s*(joint\s*)?ligament|lateral\s*ligament\s*of\s*(the\s*)?t", "tmjlig", "tendons"),
    (r"sacro-?iliac", "si", "tendons"),
    # Muscles
    (r"pectoralis\s*major", "pec", "muscles"),
    (r"deltoid", "delt", "muscles"),
    (r"biceps\s*brachii", "bicep", "muscles"),
    (r"trapezius", "trap", "muscles"),
    (r"latissimus", "lat", "muscles"),
    (r"erector\s*spinae|iliocostalis|longissimus|spinalis(?!\s*cord)", "erector", "muscles"),
    (r"quadratus\s*lumborum", "ql", "muscles"),
    (r"gluteus\s*maximus", "glute", "muscles"),
    (r"psoas|iliopsoas", "psoas", "muscles"),
    (r"rectus\s*femoris|vastus|quadriceps", "quad", "muscles"),
    (r"biceps\s*femoris|semitendinosus|semimembranosus|hamstring", "ham", "muscles"),
    (r"adductor|gracilis|pectineus", "add", "muscles"),
    (r"gastrocnemius|soleus", "calf", "muscles"),
    (r"tibialis\s*anterior", "tib", "muscles"),
    (r"masseter", "masseter", "muscles"),
    (r"temporalis", "temporalis", "muscles"),
    (r"sternocleidomastoid|sternomastoid", "scm", "muscles"),
    (r"splenius|semispinalis\s*capitis", "neckext", "muscles"),
    # Bones and joints
    (r"temporomandibular\s*joint|\btmj\b", "tmj", "bones"),
    (r"mandible|mandibula", "mandible", "bones"),
    (r"clavicle|clavicula", "clav", "bones"),
    (r"scapula", "scap", "bones"),
    (r"humerus", "hum", "bones"),
    (r"radius|ulna", "rad", "bones"),
    (r"femur", "femur", "bones"),
    (r"patella(?!r)", "patella", "bones"),
    (r"tibia(?!lis)|fibula", "tibia", "bones"),
    (r"sacrum", "sacrum", "bones"),
    (r"skull|cranium", "skull", "bones"),
    (r"hip\s*joint|acetabul", "hip", "bones"),
]

# Bilateral stems get a side suffix; these are midline.
MIDLINE = {"cord", "mandible", "sacrum", "skull"}

SKIP = r"\b(skin|body\s*surface|integument|artery|arteries|vein|venous|vessel|aorta|heart|lung|liver|kidney|spleen|stomach|intestin|colon|bladder|brain|eye|organ|lymph|fat|teeth|tooth|tongue|cartilage\s*of\s*nose)\b"

LAYER_HINTS = [
    ("nerves", r"nerve|plexus|ganglion|\bn\.\s|nervus|cord"),
    ("tendons", r"tendon|ligament|fascia|aponeurosis|retinaculum|\blig\.|menisc|bursa|capsule"),
    ("bones", r"bone|vertebra|\bc\d\b|\bt\d{1,2}\b|\bl\d\b|rib|costa|sternum|carpal|tarsal|phalan|metacarp|metatars|calcane|talus|navicular|cuboid|cuneiform|ilium|ischium|pubis|coccyx|os\s|hyoid|joint"),
    ("muscles", r"muscle|\bm\.\s|musculus|-us\b|us$|is$|ii$|head\s*of"),
]


def _norm(name: str) -> str:
    n = re.sub(r"([a-z])([A-Z])", r"\1 \2", name)          # camelCase → words
    n = re.sub(r"[_\-.()\[\]:]+", " ", n).lower()
    return re.sub(r"\s+", " ", n).strip()


def side_of(name: str, centroid_x: float | None = None) -> str | None:
    """'l', 'r' or None. +X is the body's left in Skeleton's convention."""
    raw = name
    n = " " + _norm(name) + " "
    if re.search(r"[ _.\-](l|lt|left|sin|sinister|links)[ _.\-]|^left|left$", n) or re.search(r"[._\-]L$|\(L\)|_L_", raw):
        return "l"
    if re.search(r"[ _.\-](r|rt|right|dex|dexter|rechts)[ _.\-]|^right|right$", n) or re.search(r"[._\-]R$|\(R\)|_R_", raw):
        return "r"
    if centroid_x is not None and abs(centroid_x) > 0.02:
        return "l" if centroid_x > 0 else "r"
    return None


def _slug(text: str) -> str:
    s = re.sub(r"\b(left|right|l|r|lt|rt|sin|dex|sinister|dexter|muscle|musculus|m|n|nerve|nervus|of|the)\b", " ", _norm(text))
    s = re.sub(r"[^a-z0-9]+", "_", s).strip("_")
    return s or "part"


def _display(text: str, side: str | None) -> str:
    base = re.sub(r"\b(left|right|l|r|lt|rt|sin|dex)\b", " ", _norm(text))
    base = re.sub(r"\s+", " ", base).strip().capitalize()
    return f"{'Left' if side == 'l' else 'Right'} {base[0].lower() + base[1:]}" if side and base else base


def classify(name: str, centroid_x: float | None = None) -> dict | None:
    """Layer, structure ID and display name for one object; None to leave it out."""
    n = _norm(name)
    if not n or re.search(SKIP, n):
        return None
    side = side_of(name, centroid_x)
    for pattern, stem, layer in KNOWN:
        if re.search(pattern, n):
            if stem in MIDLINE:
                return {"id": stem, "layer": layer, "name": _display(name, None), "known": True}
            s = side or ("l" if (centroid_x or 0) >= 0 else "r")
            return {"id": f"{stem}_{s}", "layer": layer, "name": _display(name, s), "known": True}
    layer = next((l for l, pat in LAYER_HINTS if re.search(pat, n)), None)
    if layer is None:
        return None
    sid = _slug(name) + (f"_{side}" if side else "")
    return {"id": f"anat.{sid}", "layer": layer, "name": _display(name, side), "known": False}


def required_ids(pathways: dict) -> set:
    """Structure IDs the pathway library lights up, both sides."""
    out = set()
    for p in pathways["pathways"]:
        for s in p["linked_structures"]:
            out |= {s.replace("{s}", "l"), s.replace("{s}", "r")} if "{s}" in s else {s}
    return out
