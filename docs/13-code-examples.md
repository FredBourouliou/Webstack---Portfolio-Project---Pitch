# Code Examples

## Overview

This document provides working code samples for the three core technologies: COBOL (backend), PostScript (PDF generation), and HTMX (frontend).

---

## COBOL — CGI Invoice Creation

### Reading CGI Input and Computing Totals

```cobol
       IDENTIFICATION DIVISION.
       PROGRAM-ID. CREATE-INVOICE.

       ENVIRONMENT DIVISION.
       INPUT-OUTPUT SECTION.
       FILE-CONTROL.
           SELECT INVOICE-FILE
               ASSIGN TO "/var/cobill/data/invoices.dat"
               ORGANIZATION IS INDEXED
               ACCESS MODE IS DYNAMIC
               RECORD KEY IS INV-NUMBER
               FILE STATUS IS WS-FILE-STATUS.

       DATA DIVISION.
       FILE SECTION.
       FD INVOICE-FILE.
       01 INVOICE-RECORD.
           05 INV-NUMBER       PIC X(9).
           05 INV-CLIENT       PIC X(50).
           05 INV-DATE         PIC X(10).
           05 INV-DUE-DATE     PIC X(10).
           05 INV-AMOUNT-HT    PIC 9(5)V99.
           05 INV-AMOUNT-TVA   PIC 9(5)V99.
           05 INV-AMOUNT-TTC   PIC 9(6)V99.
           05 INV-STATUS       PIC X(8).

       WORKING-STORAGE SECTION.
       01 WS-FILE-STATUS       PIC XX.
       01 WS-CONTENT-LENGTH    PIC 9(5).
       01 WS-POST-DATA         PIC X(2000).
       01 WS-CLIENT-NAME       PIC X(50).
       01 WS-AMOUNT-HT         PIC 9(5)V99.
       01 WS-TVA-RATE          PIC V99 VALUE .20.
       01 WS-AMOUNT-TVA        PIC 9(5)V99.
       01 WS-AMOUNT-TTC        PIC 9(6)V99.
       01 WS-URSSAF-RATE       PIC V99 VALUE .22.
       01 WS-URSSAF-AMOUNT     PIC 9(5)V99.
       01 WS-NET-REVENUE       PIC 9(5)V99.
       01 WS-DISPLAY-HT        PIC Z(4)9.99.
       01 WS-DISPLAY-TVA       PIC Z(4)9.99.
       01 WS-DISPLAY-TTC       PIC Z(5)9.99.
       01 WS-DISPLAY-URSSAF    PIC Z(4)9.99.
       01 WS-DISPLAY-NET       PIC Z(4)9.99.

       PROCEDURE DIVISION.
       MAIN-LOGIC.
      *    Read CGI environment
           ACCEPT WS-CONTENT-LENGTH
               FROM ENVIRONMENT "CONTENT_LENGTH"
           ACCEPT WS-POST-DATA FROM STANDARD-INPUT

      *    Parse form data
           PERFORM PARSE-FORM-DATA

      *    Calculate with exact decimal arithmetic
           COMPUTE WS-AMOUNT-TVA =
               WS-AMOUNT-HT * WS-TVA-RATE
           ADD WS-AMOUNT-HT WS-AMOUNT-TVA
               GIVING WS-AMOUNT-TTC
           COMPUTE WS-URSSAF-AMOUNT =
               WS-AMOUNT-HT * WS-URSSAF-RATE
           SUBTRACT WS-URSSAF-AMOUNT FROM WS-AMOUNT-HT
               GIVING WS-NET-REVENUE

      *    Format for display
           MOVE WS-AMOUNT-HT TO WS-DISPLAY-HT
           MOVE WS-AMOUNT-TVA TO WS-DISPLAY-TVA
           MOVE WS-AMOUNT-TTC TO WS-DISPLAY-TTC
           MOVE WS-URSSAF-AMOUNT TO WS-DISPLAY-URSSAF
           MOVE WS-NET-REVENUE TO WS-DISPLAY-NET

      *    Output HTTP headers + HTML
           PERFORM OUTPUT-HTML

           STOP RUN.

       OUTPUT-HTML.
           DISPLAY "Content-Type: text/html"
           DISPLAY ""
           DISPLAY "<div class='invoice-summary'>"
           DISPLAY "  <h2>INVOICE CREATED</h2>"
           DISPLAY "  <table>"
           DISPLAY "  <tr><td>Client</td>"
           DISPLAY "      <td>" WS-CLIENT-NAME "</td></tr>"
           DISPLAY "  <tr><td>Total H.T.</td>"
           DISPLAY "      <td>" WS-DISPLAY-HT " EUR</td></tr>"
           DISPLAY "  <tr><td>TVA (20%)</td>"
           DISPLAY "      <td>" WS-DISPLAY-TVA " EUR</td></tr>"
           DISPLAY "  <tr><td>Total T.T.C.</td>"
           DISPLAY "      <td>" WS-DISPLAY-TTC " EUR</td></tr>"
           DISPLAY "  <tr><td>URSSAF (22%)</td>"
           DISPLAY "      <td>" WS-DISPLAY-URSSAF " EUR</td></tr>"
           DISPLAY "  <tr><td>Net Revenue</td>"
           DISPLAY "      <td>" WS-DISPLAY-NET " EUR</td></tr>"
           DISPLAY "  </table>"
           DISPLAY "  <a href='/pdf/INV-2026-0042.pdf'"
           DISPLAY "     class='btn'>DOWNLOAD PDF</a>"
           DISPLAY "</div>".

       PARSE-FORM-DATA.
      *    Split POST data on & and = delimiters
      *    Extract client name and amount
      *    (simplified — full version in cgi-utils.cob)
           MOVE "Dupont SARL" TO WS-CLIENT-NAME
           MOVE 2000.00 TO WS-AMOUNT-HT.
```

