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
pagina, ad esempio `public/supabase-config.js` dalla homepage. `tesi.html` carica questo file e `public/thesis-application.js` con percorsi relativi.

GitHub Pages serve file statici e non carica `supa.env`. Il workflow pubblica un
checkout Git; il deploy DiSTA copia le pagine e `public/`. Mantenere questa
separazione anche per le anteprime: non esporre la radice locale della repository
con un server statico, perché contiene `supa.env`.

## Iscrizioni alle tesi

L'integrazione è implementata in `tesi.html` e `public/thesis-application.js`.
La migration `supabase/migrations/202610070001_thesis_applications.sql` è stata
applicata il **7 ottobre 2026** al progetto PSI indicato sopra. Non è stato
pubblicato il sito, né eseguito un commit o push.

### Schema, grant e RLS

- `public.thesis_applications`: UUID della richiesta, data, nome, cognome, email,
  corso di laurea, livello, array dei topic, descrizione di Other e note.
- RLS abilitata e forzata; policy restrittiva che nega ogni operazione a `anon`
  e `authenticated`. Nessun grant sulla tabella a `PUBLIC`, `anon`,
  `authenticated` o `service_role`. Nessuna lettura, lista, modifica o
  inserimento diretto dal browser, nemmeno per utenti autenticati.
- Endpoint di invio: `POST /rest/v1/rpc/submit_thesis_application`, eseguibile
  da `anon` e `authenticated`. Restituisce HTTP 204 senza dati personali.
  La funzione `SECURITY DEFINER`, di proprietà di `postgres`, usa un
  `search_path` vuoto e riferimenti espliciti alla tabella. Valida prima
  di inserire; nessun SQL dinamico e nessun parametro per consultare dati.
- Nome/cognome: 1–80 caratteri; email: formato valido e massimo 254;
  corso: 2–160; solo `bachelor`; 1–6 topic distinti fra `autumn26-a` …
  `autumn26-e` e `other`; Other richiede 20–2000 caratteri dopo trim;
  senza Other la descrizione deve essere vuota; note massimo 3000.
  Il server normalizza spazi esterni, email e ordine dei topic.
- `votes`, `poll_counts` e le loro autorizzazioni non vengono modificati.

### Disponibilità dei topic e assegnazioni confermate

La migration `supabase/migrations/202610070002_thesis_topic_availability.sql`
è stata applicata il 7 ottobre 2026. `public.thesis_topics` contiene gli ID
A–E e Other. `public.thesis_topic_assignments` conserva privatamente un topic
assegnato, nome/cognome, data e, quando noti, email, corso e collegamento alla
richiesta. Email e `application_id` possono essere null per assegnazioni inserite
dal supervisore senza dati di contatto: non si inventano indirizzi email.
Entrambe le tabelle hanno grant revocati ai client e RLS forzata con policy
restrittiva. Le richieste che esprimono interesse non assegnano automaticamente
un topic: soltanto un'assegnazione confermata lo rende indisponibile.

`POST /rest/v1/rpc/thesis_topic_availability` restituisce esclusivamente
`topic_id` e `available`, senza identità, contatti, conteggi o riferimenti alle
richieste. La funzione ha `search_path` vuoto e grant EXECUTE a anon/authenticated.
Il modulo consulta questo endpoint al caricamento e con **Refresh availability**,
mostra **Unavailable** e disabilita i topic assegnati. Se il controllo fallisce,
non consente l'invio fino a una verifica riuscita.

Il backend controlla la disponibilità anche durante l'invio e risponde HTTP 409
se uno dei topic selezionati è stato assegnato. Il modulo aggiorna allora i topic
e conserva i dati personali per scegliere un'alternativa. I retry identici di
una richiesta già ricevuta continuano a funzionare anche se il topic è stato
assegnato successivamente. Le modifiche alle assegnazioni usano lo stesso lock
degli invii; un indice univoco parziale sul topic impedisce assegnazioni
multiple dei topic A–E. Other resta selezionabile anche in presenza di
assegnazioni personalizzate.

Per consultare o gestire assegnazioni usare soltanto il Table Editor/SQL Editor
privato, tabella `public.thesis_topic_assignments`. Inserire una riga confermata
chiude un topic A–E; cancellarla lo rende nuovamente disponibile. Se si riceve in
seguito l'email di una persona già assegnata, aggiornare la riga privata e,
se necessario, inserire amministrativamente la domanda e collegarla tramite
`application_id`; non usare l'endpoint pubblico per un topic già chiuso.

Verificate disponibilità anonima priva di dati degli studenti, lettura delle
assegnazioni negata, rifiuto backend dei topic chiusi, retry dopo assegnazione,
UI disabilitata, recupero dopo errore di disponibilità e selezione diventata
indisponibile. Le fixture SQL sono annullate; il record reale dell'assegnazione
resta nel database privato e non è contenuto nelle migration o negli asset.

