# Supabase condiviso con PSI

Questa repository usa il progetto già configurato in `../PSI_2.0/supa.env`:

- Project ref: `kmfpuqswhgslmhvekphl`.
- [Dashboard del progetto](https://supabase.com/dashboard/project/kmfpuqswhgslmhvekphl).
- URL API: `https://kmfpuqswhgslmhvekphl.supabase.co`.
- Configurazione originale dei sondaggi:
  `../PSI_2.0/PSI-VA-2627/docs/assets/sondaggi.js`.

## Credenziali locali

`supa.env` contiene una copia della configurazione originale, inclusa la password
del database, con permessi `600`. È escluso da Git e deve rimanere fuori dalle
directory e dagli artefatti pubblicati. Non stamparne il contenuto.

| Variabile | Uso |
| --- | --- |
| `PROJECT_NAME`, `PROJECT_ID` | Identificativi ereditati da PSI |
| `PROJECT_UR` | Link alla dashboard; **non** è l'URL API |
| `SUPABASE_URL` | URL API aggiunto per questa integrazione |
| `PUBLISHABLE_KEY` | Chiave pubblica già usata dai sondaggi |
| `DB_PASSWORD` | Password PostgreSQL, solo per amministrazione locale |

Il file è una copia locale, non viene sincronizzato automaticamente: eventuali
rotazioni delle credenziali vanno riportate anche qui. Per una nuova clonazione,
recuperarlo dalla configurazione locale autorizzata e mantenere i permessi `600`.
Non eseguirlo con `source`: leggere le assegnazioni come dati con un parser dotenv.

Per amministrare il database, usare l'SQL Editor della dashboard oppure i
parametri di connessione PostgreSQL mostrati da **Connect**, con `DB_PASSWORD`.
La chiave publishable non permette di creare tabelle o amministrare il progetto.
Non sono stati aggiunti token di gestione o chiavi `service_role`.

## Configurazione per il sito statico

`public/supabase-config.js` espone `window.SITE_SUPABASE` con `url` e
`publishableKey`. Contiene soltanto i valori destinati al browser, come nella
configurazione dei sondaggi PSI. Per usarlo in una futura pagina:

```html
<script src="/public/supabase-config.js"></script>
<script>
  const { url, publishableKey } = window.SITE_SUPABASE;
  // API REST: `${url}/rest/v1/<tabella>`
  // Header: { apikey: publishableKey, 'Content-Type': 'application/json' }
</script>
```

Su DiSTA il sito vive sotto `~jesus.cevallos/`: usare un percorso relativo alla
pagina, ad esempio `public/supabase-config.js` dalla homepage. Le pagine attuali
non caricano ancora questo file; verrà incluso nel modulo delle tesi.

GitHub Pages serve file statici e non carica `supa.env`. Il workflow pubblica un
checkout Git; il deploy DiSTA copia le pagine e `public/`. Mantenere questa
separazione anche per le anteprime: non esporre la radice locale della repository
con un server statico, perché contiene `supa.env`.

## Prossima funzionalità: iscrizioni alle tesi

Questa preparazione non crea ancora tabelle o moduli. Per implementarli:

1. Definire i campi del modulo e creare una tabella dedicata, ad esempio
   `public.thesis_signups`, nello stesso progetto. Conservare lo SQL nella repo.
2. Definire grant e Row Level Security prima di collegare il modulo. Nome,
   email e altri dati delle iscrizioni non devono essere leggibili pubblicamente.
   Stabilire se l'invio richiede autenticazione e chi può consultare le richieste.
3. Collegare il modulo alla nuova tabella usando la configurazione pubblica;
   verificare inserimento, gestione degli errori e accessi negati.

Le tabelle dei sondaggi (`votes`) e la funzione `poll_counts` condividono il
progetto ma mantengono le proprie regole. Non riutilizzarle per le tesi e non
allargare i permessi globali di `anon` o `authenticated`.

Riferimenti ufficiali: [chiavi API](https://supabase.com/docs/guides/getting-started/api-keys),
[Row Level Security](https://supabase.com/docs/guides/database/postgres/row-level-security),
[connessione PostgreSQL](https://supabase.com/docs/guides/database/connecting-to-postgres).
