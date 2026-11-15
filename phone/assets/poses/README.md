# Provided character artwork

The canonical Pleos display roster is data/characters.json, matching the twelve folders in Desktop/assets. All idle/move/sleep/happy/sad/surprised PNGs and joy/sadness/surprise GIFs are copied unchanged. Logo assets are not imported or modified.

Pleos selects the provided idle/move/sleep/surprised PNG directly. A provided fishing sequence does not exist, so fishing shows the original idle image. Generated action sheets and actions.png from earlier work are excluded from app and preview APK packaging and are never selected by PetArt. Existing generated files are retained only as deferred source work, not shipped artwork.

Game rules, saved species IDs, and data/species.json remain unchanged. Display-only IDs are not aliases for the six unrelated legacy game IDs. New artwork without agreed gameplay metadata uses its supplied English name; no attribute/tier/acquisition rule is invented.