La migration `supabase/migrations/202610070003_custom_thesis_assignments.sql`
è stata applicata il 7 ottobre 2026 per supportare più tesi personalizzate.
Ogni assegnazione ha un UUID `id`; i topic A–E restano assegnabili una sola volta,
mentre `other` può avere più record. Un'assegnazione Other richiede
`other_description` con 20–2000 caratteri dopo trim. Email, corso e collegamento
alla domanda restano facoltativi quando non forniti al supervisore.
La disponibilità e il controllo dell'invio escludono Other dalle chiusure:
registrare una tesi personalizzata non impedisce altre proposte personalizzate.
Grant e RLS continuano a proteggere tutte le assegnazioni.

Per consultare le tesi confermate e le descrizioni, nell'SQL Editor privato:

```sql
select id, assigned_at, topic_id, first_name, last_name, email,
       degree_programme, other_description, application_id
from public.thesis_topic_assignments
order by assigned_at desc;
```

I test SQL verificano più assegnazioni Other, descrizione obbligatoria,
unicità dei topic A–E e disponibilità/invio di Other dopo un'assegnazione.
Verificata inoltre tramite API reale la disponibilità di Other, la chiusura
preesistente di D e il diniego della lettura pubblica delle assegnazioni.
I dati reali degli studenti sono inseriti soltanto nel database privato,
non nei file SQL o nella documentazione.

### Invio, privacy e abuso

La chiave publishable permette solo di chiamare l'endpoint autorizzato,
non di consultare la tabella. Il modulo offre validazione, caricamento,
errori e conferma in inglese; blocca i controlli durante l'invio, conserva
le informazioni in caso di errore e le cancella dalla pagina al successo.
Non memorizza dati o sessioni in localStorage/sessionStorage e non registra
payload o errori del server nella console.

Ogni tentativo usa un UUID casuale. Un retry nella stessa pagina con gli
stessi dati riusa l'UUID e non duplica l'applicazione, anche se la prima
risposta è andata persa. Modificare i dati o ricaricare la pagina genera
un'altra richiesta, soggetta ai limiti sottostanti.

Il database serializza gli invii con un advisory lock dedicato e impone:
**una domanda per email ogni 24 ore**, **30 domande nell'ultima ora** e
**100 nelle ultime 24 ore**. I conteggi usano finestre mobili, senza fidarsi
di IP, timestamp o contatori forniti dal browser. HTTP 429 ha lo stesso
messaggio per tutti i limiti. Un honeypot respinge i bot più semplici.
I limiti si applicano anche chiamando direttamente l'API.

Questa è una scelta senza servizi aggiuntivi per un modulo pubblico a basso
volume. **Non verifica la proprietà dell'email o l'appartenenza a un'università**:
non è stata fornita una lista di domini accettati. Un bot può cambiare email
ed esaurire la quota globale, impedendo temporaneamente nuovi invii; inoltre
il limite riguarda le domande accettate, non il volume delle richieste HTTP.
Per una protezione più forte servono un gateway/Edge Function con CAPTCHA
verificato sul server, limiti per IP affidabile ed eventualmente verifica
email. Non basta aggiungere un CAPTCHA al solo browser: occorre togliere
agli utenti pubblici l'accesso diretto alla funzione e farla chiamare solo
al gateway. Non sono disponibili token di gestione, secret CAPTCHA o
configurazione SMTP per realizzare questo ulteriore setup; non sono state
cambiate le impostazioni Auth del progetto condiviso.

Non si applicano restrizioni CORS/origin come autorizzazione: possono essere
aggirate da client esterni. Il backend restituisce soltanto messaggi generici.
Usare HTTPS per il sito pubblicato: l'URL DiSTA HTTP dello script di deploy
non protegge l'integrità del JavaScript servito, anche se l'API Supabase usa HTTPS.

### Accesso privato alle domande

