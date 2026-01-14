from __future__ import annotations

import re

from typing import Dict, List, Optional, Tuple


def _canonical_treatment(value: Optional[str]) -> str:
    raw = (value or "").strip()
    if not raw:
        return ""
    s = raw.lower()
    # Back-compat aliases (mirrors Flutter AppState._canonicalTreatment)
    if s == "prosthesis":
        return "Prosthesis Fitted"
    # Case-insensitive normalization for known treatments in this catalog
    known = {
        "braces": "Braces",
        "tooth taken out": "Tooth Taken Out",
        "root canal/filling": "Root Canal/Filling",
        "implant": "Implant",
        "tooth fracture": "Tooth Fracture",
        "prosthesis fitted": "Prosthesis Fitted",
    }
    return known.get(s, raw)


def _canonical_subtype(treatment: Optional[str], value: Optional[str]) -> str:
    t = _canonical_treatment(treatment)
    raw = (value or "").strip()
    if not raw:
        return ""
    s = raw.lower()

    # Mirrors Flutter AppState._canonicalSubtype for Prosthesis
    if t == "Prosthesis Fitted":
        if s in {"fixed", "fixed denture", "fixed dentures"}:
            return "Fixed Dentures"
        if s in {"removable", "removable denture", "removable dentures"}:
            return "Removable Dentures"

    if t == "Implant":
        if s in {"first stage"}:
            return "First Stage"
        if s in {"second stage"}:
            return "Second Stage"

    if t == "Tooth Fracture":
        # Common variants
        if s in {"teeth cleaning", "cleaning"}:
            return "Teeth Cleaning"
        if s in {"teeth whitening", "whitening"}:
            return "Teeth Whitening"
        if s in {"gum surgery"}:
            return "Gum Surgery"
        if s in {"veneers", "laminates", "veneers/laminates", "veneers laminates"}:
            return "Veneers/Laminates"

    return raw


def canonical_group(value: Optional[str]) -> str:
    return (value or "").strip().lower()


def canonical_instruction_text(value: Optional[str]) -> str:
    # Mirrors Flutter AppState._canonicalInstructionText
    s = (value or "").strip()
    # When extracting from source-like content, we may have literal escape sequences.
    # The app sees real newlines at runtime, which then get whitespace-collapsed.
    s = s.replace("\\n", " ")
    s = re.sub(r"\s+", " ", s)
    s = s.replace("\u2013", "-")  # –
    s = s.replace("\u2014", "-")  # —
    return s


def stable_instruction_index(group: str, instruction: str) -> int:
    """Matches Flutter AppState.stableInstructionIndex (FNV-1a 32-bit, positive int)."""
    s = (group.strip().lower() + "|" + instruction.strip().lower())
    h = 0x811C9DC5
    prime = 0x01000193
    for b in s.encode("utf-8"):
        h ^= b & 0xFF
        h = (h * prime) & 0xFFFFFFFF
    return h & 0x7FFFFFFF


