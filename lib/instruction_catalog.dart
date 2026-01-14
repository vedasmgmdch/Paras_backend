// Centralized catalog of *logged/checkable* instructions (not informational "don'ts").
// Used by Progress screens to materialize expected instructions even when
// there are zero logs for a day.
//
// IMPORTANT: Keep these texts exactly as the instruction screens log them
// (almost all screens log English strings even when UI language is Marathi).

class InstructionCatalog {
  static Map<String, List<String>>? getExpected({required String? treatment, required String? subtype}) {
    final t = _canonicalTreatment(treatment);
    final s = _canonicalSubtype(t, subtype);
    if (t.isEmpty) return null;

    // Prefer exact (t, s) match, then (t, null).
    final keyExact = _key(t, s.isEmpty ? null : s);
    final keyBase = _key(t, null);
    final entry = _catalog[keyExact] ?? _catalog[keyBase];
    return entry;
  }

  static String _key(String treatment, String? subtype) => subtype == null || subtype.isEmpty ? treatment : '$treatment::$subtype';

  static String _canonicalTreatment(String? value) {
    final raw = (value ?? '').trim();
    if (raw.isEmpty) return '';
    final s = raw.toLowerCase();
    if (s == 'prosthesis') return 'Prosthesis Fitted';
    // Normalize common case variants
    if (s == 'braces') return 'Braces';
    if (s == 'implant') return 'Implant';
    if (s == 'tooth taken out') return 'Tooth Taken Out';
    if (s == 'root canal/filling' || s == 'root canal' || s == 'filling') return 'Root Canal/Filling';
    if (s == 'tooth fracture') return 'Tooth Fracture';
    return raw;
  }

  static String _canonicalSubtype(String treatment, String? value) {
    final raw = (value ?? '').trim();
    if (raw.isEmpty) return '';
    final s = raw.toLowerCase();

    if (treatment == 'Prosthesis Fitted') {
      if (s == 'fixed' || s == 'fixed denture' || s == 'fixed dentures') return 'Fixed Dentures';
      if (s == 'removable' || s == 'removable denture' || s == 'removable dentures') return 'Removable Dentures';
    }

    if (treatment == 'Implant') {
      if (s == 'first stage') return 'First Stage';
      if (s == 'second stage') return 'Second Stage';
    }

    if (treatment == 'Tooth Fracture') {
      if (s == 'filling') return 'Filling';
      if (s == 'teeth cleaning') return 'Teeth Cleaning';
      if (s == 'teeth whitening') return 'Teeth Whitening';
      if (s == 'gum surgery') return 'Gum Surgery';
      if (s == 'veneers/laminates' || s == 'veneers' || s == 'laminates') return 'Veneers/Laminates';
    }

    return raw;
  }

