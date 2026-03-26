# Architecture

## System Overview

```
┌─────────────────────────────────────────────────────────┐
│                     USER BROWSER                         │
│                                                          │
│  ┌────────────────────────────────────────────────────┐ │
│  │  HTML + HTMX (14 KB) + CSS (retro terminal theme) │ │
│  │                                                     │ │
│  │  hx-post="/cgi-bin/cobill/create-invoice"          │ │
│  │  hx-get="/cgi-bin/cobill/list-invoices"            │ │
│  │  hx-target="#content"                               │ │
│  └──────────────────────┬─────────────────────────────┘ │
└─────────────────────────┼───────────────────────────────┘
                          │ HTTP (GET/POST)
                          ▼
┌─────────────────────────────────────────────────────────┐
│                   LINUX SERVER (VPS)                      │
│                                                          │
│  ┌────────────────────────────────────────────────────┐ │
│  │              Apache HTTP Server 2.4                 │ │
│  │              mod_cgi enabled                        │ │
│  │              /cgi-bin/cobill/*                      │ │
│  └──────────────────────┬─────────────────────────────┘ │
│                         │ CGI exec                       │
│                         ▼                                │
│  ┌────────────────────────────────────────────────────┐ │
│  │           COBOL PROGRAMS (GnuCOBOL)                │ │
│  │                                                     │ │
│  │  ┌──────────────┐  ┌──────────────────────────┐   │ │
│  │  │ invoice.cob  │  │ dashboard.cob            │   │ │
│  │  │ - Parse CGI  │  │ - URSSAF calculation     │   │ │
│  │  │ - Compute    │  │ - VAT threshold tracking │   │ │
│  │  │   HT/TVA/TTC│  │ - Revenue summary        │   │ │
│  │  │ - Write data │  │ - Monthly/yearly stats   │   │ │
│  │  │ - Return HTML│  │                          │   │ │
│  │  └──────┬───────┘  └──────────────────────────┘   │ │
│  │         │                                          │ │
│  │  ┌──────▼───────┐  ┌──────────────────────────┐   │ │
│  │  │ pdf-gen.cob  │  │ client.cob               │   │ │
│  │  │ - Read data  │  │ - Client CRUD            │   │ │
│  │  │ - Write .ps  │  │ - Contact management     │   │ │
│  │  │ - Call gs    │  │                          │   │ │
│  │  │ - Return PDF │  │                          │   │ │
│  │  └──────────────┘  └──────────────────────────┘   │ │
│  │                                                     │ │
│  │  ┌──────────────────────────────────────────────┐  │ │
│  │  │ cgi-utils.cob + auth.cob                     │  │ │
│  │  │ - CGI parsing (shared utility)               │  │ │
│  │  │ - Session management (cookie-based)          │  │ │
│  │  └──────────────────────────────────────────────┘  │ │
│  └────────────────────────────────────────────────────┘ │
│                                                          │
│  ┌────────────────────────────────────────────────────┐ │
│  │            DATA LAYER                               │ │
│  │                                                     │ │
│  │  /var/cobill/data/                                  │ │
│  │  ├── clients.dat    (COBOL ISAM indexed file)      │ │
│  │  ├── invoices.dat   (COBOL ISAM indexed file)      │ │
│  │  ├── sessions.dat   (session tokens)               │ │
│  │  └── config.dat     (user settings)                │ │
│  │                                                     │ │
│  │  /var/cobill/pdf/                                   │ │
│  │  ├── INV-2026-0001.ps   (PostScript source)        │ │
│  │  ├── INV-2026-0001.pdf  (generated PDF)            │ │
│  │  └── ...                                           │ │
│  └────────────────────────────────────────────────────┘ │
└─────────────────────────────────────────────────────────┘
```

---

## Data Flow — Creating an Invoice

