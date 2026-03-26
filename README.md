# COBILL — COBOL-Powered Invoicing

> *"JavaScript can't count. COBOL can."*
> `0.1 + 0.2 = 0.30000000000000004` in JavaScript.
> `0.1 + 0.2 = 0.30` in COBOL. Every time. Since 1959.

---

**COBILL** is a web-based invoicing application for French freelancers, powered by two languages that have been doing their job flawlessly for decades:

- **COBOL** (1959) — the language of banks — handles all financial calculations with native decimal arithmetic
- **PostScript** (1985) — the language of printers — generates pixel-perfect PDF invoices without any library
- **HTMX** (2020) — delivers a dynamic UI with zero JavaScript frameworks

The entire application runs through **CGI**, the original server-side web technology — making it the most historically coherent web stack ever assembled.

**One-liner pitch:** *"Your bank runs on COBOL. Your printer runs on PostScript. Your invoicing app should too."*

---

## Team

| Name | Role |
|------|------|
| Frédéric Bourouliou | Solo developer — Full Stack |

---

## Documentation

| Document | Description |
|----------|-------------|
| [Problem Statement](docs/01-problem-statement.md) | Why this project exists — the pain points of 2M+ French freelancers |
| [Solution](docs/02-solution.md) | What COBILL does and why COBOL + PostScript are the right tools |
| [Commercial Angle](docs/03-commercial-angle.md) | Target market, pricing model, competitive advantages |
| [Architecture](docs/04-architecture.md) | System design, data flow, component diagram |
| [Technology Stack](docs/05-technology-stack.md) | Every technology choice, justified |
| [Key Features](docs/06-key-features.md) | MVP, core, and polish feature sets |
| [Learning Objectives](docs/07-learning-objectives.md) | Skills demonstrated through this project |
| [Challenges](docs/08-challenges.md) | Technical risks identified and mitigation strategies |
| [Schedule](docs/09-schedule.md) | Day-by-day planning across 27 days |
| [Mock-ups](docs/10-mockups.md) | Terminal UI, dashboard, and PDF invoice mock-ups |
| [Third-Party Services](docs/11-third-party-services.md) | External dependencies and costs |
| [Repository Structure](docs/12-repository-structure.md) | File and folder organization |
| [Code Examples](docs/13-code-examples.md) | COBOL, PostScript, and HTMX sample code |
| [Roadmap](docs/14-roadmap.md) | Post-Holberton evolution plan |

---

## Quick Start

```bash
# Install dependencies (Ubuntu 22.04)
sudo apt install gnucobol ghostscript apache2

# Enable CGI
sudo a2enmod cgi
sudo systemctl restart apache2

# Build all COBOL programs
make build

# Deploy to Apache
make deploy

# Open in browser
open http://localhost/cobill
```

---

## Tech Stack at a Glance

| Layer | Technology | Year |
|-------|-----------|------|
| Financial engine | GnuCOBOL 3.x | 1959 |
| PDF generation | PostScript + Ghostscript | 1985 |
| Web server | Apache 2.4 + mod_cgi | 1995 |
| Frontend | HTML5 + HTMX 2.x + CSS3 | 2020 |
| Data storage | COBOL ISAM files | 1959 |

**Total frontend JavaScript: 14 KB** (HTMX only).
**Total npm packages: 0.**
**Infrastructure: AWS EC2** (Free Tier eligible).

---

## Here a beautiful duck

<p align="center">
  <img src="duck.png" alt="A beautiful duck" width="400">
</p>

---

*COBILL — Where 1959 meets 1985 meets 2026.*
*Two languages. Zero dependencies. Perfect invoices.*