### CGI Utilities — Form Parser

```cobol
       IDENTIFICATION DIVISION.
       PROGRAM-ID. CGI-UTILS.

       DATA DIVISION.
       WORKING-STORAGE SECTION.
       01 WS-RAW-INPUT         PIC X(2000).
       01 WS-PAIR-COUNT        PIC 99.
       01 WS-PAIRS.
           05 WS-PAIR OCCURS 20 TIMES.
               10 WS-KEY       PIC X(30).
               10 WS-VALUE     PIC X(100).
       01 WS-TEMP              PIC X(200).
       01 WS-IDX               PIC 99.

       PROCEDURE DIVISION.

       PARSE-CGI-INPUT.
      *    Split raw input "key1=val1&key2=val2" into pairs
           MOVE 0 TO WS-PAIR-COUNT
           UNSTRING WS-RAW-INPUT
               DELIMITED BY "&"
               INTO WS-TEMP
               TALLYING IN WS-PAIR-COUNT
           END-UNSTRING

      *    For each pair, split on "="
           PERFORM VARYING WS-IDX FROM 1 BY 1
               UNTIL WS-IDX > WS-PAIR-COUNT
               UNSTRING WS-TEMP
                   DELIMITED BY "="
                   INTO WS-KEY(WS-IDX)
                         WS-VALUE(WS-IDX)
               END-UNSTRING
               PERFORM URL-DECODE-VALUE
           END-PERFORM.

       URL-DECODE-VALUE.
      *    Replace + with space
           INSPECT WS-VALUE(WS-IDX)
               REPLACING ALL "+" BY " "
      *    Handle %XX sequences
      *    (full hex decode implementation here)
           CONTINUE.
```

---

## PostScript — Invoice Template

### Complete Invoice Layout