```
1. User fills the invoice form in the browser
        │
        ▼
2. HTMX sends POST to /cgi-bin/cobill/create-invoice
   Body: client=Dupont%20SARL&item1=Consulting&qty1=5&rate1=300.00
        │
        ▼
3. Apache receives the request, invokes the COBOL binary
   Passes data via:
   - CONTENT_LENGTH environment variable
   - QUERY_STRING environment variable (for GET params)
   - stdin (for POST body)
        │
        ▼
4. COBOL program executes:
   a. ACCEPT CONTENT-LENGTH FROM ENVIRONMENT "CONTENT_LENGTH"
   b. READ POST-DATA FROM stdin
   c. PERFORM PARSE-FORM-DATA (split on & and =, URL-decode)
   d. COMPUTE MONTANT-TVA = MONTANT-HT * TAUX-TVA
   e. ADD MONTANT-HT MONTANT-TVA GIVING MONTANT-TTC
   f. WRITE invoice record to invoices.dat (ISAM)
   g. PERFORM GENERATE-POSTSCRIPT (write .ps file)
   h. CALL "SYSTEM" USING "gs -sDEVICE=pdfwrite -o out.pdf in.ps"
   i. DISPLAY HTTP headers + HTML fragment to stdout
        │
        ▼
5. Apache returns the HTML fragment to the browser
        │
        ▼
6. HTMX injects the fragment into #content
   Shows: invoice summary + "Download PDF" link
        │
        ▼
7. User clicks "Download PDF"
   Apache serves the static .pdf file from /var/cobill/pdf/
```

---

## Data Flow — Dashboard

```
1. User clicks [F3] DASHBOARD
        │
        ▼
2. HTMX sends GET to /cgi-bin/cobill/dashboard
        │
        ▼
3. COBOL dashboard.cob executes:
   a. OPEN INPUT invoices.dat
   b. READ all invoices for current year
   c. COMPUTE monthly totals using PIC 9(7)V99 accumulators
   d. COMPUTE URSSAF = TOTAL-HT * URSSAF-RATE
   e. COMPUTE VAT-threshold-percentage
   f. DISPLAY HTML fragment with:
      - Monthly revenue bar chart (CSS-based)
      - Year-to-date summary table
      - VAT threshold progress bar
      - Unpaid invoices list
        │
        ▼
4. HTMX injects dashboard HTML into #content
```

---

## Component Responsibilities

| Component | File | Responsibility |
|-----------|------|----------------|
| **Invoice Engine** | `invoice.cob` | Create, read, update invoices. All financial calculations. |
| **Client Manager** | `client.cob` | CRUD operations on client records. |
| **PDF Generator** | `pdf-gen.cob` | Generate PostScript source, invoke Ghostscript. |
| **Dashboard** | `dashboard.cob` | Aggregate invoice data, compute stats, render dashboard HTML. |
| **CGI Utilities** | `cgi-utils.cob` | Parse form data, URL-decode, read env vars. Shared by all programs. |
| **Auth Module** | `auth.cob` | Login, session creation, cookie management. |
| **PostScript Template** | `invoice-template.ps` | Base visual layout for PDF invoices. |
| **Frontend Shell** | `index.html` | HTML skeleton, HTMX integration, CSS themes. |

---

## Security Considerations

| Concern | Mitigation |
|---------|------------|
| **CGI injection** | All user input is sanitized in `cgi-utils.cob` before use |
| **Path traversal** | Invoice filenames are generated (YYYY-NNNN), never from user input |
| **Session hijacking** | Session tokens are random, stored server-side in ISAM, expire after 24h |
| **Shell injection** | Ghostscript command uses generated filenames only, never user-provided strings |
| **Data at rest** | ISAM files are only readable by the Apache user (chmod 600) |

---

## Why No Database?

COBOL has its own native file system: **ISAM** (Indexed Sequential Access Method). It supports:

- **Indexed reads** by primary key (invoice number, client ID)
- **Sequential reads** for listing and reporting
- **Atomic writes** for data integrity
- **Alternate keys** for searching by client name, date, etc.

For a single-user invoicing app, ISAM is simpler and faster than adding PostgreSQL or SQLite. It also reinforces the project's philosophy: **zero external dependencies beyond COBOL itself**.

### ISAM File Definition Example

```cobol
SELECT INVOICE-FILE
    ASSIGN TO "/var/cobill/data/invoices.dat"
    ORGANIZATION IS INDEXED
    ACCESS MODE IS DYNAMIC
    RECORD KEY IS INV-NUMBER
    ALTERNATE KEY IS INV-CLIENT WITH DUPLICATES
    ALTERNATE KEY IS INV-DATE WITH DUPLICATES
    FILE STATUS IS WS-FILE-STATUS.
```
