# Technology Stack

## Overview

| Component | Technology | Year | Justification |
|-----------|-----------|------|---------------|
| **Financial engine** | GnuCOBOL 3.x | 1959 | Native decimal arithmetic (`PIC` clause), compiled to native binary via C, 65+ years of battle-tested reliability |
| **PDF generation** | PostScript + Ghostscript | 1985 | Direct PDF rendering with pixel-perfect control, no library dependency |
| **Web server** | Apache 2.4 + mod_cgi | 1995 | Industry standard, CGI support out of the box, zero configuration complexity |
| **Frontend** | HTML5 + HTMX 2.x + CSS3 | 2020 | Dynamic UI without JavaScript frameworks, 14 KB total JS, no build step |
| **Data storage** | COBOL ISAM files | 1959 | Native to COBOL, no database server needed, indexed sequential access |
| **Server OS** | Ubuntu 22.04 LTS | — | GnuCOBOL available via `apt`, stable, well-documented |
| **Deployment** | Single VPS | — | No Docker, no orchestration — compiled binaries + Apache |

---

## GnuCOBOL — The Financial Engine

**What it is:** An open-source COBOL compiler that translates COBOL to C, then compiles to native machine code via GCC.

**Why it's the right choice:**

1. **Native decimal arithmetic** — The `PICTURE` clause defines exact decimal storage. `PIC 9(5)V99` means 5 digits + 2 decimal places, no floating-point involved.

2. **Compiled to native binary** — GnuCOBOL → C → GCC → binary. The resulting executable is fast, small, and has no runtime dependency.

3. **CGI-compatible** — COBOL can read environment variables (`ACCEPT FROM ENVIRONMENT`) and write to stdout (`DISPLAY`), which is all CGI requires.

4. **ISAM file support** — Native indexed file I/O for data persistence.

**Installation:**
```bash
sudo apt install gnucobol
```

**Compilation:**
```bash
cobc -x -o create-invoice invoice.cob cgi-utils.cob
```

---

## PostScript + Ghostscript — The PDF Engine

**What it is:** PostScript is a page description language created by Adobe in 1985. Ghostscript is an open-source interpreter that converts PostScript to PDF.

**Why it's the right choice:**

1. **Pixel-perfect control** — Every text element, line, and shape is placed by exact coordinates. No CSS rendering quirks.

2. **Zero library dependency** — No wkhtmltopdf (requires Qt), no Puppeteer (requires Chrome), no WeasyPrint (requires Cairo). Just Ghostscript.

3. **Text-based source** — The `.ps` file is plain text. COBOL can generate it line by line with `WRITE` statements.

4. **Industry standard** — PostScript/PDF are the backbone of professional printing. The output is guaranteed consistent.

**Installation:**
```bash
sudo apt install ghostscript
```

**Conversion:**
```bash
gs -sDEVICE=pdfwrite -dNOPAUSE -dBATCH -dQUIET -o output.pdf input.ps
```

---

## Apache 2.4 + mod_cgi — The Web Server

**What it is:** The Apache HTTP Server with CGI module enabled.

**Why it's the right choice:**

1. **CGI is built-in** — `a2enmod cgi` and it works. No plugins, no middleware.

2. **Static file serving** — Serves HTML, CSS, JS, and generated PDFs out of the box.

3. **Battle-tested** — Apache has been serving the web since 1995. Configuration is well-documented.

4. **No application server needed** — CGI invokes the COBOL binary directly. No WSGI, no Node, no PM2.

**Configuration:**
```apache
ScriptAlias /cgi-bin/cobill/ /usr/lib/cgi-bin/cobill/
<Directory "/usr/lib/cgi-bin/cobill">
    AllowOverride None
    Options +ExecCGI
    Require all granted
</Directory>
```

---

## HTMX 2.x — The Frontend Library

**What it is:** A 14 KB JavaScript library that extends HTML with attributes for making HTTP requests and swapping DOM content.

**Why it's the right choice:**

1. **Server returns HTML, not JSON** — COBOL generates HTML fragments directly. No API layer, no serialization.

2. **No build step** — One `<script>` tag. No webpack, no Vite, no npm.

3. **No JavaScript to write** — All interactivity is declared in HTML attributes.

4. **Progressive enhancement** — The app works without JavaScript (forms still submit via standard POST). HTMX enhances the experience.

**Integration:**
```html
<script src="/js/htmx.min.js"></script>
```

---

## COBOL ISAM — The Data Layer

**What it is:** Indexed Sequential Access Method — COBOL's native file system for structured data storage.

**Why it's the right choice:**

1. **Native to COBOL** — No ORM, no driver, no connection string. `OPEN`, `READ`, `WRITE`, `CLOSE`.

2. **Indexed access** — Define primary and alternate keys. Search by invoice number, client name, or date.

3. **No server process** — Unlike PostgreSQL or MySQL, ISAM files are just files on disk. No daemon running.

4. **Transactional** — COBOL file I/O supports error handling via `FILE STATUS` codes.

**Trade-off:** ISAM doesn't support complex queries (joins, aggregations). All aggregation logic is written in COBOL procedural code. For a single-user invoicing app, this is acceptable and even desirable (no SQL injection possible).

---

## Stack Comparison

| Aspect | COBILL | Typical Modern Stack |
|--------|--------|---------------------|
| Languages | COBOL + PostScript + HTML | JavaScript + JavaScript + JavaScript |
| Frontend framework | HTMX (14 KB) | React (140 KB) + router + state management |
| Build tools | `make` (Makefile) | webpack + babel + eslint + prettier + ... |
| Package manager | None | npm (500+ packages) |
| Database | COBOL ISAM (files) | PostgreSQL + ORM + migrations |
| PDF library | PostScript + Ghostscript | Puppeteer + Chrome or wkhtmltopdf + Qt |
| Application server | Apache CGI | Express/Fastify + PM2 |
| Total JS shipped | 14 KB | 200-500 KB |
| Infrastructure cost | €3-5/month | €15-50/month |
| `node_modules` size | N/A | 200+ MB |