# Canonical instruction catalog extracted from the Flutter instruction screens.
# This catalog includes ONLY checkable/logged instructions:
#   - group='general' and group='specific'
# and uses the same canonicalization + hashing rules as the app.
_CATALOG: Dict[Tuple[str, Optional[str]], Dict[str, List[str]]] = {
    ("Braces", None): {
        "general": [
            "Brush your teeth and rinse your mouth carefully after every meal.",
            "Floss daily (if possible).",
            "Attend all your orthodontic appointments.",
        ],
        "specific": [
            "If a bracket or wire becomes loose, contact your orthodontist as soon as possible.",
            "Use orthodontic wax to cover sharp or irritating wires.",
            "In case of mouth sores, rinse with warm salt water.",
            "Avoid chewing gum during orthodontic treatment.",
        ],
    },
    ("Tooth Taken Out", None): {
        "general": [
            "Eat soft cold foods for at least 2 days.",
            "Avoid hot, spicy, hard foods.",
            "Consume tea, coffee at room temperature.",
            "Take medicines as prescribed by your doctor.",
        ],
        "specific": [
            "Bite firmly on the gauze placed in your mouth for at least 45-60 minutes and then gently remove the pack. (Today 8:00 AM)",
            "After going home, apply ice pack on the area in 15-20 minute intervals till nighttime. (Tomorrow 9:00 AM)",
            "After removing the pack, take one dosage of medicines prescribed.",
            "After 24 hours, gargle in that area with lukewarm water and salt at least 3-4 times a day.",
        ],
    },
    ("Root Canal/Filling", None): {
        "general": [
            "If your lips or tongue feel numb avoid chewing on that side till numbness wears off.",
            "If multiple appointments are required, do not bite hard/sticky food from the operated site till the completion of treatment.",
            "A putty-like material is placed in your tooth after completion of your treatment which is temporary; To protect and help keep your temporary in place.",
            "Avoid chewing sticky foods, especially on side of filling.",
            "Avoid biting hard foods and hard substances, such as ice, fingernails and pencils.",
            "If possible, chew only on the opposite side of your mouth.",
            "It's important to continue to brush and floss regularly and normally.",
        ],
        "specific": [
            "DO NOT EAT anything for 1 hr post-treatment completion.",
            "If you are experiencing discomfort, apply an ice pack on the area in 10 minutes ON 5 minutes OFF intervals for up to an hour.",
            "DO NOT SMOKE for the 1st day after treatment.",
        ],
    },
    ("Implant", "First Stage"): {
        "general": [
            "Eat soft cold foods for at least 2 days.",
            "Use warm salt water rinse as instructed.",
            "Eat your medicine as prescribed by your dentist.",
            "Drink plenty of fluids (without using a straw).",
            "Take medicines as prescribed by your doctor.",
        ],
        "specific": [
            "Apply an ice bag wrapped in a towel on the area for the first 24 hours in 15\u201320 min intervals. 15 min on and 5 min off.",
            "Do not rinse or spit for 24 hours after surgery.",
            "After the first day, use a warm salt water rinse following meals for the first week to flush out particles of food and debris that may lodge in the surgical area.\\n(Mix \u00bd teaspoon of salt in a glass of lukewarm water.)",
            "After 24 hours, gargle in that area with lukewarm water and salt at least 3\u20134 times a day.",
        ],
    },
    ("Implant", "Second Stage"): {
        "general": [
            "Eat soft cold foods for at least 2 days.",
            "Avoid hot, spicy, hard foods.",
            "Consume tea, coffee at room temperature.",
            "Take medicines as prescribed by your doctor.",
        ],
        "specific": [
            "Bite firmly on the gauze placed in your mouth for at least 45\u201360 minutes and then gently remove the pack.",
            "After going home, apply ice pack on the area in 15\u201320 minute intervals till nighttime.",
            "After removing the pack, take one dosage of medicines prescribed.",
            "After 24 hours, gargle in that area with lukewarm water and salt at least 3\u20134 times a day.",
        ],
    },
    ("Prosthesis Fitted", "Fixed Dentures"): {
        "general": [
            "Whenever local anesthesia is used, avoid chewing on your teeth until the numbness has worn off.",
            "Proper brushing, flossing, and regular cleanings are necessary to maintain the restoration.",
            "Pay special attention to your gumline.",
            "Avoid very hot or hard foods.",
        ],
        "specific": [
            "If your bite feels high or uncomfortable, contact your dentist for an adjustment.",
            "If the restoration feels loose or comes off, keep it safe and contact your dentist. Do not try to glue it yourself.",
            "Clean carefully around the restoration and gumline; use floss/interdental aids as advised by your dentist.",
            "If you notice persistent pain, swelling, or bleeding, contact your dentist.",
        ],
    },
    ("Prosthesis Fitted", "Removable Dentures"): {
        "general": [
            "Rinse your dentures after meals to remove food debris.",
            "Clean your dentures daily using a soft denture brush.",
            "Soak dentures in a denture cleanser overnight.",
            "Visit your dentist regularly to ensure proper fit.",
        ],
        "specific": [
            "Do not wear your dentures at night to allow gum rest.",
            "Avoid eating hard or sticky foods with new dentures.",
            "Report sore spots to your dentist immediately.",
            "Keep dentures in water when not wearing them.",
        ],
    },
    ("Tooth Fracture", "Filling"): {
        "general": [
            "Eat soft cold foods for at least 2 days.",
            "Avoid hot, spicy, hard foods.",
            "Consume tea, coffee at room temperature.",
            "Take medicines as prescribed by your doctor.",
        ],
        "specific": [
            "Do not chew from the filled tooth for at least 24 hours.",
            "If sensitivity persists beyond 1 week, consult your dentist.",
            "Maintain good oral hygiene and brush gently around the filling.",
            "Avoid very hot or cold foods for 2 days.",
        ],
    },
    ("Tooth Fracture", "Teeth Cleaning"): {
        "general": [
            "Eat soft cold foods for at least 2 days.",
            "Avoid hot, spicy, hard foods.",
            "Consume tea, coffee at room temperature.",
            "Take medicines as prescribed by your doctor.",
        ],
        "specific": [
            "Bite firmly on the gauze placed in your mouth for at least 45-60 minutes and then gently remove the pack.",
            "After going home, apply ice pack on the area in 15-20 minute intervals till nighttime.",
            "After removing the pack, take one dosage of medicines prescribed.",
            "After 24 hours, gargle in that area with lukewarm water and salt at least 3-4 times a day.",
        ],
    },
    ("Tooth Fracture", "Teeth Whitening"): {
        "general": [
            "Eat soft cold foods for at least 2 days.",
            "Avoid hot, spicy, hard foods.",
            "Consume tea, coffee at room temperature.",
            "Take medicines as prescribed by your doctor.",
        ],
        "specific": [
            "Bite firmly on the gauze placed in your mouth for at least 45-60 minutes and then gently remove the pack.",
            "After going home, apply ice pack on the area in 15-20 minute intervals till nighttime.",
            "After removing the pack, take one dosage of medicines prescribed.",
            "After 24 hours, gargle in that area with lukewarm water and salt at least 3-4 times a day.",
        ],
    },
    ("Tooth Fracture", "Gum Surgery"): {
        "general": [
            "Eat soft cold foods for at least 2 days.",
            "Avoid hot, spicy, hard foods.",
            "Consume tea, coffee at room temperature.",
            "Take medicines as prescribed by your doctor.",
        ],
        "specific": [
            "Bite firmly on the gauze placed in your mouth for at least 45-60 minutes and then gently remove the pack.",
            "After going home, apply ice pack on the area in 15-20 minute intervals till nighttime.",
            "After removing the pack, take one dosage of medicines prescribed.",
            "After 24 hours, gargle in that area with lukewarm water and salt at least 3-4 times a day.",
        ],
    },
    ("Tooth Fracture", "Veneers/Laminates"): {
        "general": [
            "Eat soft cold foods for at least 2 days.",
            "Avoid hot, spicy, hard foods.",
            "Consume tea, coffee at room temperature.",
            "Take medicines as prescribed by your doctor.",
        ],
        "specific": [
            "Bite firmly on the gauze placed in your mouth for at least 45-60 minutes and then gently remove the pack.",
            "After going home, apply ice pack on the area in 15-20 minute intervals till nighttime.",
            "After removing the pack, take one dosage of medicines prescribed.",
            "After 24 hours, gargle in that area with lukewarm water and salt at least 3-4 times a day.",
        ],
    },
}


