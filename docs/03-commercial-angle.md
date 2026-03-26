# Commercial Angle

## Target Market

| Segment | Size (France) | Pain Point |
|---------|---------------|------------|
| Auto-entrepreneurs | 2,000,000+ | Need simple, affordable invoicing |
| Freelance developers | 150,000+ | Appreciate the technical elegance |
| Small agencies | 200,000+ | Need multi-client invoice management |

### Primary Persona

**Marie, 32, freelance graphic designer.**
She invoices 5-10 clients per month. She currently uses a Word template she found online. She calculates TVA with a calculator app. She has no idea how close she is to the VAT threshold. She doesn't want to pay €15/month for an invoicing tool.

### Secondary Persona

**Thomas, 28, freelance web developer.**
He currently uses a free tier of a SaaS invoicing tool but finds it slow and bloated. He would appreciate an open-source, self-hostable alternative. The COBOL + PostScript angle would make him share the project on Twitter/Hacker News.

---

## Pricing Model (Freemium)

| Plan | Price | Includes |
|------|-------|----------|
| **Free** | €0/month | 5 invoices/month, 1 client profile, basic PDF template |
| **Pro** | €5/month | Unlimited invoices, unlimited clients, custom branding on PDFs, URSSAF dashboard, VAT threshold alerts |
| **Business** | €15/month | Multi-user access, REST API, automated payment reminders, accountant-friendly CSV/JSON export |

### Revenue Projections (Conservative)

| Metric | Year 1 | Year 2 |
|--------|--------|--------|
| Free users | 1,000 | 5,000 |
| Pro conversions (5%) | 50 | 250 |
| Business conversions (1%) | 10 | 50 |
| MRR (Monthly Recurring Revenue) | €400 | €1,750 |
| ARR (Annual Recurring Revenue) | €4,800 | €21,000 |

---

## Competitive Analysis

### Direct Competitors

| Tool | Price | Stack | Weakness |
|------|-------|-------|----------|
| **Henrri** | Free | Ruby on Rails | Slow, limited customization |
| **Freebe** | €14/month | PHP/Laravel | Expensive for basic invoicing |
| **Tiime** | €0-29/month | React + Node | Complex, targets accountants |
| **Facture.net** | Free | PHP | Outdated UI, no URSSAF tracking |
| **Abby** | €12/month | React + Node | Overkill for simple invoicing |

### COBILL's Competitive Advantages

| Feature | COBILL | Typical SaaS |
|---------|--------|--------------|
| Decimal precision | Native (COBOL PIC clause) | Floating-point (approximated) |
| PDF generation | Native (PostScript) | Library-dependent |
| Server requirements | Apache + CGI (€3/month VPS) | Node.js + DB + Redis + queue |
| Frontend bundle | 14 KB (HTMX) | 200+ KB (React/Vue) |
| npm dependencies | 0 | 500+ |
| Self-hostable | Yes (single binary) | Rarely |
| Open source | Yes | Rarely |

---

## Unique Selling Proposition

### The Technical Story

*"Built with the same technology that processes 95% of the world's financial transactions. Not because it's trendy — because it's right."*

This USP works on two levels:

1. **For non-technical users:** "The same tech your bank uses" = trust and reliability
2. **For developers:** "COBOL + PostScript + HTMX with zero npm" = instant virality on Hacker News, Reddit, and dev Twitter

### The Viral Angle

COBILL is inherently shareable. The absurdity of using COBOL for a modern web app — combined with the fact that it's *actually the right tool for the job* — makes it a natural conversation starter. This is built-in marketing that no competitor can replicate.

---

## Go-to-Market Strategy

### Phase 1 — Launch (Holberton presentation)

- Live demo during pitch
- GitHub repository public
- Post on Hacker News, Reddit r/programming, dev.to
- "I built an invoicing app in COBOL" blog post

### Phase 2 — Community (Month 1-3)

- Open-source community building
- Docker image for easy self-hosting
- French freelance forums (Malt, Crème de la Crème, freelance communities)

### Phase 3 — Monetization (Month 3-6)

- Hosted SaaS version (Pro + Business plans)
- Stripe integration for subscription billing
- Content marketing (blog posts about COBOL + modern web)
