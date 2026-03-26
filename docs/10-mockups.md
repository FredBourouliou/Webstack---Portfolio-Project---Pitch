# Mock-ups

## UI Design Philosophy

COBILL features two themes:

1. **Retro Terminal** (default) — IBM 3270 green-on-black mainframe aesthetic. Monospace font, block characters, scan lines. Reinforces the COBOL narrative.
2. **Modern** (toggle) — Clean, professional, white-background design. Proves the app is production-ready, not just a gimmick.

Both themes share the same HTML structure; only CSS changes.

---

## Retro Terminal Theme

### Main Navigation + Invoice Form

```
┌──────────────────────────────────────────────────────────────┐
│  COBILL v1.0              INVOICE MANAGEMENT SYSTEM          │
│  ════════════════════════════════════════════════════════════ │
│                                                               │
│  [F1] NEW INVOICE  [F2] CLIENTS  [F3] DASHBOARD  [F4] LOGOUT│
│  ──────────────────────────────────────────────────────────── │
│                                                               │
│  CREATE NEW INVOICE                                           │
│  ─────────────────                                            │
│                                                               │
│  CLIENT......: [Dupont SARL_____________]                     │
│  DATE........: [2026-03-25]                                   │
│  DUE DATE....: [2026-04-25]                                   │
│  TVA RATE....: [20%___]                                       │
│                                                               │
│  LINE ITEMS:                                                  │
│  ┌─────┬────────────────────────┬────────┬───────┬──────────┐│
│  │  #  │ DESCRIPTION            │ QTY    │ RATE  │ TOTAL    ││
│  ├─────┼────────────────────────┼────────┼───────┼──────────┤│
│  │  1  │ Web development        │   5.00 │300.00 │ 1,500.00 ││
│  │  2  │ UI/UX consulting       │   2.00 │250.00 │   500.00 ││
│  │  3  │ [________________]     │ [____] │[____] │     0.00 ││
│  ├─────┼────────────────────────┼────────┼───────┼──────────┤│
│  │     │                        │        │  H.T. │ 2,000.00 ││
│  │     │                        │        │  TVA  │   400.00 ││
│  │     │                        │        │  TTC  │ 2,400.00 ││
│  └─────┴────────────────────────┴────────┴───────┴──────────┘│
│                                                               │
│  URSSAF (22%).: 440.00 EUR                                    │
│  NET REVENUE..: 1,560.00 EUR                                  │
│                                                               │
│  [GENERATE PDF]  [SAVE DRAFT]  [CANCEL]                       │
│                                                               │
│  ──────────────────────────────────────────────────────────── │
│  STATUS: READY          INVOICES THIS MONTH: 12               │
│  VAT THRESHOLD: ████████████░░░░░░ 67% (24,560 / 36,800 EUR)│
└──────────────────────────────────────────────────────────────┘
```

### Invoice List

```
┌──────────────────────────────────────────────────────────────┐
│  COBILL v1.0              INVOICE MANAGEMENT SYSTEM          │
│  ════════════════════════════════════════════════════════════ │
│                                                               │
│  [F1] NEW INVOICE  [F2] CLIENTS  [F3] DASHBOARD  [F4] LOGOUT│
│  ──────────────────────────────────────────────────────────── │
│                                                               │
│  INVOICES                          SEARCH: [____________]     │
│  ────────                                                     │
│                                                               │
│  ┌──────────┬──────────────┬────────────┬──────────┬────────┐│
│  │ NUMBER   │ CLIENT       │ DATE       │ AMOUNT   │ STATUS ││
│  ├──────────┼──────────────┼────────────┼──────────┼────────┤│
│  │ 2026-012 │ Dupont SARL  │ 2026-03-25 │ 2,400.00 │ ● PAID ││
│  │ 2026-011 │ Martin & Co  │ 2026-03-20 │ 1,800.00 │ ● SENT ││
│  │ 2026-010 │ Durand SAS   │ 2026-03-15 │ 3,600.00 │ ◌ OVER ││
│  │ 2026-009 │ Petit SARL   │ 2026-03-10 │   750.00 │ ● PAID ││
│  │ 2026-008 │ Dupont SARL  │ 2026-03-01 │ 4,200.00 │ ◌ OVER ││
│  └──────────┴──────────────┴────────────┴──────────┴────────┘│
│                                                               │
│  PAGE 1/3    [PREV]  [NEXT]                                   │
│                                                               │
│  ──────────────────────────────────────────────────────────── │
│  5 INVOICES DISPLAYED    TOTAL OUTSTANDING: 5,400.00 EUR     │
└──────────────────────────────────────────────────────────────┘
```