def get_expected_instructions(treatment: Optional[str], subtype: Optional[str]) -> Optional[Dict[str, List[str]]]:
    """Returns a dict of groups -> instruction texts, or None if unknown."""
    t = _canonical_treatment(treatment)
    s = _canonical_subtype(t, subtype)
    key = (t, s if s else None)
    return _CATALOG.get(key)


def expected_instruction_identities(
    *,
    treatment: Optional[str],
    subtype: Optional[str],
) -> Optional[Dict[tuple, Dict[str, object]]]:
    """Returns expected identities keyed by (group, instruction_index).

    Each value contains: group, instruction_index, instruction_text, treatment, subtype.
    """
    instrs = get_expected_instructions(treatment, subtype)
    if not instrs:
        return None

    t = _canonical_treatment(treatment) or (treatment or "")
    s = _canonical_subtype(t, subtype)
    subtype_out: Optional[str] = s if s else None

    out: Dict[tuple, Dict[str, object]] = {}
    for group, items in instrs.items():
        g = canonical_group(group)
        for raw_text in items:
            text = canonical_instruction_text(raw_text)
            idx = stable_instruction_index(g, text)
            out[(g, idx)] = {
                "group": g,
                "instruction_index": idx,
                "instruction_text": text,
                "treatment": t,
                "subtype": subtype_out,
            }
    return out
