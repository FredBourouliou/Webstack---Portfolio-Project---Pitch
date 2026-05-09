# Le Cobol

Application web de facturation pour auto-entrepreneurs, écrite en COBOL pour le calcul, en PostScript pour le PDF, et servie via Apache CGI. Le frontend tourne en HTMX, sans framework JavaScript ni build step. Données stockées en ISAM natif COBOL — pas de SGBD externe.

En production : **https://lecobol.com**

## Pourquoi ce stack

Les calculs en virgule flottante font perdre des centimes. COBOL, lui, fait de l'arithmétique décimale exacte par défaut depuis 1959, et c'est encore ce qui tourne dans la majorité des systèmes bancaires. PostScript, c'est le langage natif des imprimantes laser depuis 1985 ; toute la chaîne PDF en descend. CGI, enfin, c'est la façon la plus simple de coller un binaire derrière une URL HTTP.

Le projet existe pour démontrer qu'on peut produire une app web propre, déployable et conforme RGPD avec ces trois technos plutôt qu'un stack JavaScript moderne.

## Auteur

Frédéric Bourouliou — full-stack solo.

## Documentation

- [docs/01-problem-statement.md](docs/01-problem-statement.md) — le problème
- [docs/02-solution.md](docs/02-solution.md) — la solution
- [docs/03-commercial-angle.md](docs/03-commercial-angle.md) — cible et modèle commercial
- [docs/04-architecture.md](docs/04-architecture.md) — architecture
- [docs/05-technology-stack.md](docs/05-technology-stack.md) — stack technique
- [docs/06-key-features.md](docs/06-key-features.md) — fonctionnalités
- [docs/07-learning-objectives.md](docs/07-learning-objectives.md) — objectifs d'apprentissage
- [docs/08-challenges.md](docs/08-challenges.md) — risques et mitigations
- [docs/09-schedule.md](docs/09-schedule.md) — planning
- [docs/10-mockups.md](docs/10-mockups.md) — mockups
- [docs/11-third-party-services.md](docs/11-third-party-services.md) — services tiers
- [docs/12-repository-structure.md](docs/12-repository-structure.md) — structure du repo
- [docs/13-code-examples.md](docs/13-code-examples.md) — exemples de code
- [docs/14-roadmap.md](docs/14-roadmap.md) — roadmap
- [docs/15-database-design.md](docs/15-database-design.md) — conception BDD
- [docs/16-uml-sequences.md](docs/16-uml-sequences.md) — diagrammes de séquence

## Quick start

```bash
sudo apt install gnucobol ghostscript apache2
sudo a2enmod cgi
sudo systemctl restart apache2
cd Cobill
make build
```

Pour le déploiement complet, voir [Cobill/deploy/README.md](Cobill/deploy/README.md).

## Stack

| Couche | Techno |
|---|---|
| Moteur de calcul | GnuCOBOL 3.x |
| Génération PDF | PostScript + Ghostscript |
| Serveur | Apache 2.4 + mod_cgi |
| Frontend | HTML5 + HTMX 2.x |
| Stockage | ISAM (fichiers indexés natifs COBOL) |
| Infra | AWS EC2 t3.micro (eu-west-3) |

JavaScript total : 14 Ko (HTMX). Aucune dépendance npm.

<p align="center">
  <img src="duck.png" alt="" width="400">
</p>
