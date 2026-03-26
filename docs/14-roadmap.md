# Roadmap

## Post-Holberton Evolution Plan

---

## v1.0 — Holberton Delivery (Day 27)

The baseline product delivered for the portfolio project.

### Included
- Client management (CRUD)
- Invoice creation with COBOL decimal calculations
- PDF generation via PostScript + Ghostscript
- URSSAF contribution calculator
- VAT threshold tracker
- Revenue dashboard
- Retro terminal + modern UI themes
- Basic authentication
- Deployed on a live VPS

---

## v1.1 — Quality of Life (Month 1-2 after Holberton)

Improvements based on real-world usage and initial user feedback.

### Planned Features

| Feature | Description |
|---------|-------------|
| **Email notifications** | Send invoice PDF as email attachment via SMTP. Notify on payment due, overdue. |
| **Multi-currency** | Support EUR, USD, GBP. Exchange rate stored per invoice. |
| **CSV export** | Export invoice list and revenue data as CSV for accountants. |
| **Quote generation** | Create quotes (devis) with the same engine. Convert quote → invoice. |
| **PDF customization** | Multiple PostScript templates (minimalist, classic, modern). User selects preferred style. |
| **Recurring invoices** | Mark invoices as recurring (monthly, quarterly). Auto-generate on schedule. |

### Technical Improvements

| Improvement | Description |
|-------------|-------------|
| **Input validation** | Comprehensive server-side validation with user-friendly error messages |
| **Error pages** | Custom 404, 500 error pages in terminal theme |
| **Logging** | Request logging for debugging and usage analytics |
| **Backup script** | Automated daily backup of ISAM data files |

---

## v1.2 — Growth (Month 3-6)

Features that make COBILL a viable product beyond a portfolio project.

### Planned Features

| Feature | Description |
|---------|-------------|
| **REST API** | JSON API for programmatic invoice creation. API key authentication. |
| **Stripe payment links** | Embed a "Pay Now" link in invoice PDFs. Auto-mark as paid on webhook. |
| **Multi-user** | Multiple users per instance. Role-based access (admin, accountant, viewer). |
| **Client portal** | Clients log in to view their invoices and payment history. |
| **Accountant export** | FEC (Fichier des Écritures Comptables) export for French tax compliance. |
| **Search and filter** | Full-text search across invoices. Filter by date range, status, client, amount. |

### Technical Improvements

| Improvement | Description |
|-------------|-------------|
| **SQLite migration** | Migrate from ISAM to SQLite for complex queries while keeping COBOL calculation engine. |
| **Docker image** | Self-hosted Docker image for one-command deployment. |
| **CI/CD** | GitHub Actions pipeline: build COBOL → run tests → deploy to staging. |
| **Unit tests** | COBOL test programs that verify calculation accuracy. |

---

## v2.0 — Scale (Month 6-12)

The product becomes a real SaaS.

### Planned Features

| Feature | Description |
|---------|-------------|
| **Hosted SaaS** | Multi-tenant hosted version. Users sign up, no server needed. |
| **Stripe billing** | Subscription management for Pro and Business plans. |
| **Progressive Web App** | Installable on mobile. Offline invoice creation with sync. |
| **Integrations** | Zapier/Make webhooks. Slack notifications. Google Sheets export. |
| **Internationalization** | Support for non-French invoicing (UK VAT, German USt, etc.). |
| **Audit trail** | Complete log of every invoice action (created, modified, sent, paid). |

### Technical Improvements

| Improvement | Description |
|-------------|-------------|
| **SPARK/Ada module** | Optional verification module using SPARK (Ada subset) for mathematically provable calculations. Targeting aviation/defense clients. |
| **Load testing** | Verify CGI performance under concurrent load. Add FastCGI if needed. |
| **PostgreSQL option** | For SaaS multi-tenant, migrate to PostgreSQL with connection pooling. |

---

## Long-Term Vision

COBILL starts as a portfolio project and evolves into a niche invoicing tool with a unique identity:

1. **Open-source core** — The COBOL calculation engine and PostScript PDF generator remain open-source. Community contributions welcome.

2. **Hosted SaaS** — A managed version for users who don't want to self-host. Revenue from Pro/Business subscriptions.

3. **Enterprise module** — SPARK-verified calculations for industries requiring mathematical proof of correctness (finance, aviation, defense).

4. **Educational platform** — COBILL as a teaching tool: "Learn COBOL by building a real web application." Partnerships with coding bootcamps and universities.

### The Endgame

COBILL proves that the right tool for the job isn't always the newest one. COBOL handles money better than JavaScript. PostScript handles printing better than HTML-to-PDF converters. Sometimes, the best technology is the one that's been doing the same job perfectly for 65 years.

---

## Contributing

After the Holberton delivery, the repository will be open for contributions:

- **COBOL developers** — Help improve the calculation engine and add features
- **PostScript artists** — Design new invoice templates
- **Frontend developers** — Create additional CSS themes
- **Technical writers** — Improve documentation and tutorials
- **Translators** — Internationalize the interface

Contribution guidelines will be published in `CONTRIBUTING.md` after v1.0 release.
