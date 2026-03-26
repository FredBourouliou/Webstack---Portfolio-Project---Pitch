# Learning Objectives

## Skills Demonstrated

This project covers the full spectrum of web development, from low-level protocol handling to user interface design.

---

## 1. Full-Stack Web Development

| Layer | Implementation |
|-------|----------------|
| Frontend | HTML5 + CSS3 + HTMX — responsive, themed, dynamic |
| Backend | COBOL programs serving HTML via CGI |
| Data | COBOL ISAM indexed files |
| Documents | PostScript → PDF generation |

COBILL demonstrates end-to-end ownership of every layer, without hiding behind frameworks or ORMs.

---

## 2. HTTP Protocol Mastery

Working with CGI requires understanding HTTP at a fundamental level:

- **Request methods** — GET for reads, POST for writes
- **Headers** — `Content-Type`, `Content-Length`, `Set-Cookie`, `Location` (redirects)
- **Status codes** — 200 OK, 302 Found, 401 Unauthorized, 404 Not Found
- **URL encoding** — parsing `%20`, `%26`, `+` from form data
- **Environment variables** — `CONTENT_LENGTH`, `QUERY_STRING`, `REQUEST_METHOD`, `HTTP_COOKIE`

There is no framework abstracting these details. Every HTTP interaction is handled explicitly in COBOL code.

---

## 3. Server-Side Rendering

COBOL programs generate HTML fragments directly:

```cobol
DISPLAY "<tr>"
DISPLAY "  <td>" INV-NUMBER "</td>"
DISPLAY "  <td>" INV-CLIENT "</td>"
DISPLAY "  <td>" INV-AMOUNT-TTC " EUR</td>"
DISPLAY "</tr>"
```

This is server-side rendering in its purest form — no template engine, no virtual DOM, no hydration step. The server computes the data and renders the HTML in one pass.

---

## 4. Data Persistence Without SQL

COBOL ISAM files provide indexed storage without a database server:

- **Record definition** — fixed-length records with typed fields
- **Indexed access** — primary keys, alternate keys, sequential reads
- **File I/O** — `OPEN`, `READ`, `WRITE`, `REWRITE`, `DELETE`, `CLOSE`
- **Error handling** — `FILE STATUS` codes for every operation

This teaches data persistence at a lower level than SQL, requiring explicit handling of indexing, sequential access, and file locking.

---

## 5. Document Generation

PostScript programming teaches:

- **Coordinate-based layout** — placing elements by (x, y) position
- **Font management** — selecting, scaling, and rendering typefaces
- **Vector graphics** — lines, rectangles, curves for table layouts
- **Page composition** — building a complete document programmatically

Understanding PostScript means understanding how PDFs actually work under the hood.

---

## 6. Financial Computing

Implementing an invoicing engine requires:

- **Fixed-point arithmetic** — COBOL's PIC clause vs. floating-point
- **Tax calculations** — TVA rates, URSSAF contributions
- **Threshold logic** — VAT exemption thresholds with edge cases
- **Rounding rules** — French legal requirements for invoice amounts

---

## 7. Web Deployment

Deploying COBILL requires:

- **Linux server administration** — Ubuntu, Apache configuration, file permissions
- **Build automation** — Makefile for compiling COBOL programs
- **CGI configuration** — Apache mod_cgi, ScriptAlias, directory permissions
- **SSL/TLS** — Let's Encrypt for HTTPS
- **Security hardening** — input sanitization, session management, file access control

---

## 8. Exploring Unfamiliar Technologies

The most important learning objective: **picking up unknown languages and tools under time pressure**, and delivering a production-grade result.

COBOL, PostScript, and CGI are not taught in the Holberton curriculum. Learning them from scratch and building a functional product in 27 days demonstrates the core skill that every employer values: **the ability to learn anything, fast.**

---

## Mapping to Holberton Competencies

| Holberton Competency | COBILL Implementation |
|---------------------|----------------------|
| Web infrastructure | Apache, CGI, HTTP protocol |
| Backend development | COBOL server-side programs |
| Frontend development | HTML, CSS, HTMX |
| Database / persistence | COBOL ISAM indexed files |
| DevOps / deployment | VPS setup, Makefile, deploy scripts |
| Security | Input sanitization, sessions, file permissions |
| Problem solving | Bridging 1959 technology with 2026 web standards |
| Technical communication | Documentation, pitch, architecture diagrams |