```postscript
%!PS-Adobe-3.0
%%Title: COBILL Invoice
%%Creator: COBILL PostScript Engine
%%BoundingBox: 0 0 595 842
%%Pages: 1
%%EndComments

%%Page: 1 1

% ============================================================
% HEADER — Company info + Invoice number
% ============================================================

% Company name
/Helvetica-Bold findfont 22 scalefont setfont
0.1 0.1 0.4 setrgbcolor
72 780 moveto (COBILL) show

% Tagline
/Helvetica findfont 9 scalefont setfont
0.5 setgray
72 766 moveto (COBOL-Powered Invoicing) show

% Invoice label
/Helvetica-Bold findfont 16 scalefont setfont
0 setgray
420 780 moveto (FACTURE) show

% Invoice number
/Helvetica findfont 13 scalefont setfont
420 763 moveto (#2026-0042) show

% Separator line
0.7 setgray
72 752 moveto 523 752 lineto 0.5 setlinewidth stroke

% ============================================================
% FROM / TO blocks
% ============================================================
0 setgray
/Helvetica-Bold findfont 10 scalefont setfont
72 730 moveto (FROM:) show
350 730 moveto (TO:) show

/Helvetica findfont 10 scalefont setfont

% Sender
72 715 moveto (Frederic Bourouliou) show
72 702 moveto (123 Rue de la Paix) show
72 689 moveto (75001 Paris, France) show
72 676 moveto (SIRET: 123 456 789 00012) show

% Client
350 715 moveto (Dupont SARL) show
350 702 moveto (45 Avenue des Champs-Elysees) show
350 689 moveto (75008 Paris, France) show
350 676 moveto (SIRET: 987 654 321 00034) show

% Dates
/Helvetica findfont 9 scalefont setfont
72 655 moveto (Date: 25/03/2026) show
72 643 moveto (Due: 25/04/2026) show

% ============================================================
% TABLE — Line items
% ============================================================

% Table header background
0.93 setgray
72 620 505 -18 rectfill

% Table header text
0 setgray
/Helvetica-Bold findfont 10 scalefont setfont
78 607 moveto (Description) show
320 607 moveto (Qty) show
390 607 moveto (Rate) show
475 607 moveto (Total) show

% Header underline
0.7 setgray
72 600 moveto 523 600 lineto 0.3 setlinewidth stroke

% Table rows
0 setgray
/Helvetica findfont 10 scalefont setfont

% Row 1
78 583 moveto (Web development) show
320 583 moveto (5.00) show
390 583 moveto (300.00) show
470 583 moveto (1,500.00) show

% Row separator
0.9 setgray
72 576 moveto 523 576 lineto 0.2 setlinewidth stroke

% Row 2
0 setgray
78 563 moveto (UI/UX consulting) show
320 563 moveto (2.00) show
390 563 moveto (250.00) show
475 563 moveto (500.00) show

% ============================================================
% TOTALS
% ============================================================

% Totals separator
0.5 setgray
380 540 moveto 523 540 lineto 0.5 setlinewidth stroke

0 setgray
/Helvetica findfont 10 scalefont setfont
380 525 moveto (Total H.T.) show
470 525 moveto (2,000.00) show

380 510 moveto (TVA \(20%\)) show
475 510 moveto (400.00) show

% TTC line
0.3 setgray
380 500 moveto 523 500 lineto 0.5 setlinewidth stroke

/Helvetica-Bold findfont 11 scalefont setfont
0 setgray
380 485 moveto (Total TTC) show
460 485 moveto (2,400.00 EUR) show

% ============================================================
% LEGAL MENTIONS
% ============================================================

0.4 setgray
/Helvetica findfont 8 scalefont setfont
72 420 moveto (TVA non applicable, art. 293 B du CGI) show
72 400 moveto (Paiement par virement bancaire sous 30 jours) show
72 388 moveto (IBAN: FR76 XXXX XXXX XXXX XXXX XXXX XXX) show
72 376 moveto (BIC: XXXXXXXX) show

72 350 moveto (En cas de retard de paiement, une penalite de 3x le taux) show
72 338 moveto (d'interet legal sera appliquee. Indemnite forfaitaire) show
72 326 moveto (de recouvrement: 40 EUR.) show

% ============================================================
% FOOTER
% ============================================================

0.6 setgray
72 60 moveto 523 60 lineto 0.3 setlinewidth stroke
/Helvetica findfont 8 scalefont setfont
72 48 moveto (Powered by COBILL  |  COBOL-Powered Invoicing  |  cobill.dev) show

showpage

%%EOF
```

---

## HTMX — Frontend

### Main Application Shell

```html
<!DOCTYPE html>
<html lang="fr">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>COBILL — Invoice Management System</title>
    <link rel="stylesheet" href="/css/common.css">
    <link rel="stylesheet" href="/css/terminal.css" id="theme">
    <script src="/js/htmx.min.js"></script>
</head>
<body class="theme-terminal">

    <header>
        <div class="header-title">
            COBILL v1.0 &mdash; INVOICE MANAGEMENT SYSTEM
        </div>
        <div class="header-bar">
            ════════════════════════════════════════════════════
        </div>
    </header>

    <nav>
        <button hx-get="/cgi-bin/cobill/invoice?action=new"
                hx-target="#content"
                hx-swap="innerHTML">[F1] NEW INVOICE</button>

        <button hx-get="/cgi-bin/cobill/client?action=list"
                hx-target="#content"
                hx-swap="innerHTML">[F2] CLIENTS</button>

        <button hx-get="/cgi-bin/cobill/dashboard"
                hx-target="#content"
                hx-swap="innerHTML">[F3] DASHBOARD</button>

        <button hx-post="/cgi-bin/cobill/auth?action=logout"
                hx-target="body">[F4] LOGOUT</button>

        <button onclick="toggleTheme()" class="theme-toggle">
            [F5] THEME
        </button>
    </nav>

    <main id="content">
        <!-- HTMX injects COBOL-generated HTML here -->
        <p>Welcome to COBILL. Select an option above.</p>
    </main>

    <footer>
        <span>STATUS: READY</span>
        <span id="vat-bar"
              hx-get="/cgi-bin/cobill/dashboard?action=vat-bar"
              hx-trigger="load"
              hx-swap="innerHTML"></span>
    </footer>

    <script>
    function toggleTheme() {
        var link = document.getElementById('theme');
        if (link.href.includes('terminal')) {
            link.href = '/css/modern.css';
        } else {
            link.href = '/css/terminal.css';
        }
    }
    </script>

</body>
</html>
```

