# Solution

## What COBILL Does

COBILL is a lightweight, web-based invoicing tool that:

- **Calculates with banking-grade precision** using COBOL's native `PICTURE` clause (fixed-point decimal arithmetic)
- **Generates professional PDF invoices** using raw PostScript, rendered by Ghostscript — no wkhtmltopdf, no Puppeteer, no WeasyPrint
- **Tracks URSSAF contributions and VAT thresholds** automatically
- **Runs on any Linux server** with minimal resources (Apache + GnuCOBOL + Ghostscript)
- **Delivers a snappy UI** via HTMX — no React, no Vue, no npm

---

## Why COBOL for Money?

COBOL's `PICTURE` clause defines exactly how a number is stored — digits before the decimal, digits after, no ambiguity:

```cobol
01 MONTANT-HT       PIC 9(5)V99.
01 TAUX-TVA         PIC V99 VALUE .20.
01 MONTANT-TVA      PIC 9(5)V99.
01 MONTANT-TTC      PIC 9(6)V99.

COMPUTE MONTANT-TVA = MONTANT-HT * TAUX-TVA.
ADD MONTANT-HT MONTANT-TVA GIVING MONTANT-TTC.
```

`PIC 9(5)V99` means: up to 5 digits before the decimal point, exactly 2 after. The `V` marks the decimal position. There is no float. There is no rounding surprise. This is how banks have handled money since 1959 — and it's how COBILL handles yours.

### COBOL vs. Other Languages — Decimal Precision

| Operation | JavaScript | Python (float) | COBOL |
|-----------|-----------|-----------------|-------|
| `0.1 + 0.2` | `0.30000000000000004` | `0.30000000000000004` | `0.30` |
| `1.1 * 1.1` | `1.2100000000000002` | `1.2100000000000002` | `1.21` |
| `0.3 - 0.1` | `0.19999999999999998` | `0.19999999999999998` | `0.20` |

COBOL doesn't approximate. It counts.

---

## Why PostScript for PDFs?

PostScript is the native language of laser printers. Every PDF is, at its core, a descendant of PostScript. Instead of using a library that converts HTML to PDF (with all the rendering inconsistencies that implies), COBILL writes PostScript directly:

```postscript
/Helvetica-Bold findfont 18 scalefont setfont
72 750 moveto (FACTURE #0042) show

/Helvetica findfont 11 scalefont setfont
72 720 moveto (Client: Dupont SARL) show
72 705 moveto (Date: 2026-03-25) show

% Table row
72 650 moveto (Consulting) show
350 650 moveto (1 500,00 EUR) show
```

The PostScript file is converted to PDF by Ghostscript in a single command:

```bash
gs -sDEVICE=pdfwrite -dNOPAUSE -dBATCH -o invoice.pdf invoice.ps
```

### Benefits of PostScript over PDF Libraries

| Aspect | PostScript (COBILL) | PDF Libraries (typical) |
|--------|-------------------|------------------------|
| Pixel-perfect control | Yes — you place every element by coordinate | Approximate — HTML/CSS rendering varies |
| Dependencies | Ghostscript only | wkhtmltopdf + Qt, or Puppeteer + Chrome, or WeasyPrint + Cairo |
| File size | Small (text-based source) | Often bloated |
| Consistency | Identical output on every machine | Varies by renderer version |
| Learning curve | Moderate (stack-based language) | Low but debugging is hard |

---

## Why HTMX for the Frontend?

HTMX is a 14 KB JavaScript library that gives HTML the ability to make HTTP requests and swap DOM elements — without writing JavaScript.

```html
<button hx-post="/cgi-bin/cobill/create-invoice"
        hx-target="#result"
        hx-swap="innerHTML">
    Generate Invoice
</button>
<div id="result"></div>
```

When the user clicks, HTMX sends a POST request. The COBOL CGI program responds with an HTML fragment. HTMX injects it into `#result`. No JSON parsing. No state management. No virtual DOM.

### Why This Matters for COBILL

- **COBOL serves HTML directly** — no need for a JSON API, no serialization/deserialization layer
- **Zero build step** — one `<script>` tag in the HTML `<head>` and HTMX is installed
- **Coherent philosophy** — the entire stack avoids unnecessary complexity

---

## Why CGI?

CGI (Common Gateway Interface, 1993) is the original way to run server-side programs on the web. Apache receives an HTTP request, executes a binary, passes the request data via environment variables, and returns the program's stdout as the HTTP response.

For COBILL, this is ideal:

1. **COBOL compiles to a native binary** via GnuCOBOL → C → gcc
2. **Apache invokes the binary** on each request via mod_cgi
3. **The binary reads** `CONTENT_LENGTH`, `QUERY_STRING`, and stdin
4. **The binary writes** HTTP headers + HTML to stdout
5. **Apache returns** the response to the browser

No application server. No runtime. No framework. Just a binary that reads input and writes output — exactly what COBOL was designed to do.
