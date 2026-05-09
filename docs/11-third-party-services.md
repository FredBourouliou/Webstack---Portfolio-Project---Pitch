# Third-Party Services

## Required Services

| Service | Purpose | Cost | License |
|---------|---------|------|---------|
| **AWS EC2** | Production server (t2.micro or t3.micro) | Free tier eligible / ~$8-10/month | — |
| **GnuCOBOL 3.x** | COBOL compiler (COBOL → C → binary) | Free | GPL 3.0 |
| **Ghostscript 10.x** | PostScript → PDF conversion | Free | AGPL 3.0 |
| **Apache HTTP Server 2.4** | Web server with CGI support | Free | Apache License 2.0 |
| **HTMX 2.x** | Frontend interactivity library | Free | BSD 2-Clause |
| **GitHub** | Version control + project management | Free | — |

---

## AWS Hosting

| Service | Plan | Specs | Price |
|---------|------|-------|-------|
| **EC2** | t3.micro | 2 vCPU, 1 GB RAM, EBS storage | Free tier (12 months) / ~$8/month |
| **EC2** | t3.small | 2 vCPU, 2 GB RAM, EBS storage | ~$15/month |
| **EBS** | gp3 | 20 GB SSD | ~$1.60/month |
| **Route 53** | Hosted zone | DNS management | $0.50/month + queries |
| **ACM** | Certificate | SSL/TLS (free with AWS services) | Free |

**Recommendation:** EC2 t3.micro with Ubuntu 22.04 AMI — sufficient for COBILL's requirements and eligible for AWS Free Tier during the first 12 months.

**Why AWS:**
- Industry-standard cloud provider — demonstrates real-world deployment skills
- Free Tier covers the first year of development and early users
- Easy scaling path if the product grows (upgrade instance type, add load balancer)
- Route 53 + ACM for domain + SSL with minimal configuration
- eu-west-3 (Paris) region for low latency and GDPR compliance

COBILL's resource requirements are minimal:
- **CPU:** COBOL CGI binaries are ~1-2 MB and execute in milliseconds
- **RAM:** Apache + CGI uses ~50-100 MB under normal load
- **Storage:** ISAM data files + PDFs grow slowly (each invoice ≈ 50 KB PDF)

---

## Software Dependencies

### GnuCOBOL

The core of the project. Compiles COBOL source to C, then to native binary via GCC.

```bash
# Ubuntu/Debian
sudo apt install gnucobol

# Verify
cobc --version
# GnuCOBOL 3.x.x
```

- Website: https://gnucobol.sourceforge.io/
- Documentation: GnuCOBOL Programmer's Guide (freely available)
- License: GPL 3.0

### Ghostscript

Converts PostScript files to PDF.

```bash
# Ubuntu/Debian
sudo apt install ghostscript

# Verify
gs --version
# 10.x.x

# Basic usage
gs -sDEVICE=pdfwrite -dNOPAUSE -dBATCH -dQUIET -o output.pdf input.ps
```

- Website: https://www.ghostscript.com/
- License: AGPL 3.0

### Apache HTTP Server

Web server with CGI module.

```bash
# Ubuntu/Debian
sudo apt install apache2
sudo a2enmod cgi
sudo systemctl restart apache2

# Verify
apache2 -v
# Server version: Apache/2.4.x
```

- Website: https://httpd.apache.org/
- License: Apache License 2.0

### HTMX

Frontend library. Single file, no installation needed.

```bash
# Download
curl -o htmx.min.js https://unpkg.com/htmx.org@2/dist/htmx.min.js

# Or include via CDN (development only)
# <script src="https://unpkg.com/htmx.org@2"></script>
```

- Website: https://htmx.org/
- License: BSD 2-Clause

---

## External APIs

Une seule, optionnelle : **`recherche-entreprises.api.gouv.fr`** (ex-API SIRENE) pour l'enrichissement client à partir d'un SIRET.

- API publique gouvernementale française, pas de clé d'authentification, pas de limite contractuelle.
- Appelée depuis le backend par `bin/sirene` (curl + jq), résultat injecté dans le formulaire client via HTMX out-of-band swap.
- Si l'API tombe ou que le SIRET n'existe pas, l'utilisateur voit un message d'erreur et peut continuer à saisir manuellement — aucune dépendance bloquante.
- Aucune donnée du Cobol n'est envoyée à l'API : seul le SIRET (entré par l'utilisateur) sort.

Le reste de la pile est strictement local :
- Calculs financiers → COBOL.
- Génération PDF → PostScript + Ghostscript.
- Stockage → ISAM.
- Serveur HTTP → Apache.

Choix assumé : aucune autre API tierce, pour minimiser surface d'attaque, latence et exposition RGPD.

---

## Total Cost Summary

| Item | Monthly Cost |
|------|-------------|
| AWS EC2 (t3.micro) | Free (year 1) / ~$8 |
| AWS EBS (20 GB) | ~$1.60 |
| Route 53 (DNS) | ~$0.50 |
| ACM (SSL certificate) | Free |
| Domain name (optional) | ~$1 |
| All software | Free |
| **Total (year 1)** | **~$2/month (Free Tier)** |
| **Total (after year 1)** | **~$11/month** |

For comparison, the average invoicing SaaS costs €10-30/month in subscription fees alone, plus infrastructure costs of €15-50/month to run.
