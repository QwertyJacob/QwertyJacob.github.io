# Supabase

Per lavorare sull'integrazione Supabase, leggere prima `SUPABASE.md`.

- Usare lo stesso progetto di `../PSI_2.0`, senza crearne uno nuovo.
- Le credenziali locali sono in `supa.env`, escluso da Git. Leggerle solo quando
  necessario per il lavoro richiesto, senza stamparle o copiarle in file pubblici,
  log, commit o risposte.
- Nel browser usare soltanto URL API e chiave publishable presenti in
  `public/supabase-config.js`. Password DB e chiavi amministrative restano locali.
- Il database è condiviso con i sondaggi PSI: le nuove funzionalità per le tesi
  devono avere tabelle e policy proprie. Non modificare `votes`, `poll_counts`
  o le relative autorizzazioni per implementare le iscrizioni alle tesi.
- Prima di esporre una tabella contenente dati degli studenti, definire grant e
  Row Level Security; non rendere pubblico l'elenco delle iscrizioni.

I hook Git in `.githooks/` possono pubblicare automaticamente sul server DiSTA
al commit o al push. Tenerne conto prima di eseguire queste operazioni.
