/* HPFFL Archives — Supabase connection.
   Fill these in from your Supabase project: Settings → API.
   The anon key is publishable — it is safe in a static site because every
   table is read-only for the anon role (see db/schema.sql).
   Leave url empty to run the site off the local hpffl-data.js snapshot. */
window.HPFFL_SUPABASE = {
  url: '',            // e.g. 'https://abcdefghijkl.supabase.co'
  anonKey: '',        // e.g. 'eyJhbGciOi...'
  photoBucket: 'photos'
};
