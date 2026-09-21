/* HPFFL Archives — Supabase data layer.

   Reads the four content tables over Supabase's REST endpoint (no SDK, no
   build step) and shapes them into exactly the globals the app already
   expects: window.HPFFL_DATA and window.HPFFL_PHOTOS. Then it fires an
   'hpffl-data' event so a rendered page rebuilds with fresh data.

   The local hpffl-data.js / photos.js files stay in place as an instant-paint
   snapshot; whatever comes back from the database replaces them. If no
   credentials are configured, the snapshot is all you get. */
(function () {
  var C = window.HPFFL_SUPABASE || {};
  window.HPFFL_DB = { status: 'idle', error: null };
  if (!C.url || !C.anonKey) { window.HPFFL_DB.status = 'no-config'; return; }

  var base = C.url.replace(/\/+$/, '');
  var headers = { apikey: C.anonKey, Authorization: 'Bearer ' + C.anonKey, Accept: 'application/json' };

  function get(path) {
    return fetch(base + '/rest/v1/' + path, { headers: headers }).then(function (r) {
      if (!r.ok) return r.text().then(function (t) { throw new Error(path + ' → ' + r.status + ' ' + t.slice(0, 200)); });
      return r.json();
    });
  }

  // The page references hpffl-data.js / photos.js twice (head + helmet), so the
  // static snapshot re-executes after this fetch resolves. Lock the globals to
  // the database values so the later assignment can't clobber them.
  function lock(name, value) {
    try {
      Object.defineProperty(window, name, {
        configurable: true, enumerable: true,
        get: function () { return value; },
        set: function () {}
      });
    } catch (e) { window[name] = value; }
  }

  function num(v) { return v == null ? null : +v; }
  function int(v) { return v == null ? 0 : +v; }
  function flag(v) { return v ? 1 : 0; }

  function photoUrl(p) {
    var path = p.storage_path || p.file;
    if (/^https?:\/\//i.test(path)) return path;
    if (!C.photoBucket) return 'photos/' + encodeURIComponent(path);
    return base + '/storage/v1/object/public/' + C.photoBucket + '/' +
      String(path).split('/').map(encodeURIComponent).join('/');
  }

  window.HPFFL_DB.status = 'loading';

  Promise.all([
    get('franchises?select=*&order=name.asc'),
    get('league_seasons?select=*&order=year.asc'),
    get('seasons?select=*&order=year.desc&limit=5000'),
    get('photos?select=*,photo_franchises(franchise_id,sort)&order=year.desc&limit=5000')
  ]).then(function (res) {
    var fr = res[0], ls = res[1], se = res[2], ph = res[3];
    var nameById = {};
    fr.forEach(function (f) { nameById[f.id] = f.name; });

    var champs = {};
    ls.forEach(function (r) { if (r.champ_franchise_id) champs[r.year] = r.champ_franchise_id; });

    lock('HPFFL_DATA', {
      franchises: fr.map(function (f) {
        return {
          id: f.id, name: f.name, active: !!f.active,
          first: f.first_season, last: f.last_season,
          leagueSeasons: f.league_seasons, era: f.era,
          owners: f.owners || [], formerOwners: f.former_owners || [],
          formerNames: f.former_names || [], notes: f.notes || null
        };
      }),
      seasons: se.map(function (s) {
        return {
          fid: s.franchise_id, y: s.year, era: s.era,
          w: int(s.w), l: int(s.l), t: int(s.t), pw: int(s.pw), pg: int(s.pg),
          champ: flag(s.champ), conf: flag(s.conf), div: flag(s.div),
          dw: int(s.dw), dl: int(s.dl), dt: int(s.dt),
          pf: num(s.pf), pa: num(s.pa), ppf: num(s.ppf), ppa: num(s.ppa),
          potw: int(s.potw), totw: int(s.totw),
          mlw: int(s.mlw), mla: int(s.mla), cbl: int(s.cbl), cba: int(s.cba)
        };
      }),
      leagueSeasons: ls.map(function (r) {
        return { year: r.year, era: r.era, teams: r.teams, games: r.games, champ: r.champ_franchise_id || null, note: r.note || null };
      }),
      champs: champs
    });

    lock('HPFFL_PHOTOS', ph.map(function (p) {
      var tags = (p.photo_franchises || []).slice().sort(function (a, b) { return (a.sort || 0) - (b.sort || 0); });
      return {
        file: p.file,
        url: photoUrl(p),
        year: p.year == null ? null : +p.year,
        teams: tags.map(function (t) { return nameById[t.franchise_id]; }).filter(Boolean),
        caption: p.caption || null,
        sort: p.sort == null ? 0 : +p.sort
      };
    }));

    window.HPFFL_DB.status = 'ready';
    window.dispatchEvent(new CustomEvent('hpffl-data'));
  }).catch(function (e) {
    window.HPFFL_DB.status = 'error';
    window.HPFFL_DB.error = e && e.message;
    console.error('[HPFFL] Supabase load failed — falling back to the local snapshot.', e);
    window.dispatchEvent(new CustomEvent('hpffl-data'));
  });
})();