### Dashboard

```
┌──────────────────────────────────────────────────────────────┐
│  COBILL v1.0              REVENUE DASHBOARD                  │
│  ════════════════════════════════════════════════════════════ │
│                                                               │
│  [F1] NEW INVOICE  [F2] CLIENTS  [F3] DASHBOARD  [F4] LOGOUT│
│  ──────────────────────────────────────────────────────────── │
│                                                               │
│  YEAR 2026                    ACTIVITY: CONSULTING (BNC)      │
│  ─────────                                                    │
│                                                               │
│  MONTHLY REVENUE (EUR H.T.)                                   │
│                                                               │
│  JAN │ ████████████████████ 4,200.00                          │
│  FEB │ ██████████████████████████ 5,800.00                    │
│  MAR │ ████████████████ 3,400.00                              │
│                                                               │
│  ──────────────────────────────────────────────────────────── │
│                                                               │
│  YEAR TO DATE                                                 │
│  ┌──────────────────────┬──────────────┐                      │
│  │ Total H.T.           │  13,400.00   │                      │
│  │ Total TVA collected  │   2,680.00   │                      │
│  │ Total TTC            │  16,080.00   │                      │
│  │ URSSAF due (22%)     │   2,948.00   │                      │
│  │ Net revenue          │  10,452.00   │                      │
│  └──────────────────────┴──────────────┘                      │
│                                                               │
│  VAT THRESHOLD                                                │
│  ████████████░░░░░░░░░░░░ 36% (13,400 / 36,800 EUR)         │
│  Estimated crossing: AUGUST 2026                              │
│                                                               │
│  UNPAID INVOICES: 3                                           │
│  ┌──────────┬──────────────┬──────────┬──────────────────┐   │
│  │ 2026-010 │ Durand SAS   │ 3,600.00 │ ⚠ 10 DAYS LATE  │   │
│  │ 2026-008 │ Dupont SARL  │ 4,200.00 │ ⚠ 24 DAYS LATE  │   │
│  │ 2026-011 │ Martin & Co  │ 1,800.00 │   DUE IN 5 DAYS │   │
│  └──────────┴──────────────┴──────────┴──────────────────┘   │
│                                                               │
│  ──────────────────────────────────────────────────────────── │
│  TOTAL OUTSTANDING: 9,600.00 EUR                             │
└──────────────────────────────────────────────────────────────┘
```

### Client Management

```
┌──────────────────────────────────────────────────────────────┐
│  COBILL v1.0              CLIENT MANAGEMENT                  │
│  ════════════════════════════════════════════════════════════ │
│                                                               │
│  [F1] NEW INVOICE  [F2] CLIENTS  [F3] DASHBOARD  [F4] LOGOUT│
│  ──────────────────────────────────────────────────────────── │
│                                                               │
│  CLIENTS                       [+ NEW CLIENT]                 │
│  ───────                                                      │
│                                                               │
│  ┌──────────────┬───────────────────┬────────────┬──────────┐│
│  │ NAME         │ SIRET             │ INVOICES   │ TOTAL    ││
│  ├──────────────┼───────────────────┼────────────┼──────────┤│
│  │ Dupont SARL  │ 123 456 789 00012 │         8  │ 18,400   ││
│  │ Martin & Co  │ 987 654 321 00034 │         3  │  5,400   ││
│  │ Durand SAS   │ 456 789 123 00056 │         5  │ 12,300   ││
│  │ Petit SARL   │ 321 654 987 00078 │         2  │  1,500   ││
│  └──────────────┴───────────────────┴────────────┴──────────┘│
│                                                               │
│  ──────────────────────────────────────────────────────────── │
│  4 CLIENTS REGISTERED                                        │
└──────────────────────────────────────────────────────────────┘
```

