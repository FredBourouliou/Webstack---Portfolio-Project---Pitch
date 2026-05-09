# Diagrammes de séquence

Trois flows critiques de l'application, du clic utilisateur jusqu'à la réponse HTTP. Format Mermaid (rendu natif sur GitHub).

## 1. Login (mode HASH, sha512crypt)

```mermaid
sequenceDiagram
    actor U as Utilisateur
    participant B as Navigateur
    participant A as Apache 2.4
    participant C as auth.cob
    participant E as /etc/cobill/cobill.env
    participant L as libcrypt (crypt(3))
    participant S as sessions.dat (ISAM)

    U->>B: saisit admin + password, clique [LOGIN]
    B->>A: POST /cgi-bin/auth?action=login<br/>body: username=admin&password=...
    A->>C: fork CGI<br/>PassEnv COBILL_AUTH_HASH
    C->>C: PARSE-CGI-INPUT
    C->>E: ACCEPT FROM ENVIRONMENT "COBILL_AUTH_HASH"
    E-->>C: $6$salt$hash...
    C->>L: CALL "crypt" (submitted, stored_hash)
    L-->>C: hash recalculé
    C->>C: comparaison byte-à-byte
    alt match
        C->>C: GENERATE-TOKEN (32 hex)
        C->>S: WRITE SESSION-RECORD (token, +24h)
        C-->>A: 302 Found<br/>Set-Cookie: COBILL_SID=...; HttpOnly
        A-->>B: 302 Location: /app.html
        B->>A: GET /app.html
        A-->>B: app shell (HTML statique)
    else no match
        C-->>A: 401 Unauthorized
        A-->>B: 401 + LOGIN FAILED
    end
```

## 2. Création de facture

```mermaid
sequenceDiagram
    actor U as Utilisateur
    participant B as Navigateur (HTMX)
    participant A as Apache 2.4
    participant I as invoice.cob
    participant S as sessions.dat
    participant D as invoices.dat
    participant C as clients.dat

    U->>B: remplit le form (client, lignes, dates), clique [CREATE]
    B->>A: POST /cgi-bin/invoice?action=create
    A->>I: fork CGI (cookie COBILL_SID)
    I->>S: AUTH-CHECK : READ session token
    S-->>I: valid + non expirée
    I->>C: READ client par CLI-ID (snapshot du nom)
    C-->>I: CLI-NAME
    I->>D: scan séquentiel pour le prochain INV-NUMBER<br/>format YYYY-NNNN
    D-->>I: max(seq) + 1
    I->>I: COMPUTE HT, TVA, TTC, URSSAF, NET (PIC 9(7)V99 ROUNDED)
    I->>D: WRITE INVOICE-RECORD<br/>(en-tête + 1..10 lignes en OCCURS)
    I-->>A: 200<br/>fragment HTML "INVOICE CREATED"
    A-->>B: fragment
    B->>B: HTMX swap dans #content
```

## 3. Enrichissement client via API SIRENE

```mermaid
sequenceDiagram
    actor U as Utilisateur
    participant B as Navigateur (HTMX)
    participant A as Apache 2.4
    participant Si as sirene.cob
    participant Sh as shell (curl + jq)
    participant API as recherche-entreprises.api.gouv.fr
    participant T as /tmp/sirene-XX.txt

    U->>B: saisit SIRET, clique [INSEE]
    B->>A: GET /cgi-bin/sirene?siret=542065479<br/>(hx-include='#f-siret')
    A->>Si: fork CGI
    Si->>Si: AUTH-CHECK + SANITIZE-SIRET (digits only, 9 ou 14)
    Si->>Sh: CALL "SYSTEM"<br/>curl ... | jq -f lib/sirene-extract.jq > tmp
    Sh->>API: GET /search?q=542065479&per_page=1
    API-->>Sh: JSON {results: [{nom_complet, siege:{adresse, code_postal, libelle_commune}}]}
    Sh->>T: 4 lignes : nom / adresse / zip / ville
    Sh-->>Si: rc=0
    Si->>T: OPEN INPUT + READ NEXT (4×)
    T-->>Si: nom, adresse, zip, ville
    Si->>Si: HTML-ESCAPE chaque champ
    Si-->>A: fragment HTML<br/>(hint #sirene-hint + 4× input hx-swap-oob='true')
    A-->>B: fragment
    B->>B: HTMX inject hint dans #sirene-hint<br/>OOB swap remplit #f-name, #f-addr, #f-zip, #f-city
```

## Notes de lecture

- Tous les binaires COBOL passent par le copybook `auth-check.cpy` (gate en début de programme), sauf `auth.cob` lui-même et `hello.cob`.
- `invoices.dat` et `clients.dat` sont des fichiers ISAM avec clés primaires + alternées — détails dans [`15-database-design.md`](15-database-design.md).
- L'API SIRENE (DINUM) est appelée sans clé d'authentification : seul le SIRET (que l'utilisateur a déjà saisi) sort du serveur.
- Toutes les sorties HTML passent par `HTML-ESCAPE` du copybook `cgi-utils-procs.cpy` pour neutraliser le risque XSS.
