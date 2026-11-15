# ALLO Unity phone UI

The baseline is the 2D village composition of Ninja Voltage. Palworld informs ONLY the wilderness survival theme and material palette, not a 3D camera or 3D camp. The user explicitly corrected that distinction on 2026-11-12.

Home/camp is a full-screen 2D illustrated woodland base with clean anime-game outlines and restrained cel shading. Three small transparent sprites show a timber workbench/canvas shelter, outdoor cauldron/prep table, and straw dummy/target training area. Use muted forest green, rough cedar, khaki canvas, stone and earth. Avoid ornate cottages, excess decorative ivy, glossy concept-art rendering and painterly haze.

A persistent full-canvas UGUI layer contains the 2D terrain, sprites, labels, jobs and up to four owned-friend markers. Everything in the world pans together on both axes inside a clamped oversized rectangle. The thin resource HUD and right circular action rail stay fixed, following Ninja Voltage's village composition. Pan survives snapshots, home/camp changes and inspector opening. Facility positions leave room for the right rail. A single docked inspector opens actual saved facility controls; unbuilt facilities are clearly labeled previews.

UI palette: dark sage ink #263A32, forest accent #53765B, neutral paper #F2EEE5, fine border #B8B7A7, amber primary #D5A64A. Typography is embedded Do Hyeon; height-based 1600×720 canvas with safe-area scaling. Keep the world dominant, with compact controls.

Cabin preserves the existing immersive 3D car with a thin affinity/remaining HUD, compact action dock, optional text/zone drawers and a start/failure sheet. Egg visuals exist only there. Preserve focused text and independent scroll positions across authoritative snapshots. Missing character art uses an explicit small placeholder without changing canonical IDs.

Dart controllers own all costs, affinity, ownership, saves and offline jobs. Latest dev authenticated companion selection, driving auto-fishing presentation and saved collection/base summary publication are retained. Existing distance/lookout camp material rules remain authoritative. Project-bound image assets/prompts are recorded in docs/village-art-provenance.md. Verification is recorded in docs/work-results/unity-phone/README.md.

For the requested collected-character preview, enable only the isolated fake-feed demo examples profile. Use the actual canonical character sprites and real demo ownership, rather than UI-only pretend IDs. Existing production/default data stays separate.

The Unity phone dex and inventory use a separate, scoped book treatment documented in [docs/design/book-ui/DESIGN.md](docs/design/book-ui/DESIGN.md). Its tokens and components are also recorded in `.impeccable/design.json`.

Village friends use their own eight-frame walking sheets with bounded destinations and short rests. Movement and facing follow actual travel; the name label stays upright. Input, inertia, inspectors, confirmations and reduced motion pause roaming. Selecting a friend opens a split detail: a large character animation on the left, with real role/activity and the existing learned-action and food controls on the right. Detail uses the existing five-frame joy reaction with its original GIF timing; village roaming keeps its walking sheets. Snapshot refreshes preserve actor position and preview phase.

The right character inspector leads with name, a compact dark-forest role badge (#3F6049), a short authored persona introduction and pale-sage personality tags. Group current activity, learned actions and food below fine rules. Empty action/food states explain the next step and link to the existing training/kitchen inspector; never invent stats or character lore. Keep the left joy animation separate and unchanged. Badge layout reserves32px height so Korean labels remain visible.
