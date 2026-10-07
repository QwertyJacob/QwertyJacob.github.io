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

Aprire il [Table Editor del progetto](https://supabase.com/dashboard/project/kmfpuqswhgslmhvekphl/editor)
con il proprio account amministratore e scegliere `public.thesis_applications`.
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
cancellarli privatamente dopo quel periodo. L'interfaccia amministrativa descritta
sotto usa RPC protette; la pagina statica di login non espone le tabelle.

### Area di amministrazione delle tesi

`tesi.html` ora collega `thesis-admin.html`. La pagina è in inglese, di sola
lettura e usa esclusivamente la configurazione di `public/supabase-config.js`
e la sessione personale Supabase Auth. Non ha dipendenze JavaScript esterne,
registrazione pubblica, password o chiavi amministrative nel browser.
La migration `supabase/migrations/202610070004_thesis_administration.sql`
è stata applicata il **7 ottobre 2026** allo stesso progetto PSI.
Inizialmente non erano autorizzati commit, push o pubblicazione. Il 7 ottobre
l'utente ha poi autorizzato la pubblicazione: il workflow `deploy-pages.yml`
pubblica il branch main su GitHub Pages con HTTPS. L'area si trova all'URL
`https://qwertyjacob.github.io/thesis-admin.html`; pubblicare il sito non modifica
i template, SMTP o redirect di Supabase e non verifica da solo il login OTP.
Per questa pubblicazione i hook DiSTA sono esclusi soltanto dai comandi Git
di commit/push con `-c core.hooksPath=/dev/null`, senza cambiarne la configurazione.

#### Autorizzazione e letture private

- `public.thesis_admins` è una allowlist di UUID `auth.users.id`, con foreign key
  e cancellazione a cascata. Grant revocati a PUBLIC/anon/authenticated/service_role,
  RLS abilitata e forzata, policy restrittiva di diniego. I client non possono
  leggerla, scriverla o aggiungersi. L'email non viene usata come autorizzazione.
- `thesis_admin_access()` restituisce solo un booleano per `auth.uid()` corrente.
  `thesis_admin_applications()` e `thesis_admin_assignments()` ricontrollano
  l'allowlist **ad ogni chiamata**, prima di validare i cursori o leggere record.
  La migration `202610070005_thesis_admin_sessions.sql`, applicata il 7 ottobre,
  richiede anche che il `session_id` del JWT appartenga all'utente corrente e
  corrisponda a una sessione Auth esistente, con `not_after` non scaduto.
  Un JWT privo di session_id, una sessione di un'altra identità o una sessione
  revocata non permettono letture anche quando il JWT non è ancora scaduto.
  Sono SECURITY DEFINER con proprietario postgres, search_path vuoto, SQL
  statico e nomi qualificati; EXECUTE solo ad authenticated, mai anon o PUBLIC.
  Non-admin: HTTP 403, indipendentemente dal successo del login.
- Non sono stati cambiati grant o policy sulle tabelle preesistenti, inclusi
  i dinieghi per i richiedenti. Anche l'amministratore non può usare SELECT/INSERT/
  UPDATE/DELETE diretti dalle API sulle tabelle private. Non esistono RPC di
  modifica nel dashboard. Rimuovere un UUID dall'allowlist impedisce subito
  ulteriori letture attraverso RPC, anche con JWT ancora valido.
- Le domande sono ordinate per `created_at ASC, id ASC`. La paginazione usa
  timestamp e UUID come cursore, senza offset; mantiene tutti i microsecondi
  restituiti da PostgreSQL e un limite superiore acquisito alla prima pagina.
  Il browser carica 20 record alla volta; il server consente da 1 a 100.
  **Load more applications** aggiunge la pagina successiva senza duplicati;
  **Refresh all** ricomincia e include i nuovi arrivi. Il limite superiore
  esclude nuovi inserimenti successivi; non è uno snapshot MVCC tra richieste:
  cancellazioni o correzioni amministrative delle date possono cambiare la lista.
- Le assegnazioni confermate hanno una sezione e paginazione distinte, ordinate
  per `assigned_at ASC, id ASC`. Un LEFT JOIN privato aggiunge l'arrivo della
  domanda soltanto quando esiste un `application_id`. Le assegnazioni precedenti
  sono conservate, senza inventare domande o contatti. Le nuove tesi Other
  richieste nella sessione sono state registrate soltanto nel database privato;
  identità e contatti non sono inclusi in migration, fixture o asset pubblici.
- Date mostrate con `Intl.DateTimeFormat`, timezone `Europe/Rome`. I valori degli
  studenti sono solo textContent/nodi di testo, inclusi email e descrizioni;
  non diventano HTML, handler o URL. La CSP permette script/stili locali e
  connessioni al solo progetto Supabase, vietando script inline ed eval.
- Sessione, refresh token, cursori e dati rimangono in memoria nella pagina.
  Nessun localStorage/sessionStorage, cookie, log di payload o esportazione.
  Le richieste fetch usano `cache: no-store`, `credentials: omit` e
  `referrerPolicy: no-referrer`. Ricaricare la pagina richiede un nuovo login.
  Logout cancella immediatamente entrambe le liste, i campi e la sessione,
  interrompe le richieste e ignora risposte tardive. Anche pagehide, errore
  401/403, rinnovo fallito e ritorno a una scheda con sessione scaduta cancellano
  i dati. Se il logout remoto fallisce, la pagina distingue il logout locale
  dalla revoca non confermata; come in Supabase, i JWT già emessi possono
  rimanere validi fino alla scadenza per altre API. Le RPC delle tesi controllano
  inoltre la sessione Auth attuale e negano l'accesso dopo un logout remoto riuscito.

#### Stato Auth verificato e account previsto

Prima del setup, `/auth/v1/settings` mostrava email abilitata, autoconfirm
disabilitato, signup di progetto abilitato e accesso anonimo Auth disabilitato;
`auth.users` era vuota. Le credenziali locali non includono service_role,
secret key o Management API token: non consentono di leggere SMTP, template,
Site URL e rate limit privati. Non sono state modificate impostazioni Auth
condivise, provider, signup di progetto o configurazioni email di PSI.

È stato creato **soltanto l'account indicato esplicitamente dall'utente**.
Lo strumento locale `scripts/thesis_admin.py provision --email <email-approvata>`
ha usato l'endpoint Auth ufficiale di signup, con password casuale scartata e
conferma email prevista dalla configurazione esistente; non ha scritto record
Auth manualmente. L'UUID di quell'account è stato aggiunto all'allowlist privata.
La conferma email è ora verificata nel database e l'utente ha confermato la
ricezione dell'email. Questo **non verifica ancora il login OTP del dashboard**.
Nessun account sintetico persiste dopo i test SQL.

Il browser chiama `/auth/v1/otp` con `create_user: false`, equivalente a
`signInWithOtp({ options: { shouldCreateUser: false } })`, poi
`/auth/v1/verify` con email, token e `type: 'email'`. Un login riuscito deve
superare anche il controllo della allowlist. Il rinnovo usa il refresh token
in memoria e ricontrolla l'autorizzazione. Nessun callback a redirect o sessione
nel frammento URL viene importato dalla pagina.

#### Setup manuale ancora necessario per verificare il login

1. Aprire la dashboard privata del progetto, **Authentication > Email Templates
   > Magic Link** (o “Magic link or OTP”). Ispezionare e conservare la versione
   attuale, perché è condivisa con PSI. Aggiungere al contenuto esistente:

   ```html
   <p>Your sign-in code: {{ .Token }}</p>
   ```

   Conservare eventuali link/testi necessari agli altri client. Per le tesi
   richiedere un'email nuova e digitare il codice nella pagina; non consumare
   prima il codice aprendo il link. Non sostituire globalmente template o
   redirect senza valutare i client PSI. Il dashboard accetta codici numerici
   da 6 a 10 cifre e non assume una scadenza del codice diversa da quella Auth.
   Un'email contenente solo un link non mostra l'OTP: aggiungere `.Token`,
   salvare il template **Magic Link** (non solo Confirm signup), e chiedere
   una nuova email dal pulsante **Send sign-in code** del dashboard. Se scanner
   automatici consumano il link, usare un ramo del template senza link per
   l'account admin, conservando il contenuto preesistente nel ramo degli altri
   account: `{{ if eq .Email "<email-approvata>" }}...OTP...{{ else }}...contenuto
   originale...{{ end }}`. L'email approvata si configura nella dashboard privata,
   senza pubblicarla negli asset o nelle migration.
2. Ispezionare **Custom SMTP**, eventuali Send Email hook, rate limit e Auth
   logs. La ricezione della conferma verifica una consegna signup, non il template
   Magic Link né tutti i flussi. L'SMTP predefinito Supabase consegna solo agli
   indirizzi autorizzati del team, con limiti bassi; un indirizzo esterno può
   richiedere SMTP proprio. Non aggiungere credenziali SMTP al browser o al sito.
3. L'utente ha riportato un link di conferma che terminava su
   `http://localhost:3000/#error=access_denied&error_code=otp_expired`.
   Il database mostra ora l'account confermato. Il link era monouso e risultava
   consumato/scaduto: un'apertura precedente o una scansione email sono possibili
   cause, non accertate. Il redirect localhost indica anche una configurazione
   URL/template da verificare nella dashboard. **URL Configuration** contiene
   Site URL e Redirect URLs: preservare quelli di PSI e concordare una
   destinazione HTTPS valida per i flussi che usano link. Il login tramite codice
   di questa pagina non richiede modifiche al Site URL né redirect.
   In seguito è stato condiviso un URL con sessione magic-link: indica che Auth
   ha emesso una sessione, non che il dashboard OTP sia stato aperto. Le credenziali
   non sono state copiate nei file o nei log. È stata revocata esclusivamente
   quella sessione, verificando prima proprietà e FK: la cancellazione di
   `auth.sessions` annulla in cascata i suoi refresh token. Il controllo sessione
   della migration 005 impedisce anche al relativo JWT ancora valido di leggere
   i dati delle tesi. Account e allowlist sono conservati per un nuovo login.
4. Aprire la pagina con HTTPS in produzione. Il login è disabilitato su HTTP
   remoto; per sviluppo è ammesso solo il loopback. Non usare un server statico
   sulla radice della repository. Anteprima locale con allowlist di soli asset:

   ```sh
   python3 scripts/serve_thesis_admin.py --port 8765
   # Aprire http://localhost:8765/thesis-admin.html
   ```

   Il server ascolta esclusivamente su 127.0.0.1, non registra richieste,
   invia Cache-Control no-store e non serve supa.env, Git o directory listings.
5. Dopo il setup del template, richiedere un codice nuovo, completare il login,
   controllare le due liste e il logout. Questa prova con il codice ricevuto
   personalmente è ancora necessaria: non condividere OTP, token o screenshot
   dei record privati nella chat. Nessun login reale viene dichiarato verificato
   soltanto perché le fixture passano.

Per una ricreazione dell'account, usare **Authentication > Users** nella dashboard
o `provision` solo per l'email approvata; se il signup è disabilitato, lo strumento
richiede la creazione dalla dashboard senza modificare il flag condiviso.
`grant` richiede esattamente un account con quell'email e non aggiunge un secondo
admin se ne esiste un altro. Non inserire manualmente auth.users/auth.identities.
Per un account creato dalla dashboard oppure per revocare l'accesso:

```sh
export THESIS_DB_HOST=aws-0-eu-west-1.pooler.supabase.com
/tmp/thesis-tools-venv/bin/python scripts/thesis_admin.py inspect
/tmp/thesis-tools-venv/bin/python scripts/thesis_admin.py grant --email <email-approvata>
/tmp/thesis-tools-venv/bin/python scripts/thesis_admin.py revoke --email <email-approvata>
```

GitHub Pages pubblica `thesis-admin.html`, `tesi.html` e i relativi asset public/
dal checkout Git, senza supa.env escluso da Git. Lo script DiSTA sincronizza una homepage legacy
e public/, ma non queste pagine HTML: prima di usarlo occorre includerle
esplicitamente e verificare HTTPS. Non è stato invocato o modificato durante
questo lavoro.

#### Verifiche dell'amministrazione

```sh
export THESIS_DB_HOST=aws-0-eu-west-1.pooler.supabase.com
/tmp/thesis-tools-venv/bin/python scripts/thesis_db.py test
/tmp/thesis-tools-venv/bin/python scripts/test_thesis_admin.py
/tmp/thesis-tools-venv/bin/python scripts/test_thesis_admin_api.py
/tmp/thesis-tools-venv/bin/python scripts/test_thesis_form.py
```

- Database reale, fixture nella transazione annullata: lettura admin tramite
  RPC; diniego anon; utente authenticated non-admin e admin senza grant diretti;
  impossibilità di autoiscrizione all'allowlist o modifica dei dati; dinieghi
  restrittivi anche con grant SELECT temporaneamente aggiunti e poi annullati;
  revoca dell'allowlist e della sessione tra due richieste, sessione Auth mancante/
  scaduta/di altra identità; limiti/cursori invalidi; ordinamento timestamp/UUID
  a parità di data; microsecondi; paginazione dopo cancellazione di una riga già
  letta e inserimento successivo al limite superiore; pagina vuota; date di
  assegnazione e arrivo distinte. Le identità/JWT claims dei test di ruolo sono
  simulate **nel database**, senza provisionare altri account reali.
- Chromium con Auth/RPC simulate e soli dati sintetici: nessuna registrazione,
  codice/login negato per non-admin, caricamento, vuoto, errore rete/server,
  recovery con refresh, entrambe le paginazioni e cursori invariati, date Roma,
  contenuto ostile come testo, assenza di storage/cookie, rinnovo/scadenza,
  errori 401/403, logout immediato e risposta tardiva, logout remoto fallito,
  blocco HTTP e impossibilità di servire supa.env. Non prova la consegna email
  né l'autenticazione dell'account personale con le API reali.
- Confronto prima/dopo migration: definizione di poll_counts, grant/policy di
  votes e di tutte le tabelle thesis preesistenti invariati; record delle
  assegnazioni conservati. La disponibilità reale continua a chiudere D e
  mantenere Other disponibile anche dopo più assegnazioni personalizzate.
- API REST reale con sola chiave publishable: anon non può leggere nessuna delle
  tre tabelle private né chiamare le tre RPC amministrative; l'endpoint pubblico
  di disponibilità restituisce soltanto topic_id/available. Le prove con JWT
  firmato di un admin/non-admin reale restano parte della verifica login manuale.

Riferimenti: [OTP/email](https://supabase.com/docs/guides/auth/auth-email-passwordless),
[template e link consumati dagli scanner](https://supabase.com/docs/guides/auth/auth-email-templates),
[SMTP](https://supabase.com/docs/guides/auth/auth-smtp),
[redirect](https://supabase.com/docs/guides/auth/redirect-urls),
[logout e durata JWT](https://supabase.com/docs/reference/javascript/auth-signout).

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
