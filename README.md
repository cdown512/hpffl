# HPFFL Archives

Static site. No build step, no server — every file here is served as-is.
Host it by uploading this folder's contents to a GitHub Pages repo (Settings → Pages → Deploy from a branch → `main` / root).

```
index.html      the whole app (layout, widgets, charts)
hpffl-data.js   all league data — franchises, seasons, champions
photos.js       the photo manifest (which pictures exist, and their captions)
photos/         the picture files themselves
support.js      runtime — do not edit
image-slot.js   drag-and-drop placeholder tiles, used when a photo slot is empty
_ds/            design system stylesheet + component bundle
uploads/        Outfit font files
```

## Adding photos

1. Drop the image into `photos/`. Resize to ~1600px wide and under ~400KB.
2. Add one line to `photos.js`:

```js
{ file: "2011-trophy-night.jpg", year: 2011, team: "Reservoir Dogs", caption: "Trophy night" },
```

| field | required | notes |
| --- | --- | --- |
| `file` | yes | filename inside `photos/` |
| `year` | no | season it belongs to; omit for undated/general |
| `team` | no | franchise name spelled exactly as in the app — also puts the photo on that team's page |
| `caption` | no | defaults to a tidied-up filename |
| `sort` | no | lower first within a year |

Commit, push, done. While `photos.js` is empty the Gallery shows the empty-slot mockup; the first real entry switches it to real photographs.

## Adding a season

Append the new season's rows to `hpffl-data.js` — `seasons` (one row per franchise per year), `champs`, and `leagueSeasons`. Every widget (standings, ladders, era filters, records) recalculates from that file; nothing in `index.html` needs to change.

## Notes

- Franchise names are the join key between `hpffl-data.js` and `photos.js`. Spelling must match exactly.
- Open `index.html` directly from disk to preview locally.
