# Key Features

## Feature Roadmap

Features are organized by development phase, aligned with the [27-day schedule](09-schedule.md).

---

## MVP — Weeks 1-2

The minimum viable product: a working invoicing app that creates invoices and generates PDFs.

### Client Management
- [ ] Create a new client (name, address, SIRET, email)
- [ ] Edit existing client information
- [ ] List all clients with search
- [ ] Delete a client (with confirmation)

### Invoice Creation
- [ ] Create a new invoice linked to a client
- [ ] Add multiple line items (description, quantity, unit rate)
- [ ] Automatic calculation: line total = quantity × rate
- [ ] Automatic calculation: subtotal (H.T.)
- [ ] Automatic calculation: TVA amount (H.T. × TVA rate)
- [ ] Automatic calculation: total (T.T.C.)
- [ ] All calculations use COBOL decimal arithmetic (PIC 9(5)V99)

### PDF Generation
- [ ] PostScript template with professional layout
- [ ] Dynamic data injection (client info, line items, totals)
- [ ] Ghostscript conversion to PDF
- [ ] PDF download link after invoice creation
- [ ] Legally compliant French invoice format (SIRET, TVA mention, payment terms)

### Invoice Management
- [ ] List all invoices (sortable by date, client, amount)
- [ ] View invoice detail
- [ ] Search invoices by number, client, or date range

### UI
- [ ] Retro terminal theme (IBM 3270 green-on-black)
- [ ] HTMX-powered navigation (no full page reloads)
- [ ] Responsive layout (readable on mobile)

---

## Core — Week 3

Business logic that makes COBILL genuinely useful for freelancers.

### URSSAF Calculator
- [ ] Configure activity type (BNC services, BIC vente, BIC services, CIPAV)
- [ ] Automatic URSSAF rate application per activity type
- [ ] Per-invoice URSSAF contribution display
- [ ] Quarterly URSSAF summary (matches real URSSAF declaration periods)

### VAT Threshold Tracker
- [ ] Real-time progress bar: current revenue vs. threshold (€36,800 or €91,900)
- [ ] Visual alert when approaching threshold (80%, 90%, 100%)
- [ ] Estimated threshold crossing date based on current pace
- [ ] Automatic switch from "TVA non applicable, art. 293 B du CGI" to TVA-inclusive invoices

### Revenue Dashboard
- [ ] Monthly revenue bar chart (current year)
- [ ] Year-to-date summary (H.T., TVA, TTC, URSSAF, net revenue)
- [ ] Unpaid invoices list with aging (30/60/90 days)
- [ ] Revenue comparison (current month vs. previous month)

### Invoice Workflow
- [ ] Invoice status: Draft → Sent → Paid → Overdue
- [ ] Mark invoice as paid (with payment date)
- [ ] Automatic overdue detection (past due date + not paid)
- [ ] Duplicate invoice (for recurring clients)

### Theming
- [ ] Modern UI theme (clean, professional)
- [ ] Theme toggle: retro terminal ↔ modern (CSS-only switch)

---

## Polish — Week 4

Final touches before deployment and pitch.

### Quality of Life
- [ ] Invoice auto-numbering (YYYY-NNNN format, auto-increment)
- [ ] Client auto-complete in invoice form
- [ ] Default payment terms (configurable: 30 days, 45 days, etc.)
- [ ] User profile setup (name, address, SIRET, IBAN for invoice header)

### Security
- [ ] Basic authentication (login page with username/password)
- [ ] Session management via cookie + ISAM session store
- [ ] Session expiry after 24 hours of inactivity

### Deployment
- [ ] Production deployment on VPS (Apache + COBOL binaries + Ghostscript)
- [ ] SSL/TLS via Let's Encrypt
- [ ] Landing page (product presentation, feature list, pricing table)

### Documentation
- [ ] README with setup instructions
- [ ] Technical documentation (architecture, data model)
- [ ] Pitch slides (Google Slides, max 10 minutes)

---

## Feature Priority Matrix

| Feature | User Value | Technical Risk | Priority |
|---------|-----------|----------------|----------|
| Invoice creation + calculation | Critical | Low | P0 |
| PDF generation (PostScript) | Critical | Medium | P0 |
| Client management | High | Low | P0 |
| Invoice listing | High | Low | P0 |
| URSSAF calculator | High | Low | P1 |
| VAT threshold tracker | High | Low | P1 |
| Revenue dashboard | Medium | Low | P1 |
| Invoice status workflow | Medium | Low | P1 |
| Authentication | Medium | Medium | P2 |
| Theme toggle | Low | Low | P2 |
| Landing page | Low | Low | P2 |

**Rule:** All P0 features must be complete before moving to P1. All P1 before P2. If time runs short, P2 features are cut first.
