# Commercial Angle

## Target Market

| Segment | Size (France) | Pain Point |
|---------|---------------|------------|
| Auto-entrepreneurs | 2,000,000+ | Need simple, affordable invoicing |
| Freelance developers | 150,000+ | Appreciate the technical elegance |
| Small agencies | 200,000+ | Need multi-client invoice management |

### Primary persona

Une graphiste freelance, ~30 ans, qui facture 5 à 10 clients par mois avec un template Word. Elle calcule la TVA à la calculette, ne suit pas son seuil de franchise, et refuse de payer 15 €/mois pour un outil. C'est le cœur de cible.

### Secondary persona

Un développeur freelance qui utilise un free tier d'un SaaS et le trouve lent. Il chercherait une alternative open-source auto-hébergeable. L'angle COBOL + PostScript le pousserait à partager le projet sur Twitter/Hacker News, ce qui amène du trafic gratuit.

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

## Positionnement

Un argument double-niveau :

- Pour le client final : c'est de la techno bancaire, donc fiable, donc pas de centimes qui sautent.
- Pour le développeur : COBOL + PostScript + HTMX, zéro npm — ça fait causer en ligne et ça draine du trafic.

Le caractère contre-intuitif du stack est aussi son angle viral. C'est le genre de projet qui circule sur Hacker News et dev Twitter, ce qui compense l'absence de budget marketing.

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
