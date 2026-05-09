# Solution

## Ce que fait Le Cobol

C'est un outil de facturation web léger qui :

- calcule en arithmétique décimale exacte via la clause `PICTURE` de COBOL ;
- produit des PDF via PostScript natif rendu par Ghostscript (pas de wkhtmltopdf, pas de Puppeteer) ;
- suit automatiquement les contributions URSSAF et le seuil TVA ;
- tourne sur n'importe quel Linux avec Apache + GnuCOBOL + Ghostscript ;
- sert l'UI via HTMX, sans framework JS ni build step.

## Pourquoi COBOL pour la monnaie

La clause `PICTURE` définit explicitement le format de stockage d'un nombre, chiffres avant et après la virgule, position du séparateur décimal :

```cobol
01 MONTANT-HT       PIC 9(5)V99.
01 TAUX-TVA         PIC V99 VALUE .20.
01 MONTANT-TVA      PIC 9(5)V99.
01 MONTANT-TTC      PIC 9(6)V99.

COMPUTE MONTANT-TVA = MONTANT-HT * TAUX-TVA.
ADD MONTANT-HT MONTANT-TVA GIVING MONTANT-TTC.
```

`PIC 9(5)V99` signifie : jusqu'à 5 chiffres avant la virgule, exactement 2 après. Le `V` marque la position décimale. Pas de flottant, pas d'arrondi imprévu. C'est la même arithmétique qu'utilisent les SI bancaires depuis 60 ans.

### Précision décimale comparée

| Opération | JavaScript | Python (float) | COBOL |
|-----------|-----------|-----------------|-------|
| `0.1 + 0.2` | `0.30000000000000004` | `0.30000000000000004` | `0.30` |
| `1.1 * 1.1` | `1.2100000000000002` | `1.2100000000000002` | `1.21` |
| `0.3 - 0.1` | `0.19999999999999998` | `0.19999999999999998` | `0.20` |

## Pourquoi PostScript pour les PDF

PostScript est le langage natif des imprimantes laser. Le format PDF en descend directement. Plutôt que de passer par un convertisseur HTML→PDF (avec tous les écarts de rendu que ça implique), Le Cobol écrit le PostScript brut :

```postscript
/Helvetica-Bold findfont 18 scalefont setfont
72 750 moveto (FACTURE #0042) show

/Helvetica findfont 11 scalefont setfont
72 720 moveto (Client: Dupont SARL) show
72 705 moveto (Date: 2026-03-25) show

% Ligne du tableau
72 650 moveto (Consulting) show
350 650 moveto (1 500,00 EUR) show
```

Le fichier `.ps` est converti en PDF par Ghostscript en une commande :

```bash
gs -sDEVICE=pdfwrite -dNOPAUSE -dBATCH -o invoice.pdf invoice.ps
```

### PostScript vs bibliothèques PDF

| Aspect | PostScript (Le Cobol) | Bibliothèques PDF classiques |
|--------|----------------------|------------------------------|
| Contrôle pixel | placement par coordonnées exact | dépend du rendu HTML/CSS |
| Dépendances | Ghostscript uniquement | wkhtmltopdf+Qt, ou Puppeteer+Chrome, ou WeasyPrint+Cairo |
| Taille fichier | source texte compacte | souvent volumineux |
| Cohérence | identique sur toute machine | varie selon le moteur |
| Courbe d'apprentissage | moyenne (langage à pile) | facile mais débogage pénible |

## Pourquoi HTMX

HTMX est une librairie JS de 14 Ko qui permet à du HTML standard d'envoyer des requêtes HTTP et de swapper du DOM, sans écrire une ligne de JavaScript :

```html
<button hx-post="/cgi-bin/cobill/create-invoice"
        hx-target="#result"
        hx-swap="innerHTML">
    Générer la facture
</button>
<div id="result"></div>
```

Au clic, HTMX envoie un POST. Le programme COBOL répond avec un fragment HTML. HTMX l'injecte dans `#result`. Pas de JSON à parser, pas de gestion d'état, pas de virtual DOM.

### Conséquences pour Le Cobol

- COBOL produit directement du HTML, pas besoin d'API JSON ni de couche de sérialisation.
- Aucun build step : un `<script>` dans le `<head>` et HTMX est installé.
- L'absence de framework côté client cohérence avec le reste du stack.

## Pourquoi CGI

CGI (Common Gateway Interface, 1993) est le moyen historique d'exécuter un programme côté serveur en réponse à une requête HTTP. Apache exécute un binaire, lui passe les données via variables d'environnement, et renvoie sa sortie standard comme corps de réponse HTTP.

Pour ce projet, c'est l'idéal :

1. COBOL compile en binaire natif (GnuCOBOL produit du C, gcc le compile).
2. Apache l'invoque à chaque requête via mod_cgi.
3. Le binaire lit `CONTENT_LENGTH`, `QUERY_STRING` et stdin.
4. Il écrit les en-têtes HTTP puis le HTML sur stdout.
5. Apache renvoie le tout au navigateur.

Pas d'application server, pas de runtime, pas de framework. Juste un binaire qui lit l'entrée et écrit la sortie.