Il link **Thesis administration** in `tesi.html` apre direttamente
[public.thesis_applications nel Table Editor](https://supabase.com/dashboard/project/kmfpuqswhgslmhvekphl/editor/17630).
Accedere con il proprio account della dashboard Supabase, autorizzato al progetto.
Per vedere le assegnazioni confermate aprire
[public.thesis_topic_assignments](https://supabase.com/dashboard/project/kmfpuqswhgslmhvekphl/editor/17667).
Queste tabelle restano private e richiedono l'accesso alla dashboard.
In alternativa, nell'SQL Editor autenticato:

```sql
select created_at, first_name, last_name, email, degree_programme,
       thesis_level, topics, other_description, additional_notes
from public.thesis_applications
order by created_at asc, id asc;
```

Non creare viste pubbliche o policy SELECT per consultare le iscrizioni.
Scaricare eventuali esportazioni solo in una directory privata fuori dalla
repository e dagli artefatti del sito. I record restano fino alla cancellazione
amministrativa: concordare un periodo di conservazione adatto alle tesi e
cancellarli privatamente dopo quel periodo.

### Amministrazione tramite dashboard Supabase

Il 7 ottobre 2026 l'utente ha scelto di consultare direttamente il database
nella dashboard Supabase. La pagina di login personalizzata, i relativi asset
e gli strumenti di anteprima/test del browser sono stati rimossi dal sito.
Non occorre configurare SMTP, OTP o template email per questa modalità:
il login è quello del proprio account Supabase, con accesso al progetto PSI.

Il modulo pubblico di `tesi.html` continua a usare soltanto la configurazione
publishable di `public/supabase-config.js`, l'RPC di invio e quella di
disponibilità. Solo Bachelor’s, D non disponibile, Other disponibile per più
tesi personalizzate. Il link al Table Editor non concede accesso pubblico
alle domande o alle assegnazioni.

Le migration `202610070004_thesis_administration.sql` e
`202610070005_thesis_admin_sessions.sql` restano come storico dello schema
applicato. L'allowlist e le RPC precedenti rimangono protette, senza interfaccia
sul sito; nessuna tabella, assegnazione o account Auth è stato cancellato per
questo cambiamento. Non sono state modificate configurazioni Auth/email,
policy o grant del progetto condiviso. I test SQL e API delle autorizzazioni
restano disponibili nei relativi file di `supabase/tests/` e
`scripts/test_thesis_admin_api.py`.

La pubblicazione usa il workflow GitHub Pages `deploy-pages.yml` sul branch
main. I hook DiSTA vengono esclusi soltanto dai comandi di commit/push con
`-c core.hooksPath=/dev/null`, senza modificarne la configurazione.

### Amministrazione e verifica

Gli strumenti locali non eseguono `source supa.env` e non stampano credenziali
né dati degli studenti. Creare un virtualenv fuori dalla directory pubblicata:

```sh
python3 -m venv /tmp/thesis-tools-venv
/tmp/thesis-tools-venv/bin/pip install 'psycopg[binary]' python-dotenv playwright
export THESIS_DB_HOST=aws-0-eu-west-1.pooler.supabase.com
/tmp/thesis-tools-venv/bin/python scripts/thesis_db.py inspect
# Solo su un database dove questa migration NON è ancora stata applicata:
/tmp/thesis-tools-venv/bin/python scripts/thesis_db.py apply
# Su un database con la prima migration ma senza la seconda:
/tmp/thesis-tools-venv/bin/python scripts/thesis_db.py apply --migration 202610070002_thesis_topic_availability.sql
# Su un database con le prime due migration ma senza la terza:
/tmp/thesis-tools-venv/bin/python scripts/thesis_db.py apply --migration 202610070003_custom_thesis_assignments.sql
/tmp/thesis-tools-venv/bin/python scripts/thesis_db.py test
/tmp/thesis-tools-venv/bin/playwright install chromium
/tmp/thesis-tools-venv/bin/python scripts/test_thesis_form.py
```

Il session pooler sopra è stato verificato per questo progetto (porta 5432).
Per future modifiche usare **Dashboard > Connect**, `THESIS_DB_HOST` e, se
necessario, `THESIS_DB_PORT`. La connessione diretta predefinita richiede IPv6,
non disponibile in questo ambiente. `apply` non è una migration runner:
applica il file selezionato una sola volta; futuri cambi devono avere nuove
migration. L'SQL Editor offre un'alternativa senza dipendenze Python.

Verifiche eseguite il 7 ottobre 2026:

- Test SQL nella transazione poi annullata: invio, retry, grant/RLS per ruoli
  anon e authenticated, livello, topic, null, duplicati, Other, email, limiti
  di lunghezza, honeypot e quote oraria/giornaliera.
- API reale: SELECT anon negata (401), Master’s rifiutato (400), invio sintetico
  accettato (204), retry senza duplicati, limite email (429). Il record sintetico
  è stato rimosso; nessuna iscrizione di test persistente.
- Confronto dei cataloghi prima/dopo: grant e policy di `votes`, definizione
  e grant di `poll_counts` invariati.
- Browser Chromium con API simulata: campi obbligatori, selezione multipla,
  Other condizionale, Master’s disabilitato, lock durante invio, successo,
  errori HTTP/rete/timeout, retry con lo stesso UUID, assenza di storage dei dati.
  La prova serve solo un allowlist di asset, mai la radice con `supa.env`.

I test SQL assumono che le quote non siano già esaurite da domande reali;
non cambiano record persistenti e tutte le fixture vengono annullate.
Per evitare interferenze con nuovi invii durante il test delle quote,
eseguire i test SQL prima della pubblicazione o su un database di test.

Riferimenti ufficiali: [chiavi API](https://supabase.com/docs/guides/getting-started/api-keys),
[Row Level Security](https://supabase.com/docs/guides/database/postgres/row-level-security),
[funzioni database](https://supabase.com/docs/guides/database/functions),
[protezione API](https://supabase.com/docs/guides/api/securing-your-api),
[connessione PostgreSQL](https://supabase.com/docs/guides/database/connecting-to-postgres).
