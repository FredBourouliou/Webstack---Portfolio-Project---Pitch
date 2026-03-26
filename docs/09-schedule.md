# Schedule — 27 Days

## Overview

| Week | Focus | Goal |
|------|-------|------|
| Week 1 (Days 1-7) | Foundations | COBOL + CGI + HTMX working, client + invoice CRUD |
| Week 2 (Days 8-14) | PDF Engine + Core | PostScript PDF generation, full invoicing flow |
| Week 3 (Days 15-21) | Business Logic | URSSAF, VAT tracking, dashboard, auth |
| Week 4 (Days 22-27) | Polish + Deploy | Production deployment, landing page, pitch prep |

---

## Week 1 — Foundations (Days 1-7)

**Goal:** Prove the stack works. Build the basic CRUD app.

| Day | Task | Deliverable | Risk Validation |
|-----|------|-------------|-----------------|
| **1** | Set up development environment | GnuCOBOL, Apache, Ghostscript installed and working on target OS | GnuCOBOL compiles ✓ |
| **2** | COBOL CGI "Hello World" | A COBOL binary that serves HTML via Apache mod_cgi | CGI integration ✓ |
| **3** | HTMX integration | Form submission → COBOL processes → HTMX injects response | Full loop ✓ |
| **4** | Data model + ISAM files | Define record structures for clients and invoices. COBOL READ/WRITE working | Data persistence ✓ |
| **5** | Client CRUD | Create, read, update, delete clients via HTMX + COBOL | — |
| **6** | Invoice creation + calculation | Invoice form with line items. COBOL computes HT/TVA/TTC | Core engine ✓ |
| **7** | Invoice listing + detail view | List all invoices, click to view detail | — |

**Week 1 Milestone:** A working web app where you can create clients, create invoices with automatic calculations, and list them. No PDF yet.

---

## Week 2 — PDF Engine + Core Features (Days 8-14)

**Goal:** Add PostScript PDF generation. Complete the invoicing flow.

| Day | Task | Deliverable | Risk Validation |
|-----|------|-------------|-----------------|
| **8** | PostScript crash course | Hand-written `.ps` invoice template renders as PDF via Ghostscript | PostScript ✓ |
| **9** | Dynamic PostScript from COBOL | COBOL reads invoice data → generates `.ps` with real values → converts to PDF | Dynamic PDF ✓ |
| **10** | End-to-end PDF flow | Create invoice → COBOL calculates → PostScript generates → PDF downloads | Full pipeline ✓ |
| **11** | Invoice numbering | Auto-increment YYYY-NNNN format. Sequential, gap-free | — |
| **12** | Invoice status workflow | Draft → Sent → Paid → Overdue. Mark as paid, detect overdue | — |
| **13** | Retro terminal CSS theme | IBM 3270 green-on-black theme applied to all pages | — |
| **14** | Testing + bug fixes | End-to-end testing of all features. Fix edge cases | — |

**Week 2 Milestone:** Full invoicing pipeline working — create client, create invoice, download pixel-perfect PDF. Terminal theme applied.

---

## Week 3 — Business Logic + Dashboard (Days 15-21)

**Goal:** Add the features that make COBILL genuinely useful for freelancers.

| Day | Task | Deliverable |
|-----|------|-------------|
| **15** | URSSAF calculator | Configure activity type. Auto-calculate contributions per invoice and year-to-date |
| **16** | VAT threshold tracker | Progress bar showing current revenue vs. threshold. Visual alerts at 80%/90%/100% |
| **17** | Revenue dashboard | Monthly bar chart, YTD summary table, unpaid invoices list |
| **18** | Modern UI theme | Clean, professional CSS theme. Toggle switch: retro ↔ modern |
| **19** | Responsive design | All pages work on mobile (min-width: 320px) |
| **20** | Authentication | Login page, session cookies, session ISAM store, logout |
| **21** | Testing + bug fixes | Full regression testing. Fix all known issues |

**Week 3 Milestone:** Business-ready app with URSSAF tracking, VAT alerts, dashboard, dual themes, and authentication.

---

## Week 4 — Polish + Deploy + Pitch (Days 22-27)

**Goal:** Ship it. Present it.

| Day | Task | Deliverable |
|-----|------|-------------|
| **22** | Deploy to production VPS | Apache + COBOL binaries + Ghostscript running on public URL |
| **23** | Landing page | Product presentation page with feature list, pricing table, screenshots |
| **24** | End-to-end testing on production | All features verified on live server. SSL configured |
| **25** | Write README + technical docs | Repository fully documented for GitHub |
| **26** | Prepare pitch slides | Google Slides presentation (max 10 min). Key slides: problem, solution, demo, tech, commercial |
| **27** | Rehearse pitch + final polish | Practice delivery. Time it. Fix last-minute issues |

**Week 4 Milestone:** Live production URL. Complete documentation. Pitch-ready.

---

## Critical Path

```
Day 1: Environment    ──→ Day 2: CGI works ──→ Day 3: HTMX loop
                                                        │
                                                        ▼
                              Day 8: PostScript ──→ Day 10: Full PDF pipeline
                                                        │
                                                        ▼
                                                  Day 14: Complete invoicing
                                                        │
                                                        ▼
                                                  Day 21: Business features
                                                        │
                                                        ▼
                                                  Day 22: Deploy
                                                        │
                                                        ▼
                                                  Day 27: Pitch
```

**Critical risks are front-loaded:** If CGI doesn't work by Day 2 or PostScript by Day 8, there is still time to pivot. If everything works by Day 14, the project is on track.

---

## Contingency Plan

If behind schedule:

| Situation | Action |
|-----------|--------|
| CGI doesn't work by Day 3 | Use thin Python wrapper to invoke COBOL binaries |
| PostScript too complex by Day 9 | Use a simpler text-based PDF approach or reduce template complexity |
| Behind by end of Week 2 | Cut Week 3 scope: drop auth and modern theme. Focus on URSSAF + dashboard |
| Behind by end of Week 3 | Cut landing page. Deploy with minimal documentation. Focus on pitch |

**Non-negotiable deliverables:** Invoice creation with COBOL calculation + PDF generation with PostScript + working demo on a live URL.
