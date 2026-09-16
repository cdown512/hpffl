/* HPFFL Archives — photo manifest.
   Add one entry per picture. Drop the image file itself into the photos/ folder.

   file     (required) filename inside photos/  e.g. "2011-trophy-night.jpg"
   year     (optional) season the photo belongs to. Omit for undated/general.
   team     (optional) franchise name, spelled exactly as it appears in the app.
   caption  (optional) shown under the photo. Falls back to the filename.
   sort     (optional) lower numbers come first inside a year.

   Keep images ~1600px wide and under ~400KB so the page stays fast.
*/
window.HPFFL_PHOTOS = [
  // { file: "2011-trophy-night.jpg", year: 2011, team: "Reservoir Dogs", caption: "Trophy night" },
  // { file: "1999-original-trophy.jpg", caption: "The original trophy" }
];
