# Village character movement and detail

Approved by the user on 2026-11-14: keep the village map visible behind an enlarged character and detail panel.

- Home/camp owned characters wander slowly near their starting positions. This is presentation state; no rewards, saves or job rules change. Snapshots preserve movement offsets.
- Tapping opens the exact owned character locally, without navigating to dex. Show enlarged canonical art, name, role, learned actions and existing food controls. Closing preserves map pan.
- Rename the existing Friends navigation label to the Korean word for encyclopedia (dex). Preserve collection records and existing dex functionality.
- Facility inspection and character detail are mutually exclusive. Leaving the village or removing the selected owned ID closes stale detail. Dragging pans without opening detail.
- reducedMotion disables wandering and zoom animation. Loading, busy, confirmation and pointer presses pause motion.

## Approach
Reuse the UGUI village and DockSheet/CreatureActions/FeedOptions. Enlarged character art plus a docked inspector keeps the map behind the detail. Scaling the entire map or converting camp to 3D would change existing pan constraints and the approved visual design.

## Ownership
Use the existing companion-learning-latest linked worktree. Own AppUiMap.cs, a new character-detail partial and village tests. AppUi.cs gets only the navigation-label change. Preserve the other active chat's edits; do not commit/push the whole dirty branch.
