/* HPFFL Archives — Supabase connection.
   The publishable key is safe in a static site: every table is read-only for
   public callers (see db/schema.sql). Never put the sb_secret_ key here.
   Blank the url to run the site off the local hpffl-data.js snapshot. */
window.HPFFL_SUPABASE = {
  url: 'https://wsvlicolbjwppnamuziw.supabase.co',
  anonKey: 'sb_publishable_Cf9vGH0Xe04pmN2Z9uXe3A_HhqvwlcR',
  photoBucket: 'photos'
};
