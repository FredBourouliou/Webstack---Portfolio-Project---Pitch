# Stack technique

## Vue d'ensemble

| Composant | Techno | Année |
|-----------|--------|------|
| Moteur de calcul | GnuCOBOL 3.x | 1959 |
| Génération PDF | PostScript + Ghostscript | 1985 |
| Serveur web | Apache 2.4 + mod_cgi | 1995 |
| Frontend | HTML5 + HTMX 2.x + CSS3 | 2020 |
| Stockage | ISAM (fichiers indexés natifs COBOL) | 1959 |
| API tierce | `recherche-entreprises.api.gouv.fr` (enrichissement SIRET) | — |
| OS | Ubuntu 22.04 LTS | — |
| Déploiement | Single VPS AWS EC2 (t3.micro, eu-west-3) | — |

## GnuCOBOL

Compilateur COBOL open-source qui transpile vers du C et compile en binaire natif via gcc. La clause `PICTURE` impose une représentation décimale exacte (`PIC 9(5)V99` = 5 chiffres entiers + 2 décimales, sans flottant). Lecture des variables d'environnement via `ACCEPT FROM ENVIRONMENT`, écriture sur stdout via `DISPLAY` — tout ce dont CGI a besoin. Le support ISAM est intégré.

```bash
sudo apt install gnucobol
cobc -x -o invoice src/cobol/invoice.cob
```

## PostScript + Ghostscript

PostScript est un langage de description de page créé par Adobe en 1985, ancêtre direct du PDF. Ghostscript est l'interpréteur open-source de référence qui produit le PDF.

L'avantage par rapport à un convertisseur HTML→PDF (Puppeteer, wkhtmltopdf, WeasyPrint) : placement exact par coordonnées, aucune dépendance lourde, output bit-pour-bit identique d'une machine à l'autre. Le `.ps` est du texte plat, donc COBOL le génère ligne par ligne avec `DISPLAY`.

```bash
sudo apt install ghostscript
gs -sDEVICE=pdfwrite -dNOPAUSE -dBATCH -dQUIET -o output.pdf input.ps
```

## Apache 2.4 + mod_cgi

CGI est intégré à Apache : `a2enmod cgi` et c'est actif. Le serveur sert aussi les fichiers statiques (HTML, CSS, JS, PDF générés). Pas d'application server à empiler — Apache fork le binaire COBOL à chaque requête et lit son stdout.

```apache
ScriptAlias /cgi-bin/ /opt/cobill/bin/
<Directory "/opt/cobill/bin">
    Options +ExecCGI -Indexes
    SetHandler cgi-script
    Require all granted
</Directory>
```

## HTMX 2.x

Librairie JS de 14 Ko qui ajoute à HTML des attributs pour faire des requêtes et swapper du DOM, sans écrire une ligne de JS. COBOL renvoie du HTML directement, pas de JSON, pas de couche d'API. Aucun build step : un `<script>` dans le `<head>` et c'est en route. L'app reste utilisable sans JS (les `<form>` continuent de fonctionner par soumission classique).

```html
<script src="/js/htmx.min.js"></script>
```

## API tierce : recherche-entreprises.api.gouv.fr

Service public de la DINUM (Direction interministérielle du numérique), libre d'usage, sans clé. Utilisé pour enrichir un client à partir de son SIRET : l'utilisateur saisit le numéro, clique sur le bouton INSEE, le binaire `bin/sirene` lance un `curl` vers l'API, parse le JSON via `jq`, et HTMX injecte les champs (raison sociale, adresse, code postal, ville) dans le formulaire en *out-of-band swap*.

C'est la seule API externe consommée. Si elle tombe, le formulaire reste utilisable en saisie manuelle.

## ISAM

Indexed Sequential Access Method, le système de fichiers indexés natif de COBOL. Une `SELECT ... ORGANIZATION IS INDEXED RECORD KEY IS ...` déclare la "table", les `OPEN` / `READ` / `WRITE` / `REWRITE` font le CRUD. Index alternés pour les recherches secondaires. Pas de daemon, pas de driver, pas de connexion réseau — juste des fichiers sur disque. Le statut de fichier (`FILE STATUS`) signale les erreurs après chaque opération.

Limitation assumée : pas de jointure, pas d'agrégation déclarative. Toute la logique est en COBOL procédural. Pour une app mono-utilisateur, c'est un compromis raisonnable, et ça élimine tout risque d'injection SQL par construction.

## Comparaison rapide

| Aspect | Le Cobol | Stack JS moderne |
|--------|----------|------------------|
| Frontend | HTMX 14 Ko | React 140 Ko + router + state |
| Build | `make` | webpack + babel + eslint + prettier |
| Package manager | aucun | npm (500+ paquets typiques) |
| Stockage | ISAM (fichiers) | PostgreSQL + ORM + migrations |
| PDF | PostScript + Ghostscript | Puppeteer + Chrome ou wkhtmltopdf + Qt |
| Application server | Apache CGI | Express/Fastify + PM2 |
| JS livré au client | 14 Ko | 200-500 Ko |
| Coût infra | ~5 €/mois | 15-50 €/mois |
| `node_modules` | n/a | 200+ Mo |