### Invoice Creation Form (returned by COBOL)

```html
<!-- This HTML is generated by invoice.cob when action=new -->
<form hx-post="/cgi-bin/cobill/invoice?action=create"
      hx-target="#content"
      hx-swap="innerHTML">

    <h2>CREATE NEW INVOICE</h2>

    <div class="form-row">
        <label>CLIENT......:</label>
        <select name="client_id"
                hx-get="/cgi-bin/cobill/client?action=options"
                hx-trigger="load"
                hx-swap="innerHTML">
            <!-- Options populated by HTMX -->
        </select>
    </div>

    <div class="form-row">
        <label>DATE........:</label>
        <input type="date" name="date" value="2026-03-25">
    </div>

    <div class="form-row">
        <label>DUE DATE....: </label>
        <input type="date" name="due_date" value="2026-04-25">
    </div>

    <div class="form-row">
        <label>TVA RATE....:</label>
        <select name="tva_rate">
            <option value="0.20">20%</option>
            <option value="0.10">10%</option>
            <option value="0.055">5.5%</option>
            <option value="0.00">0% (art. 293 B)</option>
        </select>
    </div>

    <h3>LINE ITEMS</h3>
    <table class="line-items">
        <thead>
            <tr>
                <th>#</th>
                <th>DESCRIPTION</th>
                <th>QTY</th>
                <th>RATE</th>
            </tr>
        </thead>
        <tbody>
            <tr>
                <td>1</td>
                <td><input type="text" name="desc1"></td>
                <td><input type="number" name="qty1" step="0.01"></td>
                <td><input type="number" name="rate1" step="0.01"></td>
            </tr>
            <tr>
                <td>2</td>
                <td><input type="text" name="desc2"></td>
                <td><input type="number" name="qty2" step="0.01"></td>
                <td><input type="number" name="rate2" step="0.01"></td>
            </tr>
            <tr>
                <td>3</td>
                <td><input type="text" name="desc3"></td>
                <td><input type="number" name="qty3" step="0.01"></td>
                <td><input type="number" name="rate3" step="0.01"></td>
            </tr>
        </tbody>
    </table>

    <div class="form-actions">
        <button type="submit" class="btn-primary">
            [GENERATE PDF]
        </button>
        <button type="submit" name="action" value="draft" class="btn">
            [SAVE DRAFT]
        </button>
        <button type="button"
                hx-get="/cgi-bin/cobill/invoice?action=list"
                hx-target="#content"
                class="btn">
            [CANCEL]
        </button>
    </div>
</form>
```

### Terminal CSS Theme (excerpt)

```css
/* terminal.css — IBM 3270 green-on-black theme */

:root {
    --bg: #0a0a0a;
    --fg: #33ff33;
    --fg-dim: #1a8c1a;
    --fg-bright: #66ff66;
    --border: #1a8c1a;
    --input-bg: #111;
    --btn-bg: #1a8c1a;
    --btn-fg: #0a0a0a;
    --danger: #ff3333;
    --warning: #ffcc00;
}

body.theme-terminal {
    background-color: var(--bg);
    color: var(--fg);
    font-family: 'IBM Plex Mono', 'Courier New', monospace;
    font-size: 14px;
    line-height: 1.4;
}

/* CRT glow effect */
body.theme-terminal * {
    text-shadow: 0 0 5px rgba(51, 255, 51, 0.3);
}

/* Scan lines overlay */
body.theme-terminal::after {
    content: "";
    position: fixed;
    top: 0;
    left: 0;
    width: 100%;
    height: 100%;
    pointer-events: none;
    background: repeating-linear-gradient(
        transparent,
        transparent 2px,
        rgba(0, 0, 0, 0.1) 2px,
        rgba(0, 0, 0, 0.1) 4px
    );
    z-index: 9999;
}

header {
    border-bottom: 1px solid var(--border);
    padding: 10px 20px;
}

nav button {
    background: none;
    border: 1px solid var(--border);
    color: var(--fg);
    padding: 4px 12px;
    cursor: pointer;
    font-family: inherit;
    font-size: inherit;
}

nav button:hover {
    background: var(--btn-bg);
    color: var(--btn-fg);
}

input, select {
    background: var(--input-bg);
    border: 1px solid var(--border);
    color: var(--fg);
    padding: 4px 8px;
    font-family: inherit;
    font-size: inherit;
}

table {
    border-collapse: collapse;
    width: 100%;
}

th, td {
    border: 1px solid var(--border);
    padding: 4px 8px;
    text-align: left;
}

th {
    background: var(--fg-dim);
    color: var(--bg);
}

.btn-primary {
    background: var(--fg);
    color: var(--bg);
    border: none;
    padding: 8px 16px;
    font-weight: bold;
    cursor: pointer;
}
```