  // groups: 'general', 'specific'
  static const Map<String, Map<String, List<String>>> _catalog = {
    'Braces': {
      'general': [
        'Brush your teeth and rinse your mouth carefully after every meal.',
        'Floss daily (if possible).',
        'Attend all your orthodontic appointments.',
      ],
      'specific': [
        'If a bracket or wire becomes loose, contact your orthodontist as soon as possible.',
        'Use orthodontic wax to cover sharp or irritating wires.',
        'In case of mouth sores, rinse with warm salt water.',
        'Avoid chewing gum during orthodontic treatment.',
      ],
    },

    'Tooth Taken Out': {
      'general': [
        'Eat soft cold foods for at least 2 days.',
        'Avoid hot, spicy, hard foods.',
        'Consume tea, coffee at room temperature.',
        'Take medicines as prescribed by your doctor.',
      ],
      'specific': [
        'Bite firmly on the gauze placed in your mouth for at least 45-60 minutes and then gently remove the pack. (Today 8:00 AM)',
        'After going home, apply ice pack on the area in 15-20 minute intervals till nighttime. (Tomorrow 9:00 AM)',
        'After removing the pack, take one dosage of medicines prescribed.',
        'After 24 hours, gargle in that area with lukewarm water and salt at least 3-4 times a day.',
      ],
    },

    'Root Canal/Filling': {
      'general': [
        'If your lips or tongue feel numb avoid chewing on that side till numbness wears off.',
        'If multiple appointments are required, do not bite hard/sticky food from the operated site till the completion of treatment.',
        "A putty-like material is placed in your tooth after completion of your treatment which is temporary; To protect and help keep your temporary in place.",
        'Avoid chewing sticky foods, especially on side of filling.',
        'Avoid biting hard foods and hard substances, such as ice, fingernails and pencils.',
        'If possible, chew only on the opposite side of your mouth.',
        "It's important to continue to brush and floss regularly and normally.",
      ],
      'specific': [
        'DO NOT EAT anything for 1 hr post-treatment completion.',
        'If you are experiencing discomfort, apply an ice pack on the area in 10 minutes ON 5 minutes OFF intervals for up to an hour.',
        'DO NOT SMOKE for the 1st day after treatment.',
      ],
    },

    'Implant::First Stage': {
      'general': [
        'Eat soft cold foods for at least 2 days.',
        'Use warm salt water rinse as instructed.',
        'Eat your medicine as prescribed by your dentist.',
        'Drink plenty of fluids (without using a straw).',
        'Take medicines as prescribed by your doctor.',
      ],
      'specific': [
        'Apply an ice bag wrapped in a towel on the area for the first 24 hours in 15–20 min intervals. 15 min on and 5 min off.',
        'Do not rinse or spit for 24 hours after surgery.',
        'After the first day, use a warm salt water rinse following meals for the first week to flush out particles of food and debris that may lodge in the surgical area.\n(Mix ½ teaspoon of salt in a glass of lukewarm water.)',
        'After 24 hours, gargle in that area with lukewarm water and salt at least 3–4 times a day.',
      ],
    },

    'Implant::Second Stage': {
      'general': [
        'Eat soft cold foods for at least 2 days.',
        'Avoid hot, spicy, hard foods.',
        'Consume tea, coffee at room temperature.',
        'Take medicines as prescribed by your doctor.',
      ],
      'specific': [
        'Bite firmly on the gauze placed in your mouth for at least 45–60 minutes and then gently remove the pack.',
        'After going home, apply ice pack on the area in 15–20 minute intervals till nighttime.',
        'After removing the pack, take one dosage of medicines prescribed.',
        'After 24 hours, gargle in that area with lukewarm water and salt at least 3–4 times a day.',
      ],
    },

    'Prosthesis Fitted::Fixed Dentures': {
      'general': [
        'Whenever local anesthesia is used, avoid chewing on your teeth until the numbness has worn off.',
        'Proper brushing, flossing, and regular cleanings are necessary to maintain the restoration.',
        'Pay special attention to your gumline.',
        'Avoid very hot or hard foods.',
      ],
      'specific': [
        'If your bite feels high or uncomfortable, contact your dentist for an adjustment.',
        'If the restoration feels loose or comes off, keep it safe and contact your dentist. Do not try to glue it yourself.',
        'Clean carefully around the restoration and gumline; use floss/interdental aids as advised by your dentist.',
        'If you notice persistent pain, swelling, or bleeding, contact your dentist.',
      ],
    },

    'Prosthesis Fitted::Removable Dentures': {
      'general': [
        'Rinse your dentures after meals to remove food debris.',
        'Clean your dentures daily using a soft denture brush.',
        'Soak dentures in a denture cleanser overnight.',
        'Visit your dentist regularly to ensure proper fit.',
      ],
      'specific': [
        'Do not wear your dentures at night to allow gum rest.',
        'Avoid eating hard or sticky foods with new dentures.',
        'Report sore spots to your dentist immediately.',
        'Keep dentures in water when not wearing them.',
      ],
    },

    'Tooth Fracture::Filling': {
      'general': [
        'Eat soft cold foods for at least 2 days.',
        'Avoid hot, spicy, hard foods.',
        'Consume tea, coffee at room temperature.',
        'Take medicines as prescribed by your doctor.',
      ],
      'specific': [
        'Do not chew from the filled tooth for at least 24 hours.',
        'If sensitivity persists beyond 1 week, consult your dentist.',
        'Maintain good oral hygiene and brush gently around the filling.',
        'Avoid very hot or cold foods for 2 days.',
      ],
    },

    'Tooth Fracture::Teeth Cleaning': {
      'general': [
        'Eat soft cold foods for at least 2 days.',
        'Avoid hot, spicy, hard foods.',
        'Consume tea, coffee at room temperature.',
        'Take medicines as prescribed by your doctor.',
      ],
      'specific': [
        'Bite firmly on the gauze placed in your mouth for at least 45-60 minutes and then gently remove the pack.',
        'After going home, apply ice pack on the area in 15-20 minute intervals till nighttime.',
        'After removing the pack, take one dosage of medicines prescribed.',
        'After 24 hours, gargle in that area with lukewarm water and salt at least 3-4 times a day.',
      ],
    },

    'Tooth Fracture::Teeth Whitening': {
      'general': [
        'Eat soft cold foods for at least 2 days.',
        'Avoid hot, spicy, hard foods.',
        'Consume tea, coffee at room temperature.',
        'Take medicines as prescribed by your doctor.',
      ],
      'specific': [
        'Bite firmly on the gauze placed in your mouth for at least 45-60 minutes and then gently remove the pack.',
        'After going home, apply ice pack on the area in 15-20 minute intervals till nighttime.',
        'After removing the pack, take one dosage of medicines prescribed.',
        'After 24 hours, gargle in that area with lukewarm water and salt at least 3-4 times a day.',
      ],
    },

    'Tooth Fracture::Gum Surgery': {
      'general': [
        'Eat soft cold foods for at least 2 days.',
        'Avoid hot, spicy, hard foods.',
        'Consume tea, coffee at room temperature.',
        'Take medicines as prescribed by your doctor.',
      ],
      'specific': [
        'Bite firmly on the gauze placed in your mouth for at least 45-60 minutes and then gently remove the pack.',
        'After going home, apply ice pack on the area in 15-20 minute intervals till nighttime.',
        'After removing the pack, take one dosage of medicines prescribed.',
        'After 24 hours, gargle in that area with lukewarm water and salt at least 3-4 times a day.',
      ],
    },

    'Tooth Fracture::Veneers/Laminates': {
      'general': [
        'Eat soft cold foods for at least 2 days.',
        'Avoid hot, spicy, hard foods.',
        'Consume tea, coffee at room temperature.',
        'Take medicines as prescribed by your doctor.',
      ],
      'specific': [
        'Bite firmly on the gauze placed in your mouth for at least 45-60 minutes and then gently remove the pack.',
        'After going home, apply ice pack on the area in 15-20 minute intervals till nighttime.',
        'After removing the pack, take one dosage of medicines prescribed.',
        'After 24 hours, gargle in that area with lukewarm water and salt at least 3-4 times a day.',
      ],
    },
  };
}