### Login Screen

```
┌──────────────────────────────────────────────────────────────┐
│                                                               │
│                                                               │
│                                                               │
│                    ╔═══════════════════════╗                   │
│                    ║                       ║                   │
│                    ║   C O B I L L  v1.0   ║                   │
│                    ║                       ║                   │
│                    ║  COBOL-POWERED        ║                   │
│                    ║  INVOICING SYSTEM     ║                   │
│                    ║                       ║                   │
│                    ║  USER...: [________]  ║                   │
│                    ║  PASS...: [________]  ║                   │
│                    ║                       ║                   │
│                    ║     [  LOG IN  ]      ║                   │
│                    ║                       ║                   │
│                    ╚═══════════════════════╝                   │
│                                                               │
│         "The same technology your bank trusts."               │
│                                                               │
│                                                               │
└──────────────────────────────────────────────────────────────┘
```

---

## PDF Invoice (PostScript-generated)

```
┌─────────────────────────────────────────────────┐
│                                                  │
│  COBILL                          FACTURE         │
│  ──────                          #2026-0042      │
│                                                  │
│  Frédéric Bourouliou             Date: 25/03/26  │
│  123 Rue de la Paix              Échéance: 25/04 │
│  75001 Paris                                     │
│  SIRET: 123 456 789 00012                        │
│                                                  │
│  CLIENT:                                         │
│  Dupont SARL                                     │
│  45 Avenue des Champs-Élysées                    │
│  75008 Paris                                     │
│  SIRET: 123 456 789 00012                        │
│                                                  │
│  ─────────────────────────────────────────────── │
│  Description              Qty    Rate     Total  │
│  ─────────────────────────────────────────────── │
│  Web development          5.00   300.00  1500.00 │
│  UI/UX consulting         2.00   250.00   500.00 │
│  ─────────────────────────────────────────────── │
│                                                  │
│                            Total H.T.  2,000.00  │
│                            TVA (20%)     400.00  │
│                           ───────────────────    │
│                            Total TTC   2,400.00  │
│                                                  │
│  ─────────────────────────────────────────────── │
│                                                  │
│  TVA non applicable, art. 293 B du CGI           │
│                                                  │
│  Paiement par virement bancaire sous 30 jours    │
│  IBAN: FR76 XXXX XXXX XXXX XXXX XXXX XXX        │
│  BIC: XXXXXXXX                                   │
│                                                  │
│  ─────────────────────────────────────────────── │
│  En cas de retard de paiement, une pénalité de   │
│  3x le taux d'intérêt légal sera appliquée.      │
│  Indemnité forfaitaire de recouvrement: 40 EUR.  │
│  ─────────────────────────────────────────────── │
│                                                  │
│  Powered by COBILL — COBOL-Powered Invoicing     │
└─────────────────────────────────────────────────┘
```

---

## CSS Theme Guidelines

### Retro Terminal Theme

```css
/* Core colors */
--bg: #0a0a0a;
--fg: #33ff33;
--fg-dim: #1a8c1a;
--border: #1a8c1a;
--highlight: #66ff66;

/* Typography */
font-family: 'IBM Plex Mono', 'Courier New', monospace;
font-size: 14px;
line-height: 1.4;

/* Effects */
text-shadow: 0 0 5px rgba(51, 255, 51, 0.5);  /* CRT glow */
```

### Modern Theme

```css
/* Core colors */
--bg: #ffffff;
--fg: #1a1a2e;
--accent: #0f3460;
--border: #e0e0e0;
--highlight: #16537e;

/* Typography */
font-family: 'Inter', -apple-system, sans-serif;
font-size: 15px;
line-height: 1.6;
```
