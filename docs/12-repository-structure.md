# Repository Structure

## Directory Layout

```
cobill/
│
├── README.md                        # Project overview + quick start
│
├── Makefile                         # Build targets (compile, deploy, clean)
│
├── src/
│   ├── cobol/
│   │   ├── invoice.cob              # Invoice creation + financial calculations
│   │   ├── client.cob               # Client CRUD operations
│   │   ├── dashboard.cob            # Revenue dashboard + statistics
│   │   ├── pdf-gen.cob              # PostScript file generation + Ghostscript call
│   │   ├── auth.cob                 # Authentication + session management
│   │   ├── cgi-utils.cob            # CGI parsing utilities (shared module)
│   │   └── copybooks/
│   │       ├── invoice-record.cpy   # Invoice data structure definition
│   │       ├── client-record.cpy    # Client data structure definition
│   │       ├── session-record.cpy   # Session data structure definition
│   │       └── config-record.cpy    # User configuration structure
│   │
│   └── postscript/
│       └── invoice-template.ps      # Base PostScript invoice template
│
├── web/
│   ├── index.html                   # Main HTML shell (SPA entry point)
│   ├── landing.html                 # Landing page (product presentation)
│   ├── css/
│   │   ├── terminal.css             # Retro IBM 3270 theme
│   │   ├── modern.css               # Clean modern theme
│   │   └── common.css               # Shared styles (layout, components)
│   ├── js/
│   │   └── htmx.min.js             # HTMX library (14 KB, vendored)
│   └── assets/
│       └── favicon.ico              # Site favicon
│
├── data/                            # COBOL ISAM data files (gitignored)
│   ├── .gitkeep
│   ├── clients.dat                  # Client records (ISAM indexed)
│   ├── invoices.dat                 # Invoice records (ISAM indexed)
│   ├── sessions.dat                 # Active sessions (ISAM indexed)
│   └── config.dat                   # User configuration
│
├── pdf/                             # Generated PDF files (gitignored)
│   └── .gitkeep
│
├── bin/                             # Compiled COBOL binaries (gitignored)
│   └── .gitkeep
│
├── scripts/
│   ├── build.sh                     # Compile all COBOL programs
│   ├── deploy.sh                    # Deploy to production VPS
│   ├── setup-server.sh              # Server provisioning (apt install, Apache config)
│   └── init-data.sh                 # Initialize empty ISAM data files
│
├── docs/                            # Project documentation
│   ├── 01-problem-statement.md
│   ├── 02-solution.md
│   ├── 03-commercial-angle.md
│   ├── 04-architecture.md
│   ├── 05-technology-stack.md
│   ├── 06-key-features.md
│   ├── 07-learning-objectives.md
│   ├── 08-challenges.md
│   ├── 09-schedule.md
│   ├── 10-mockups.md
│   ├── 11-third-party-services.md
│   ├── 12-repository-structure.md   # (this file)
│   ├── 13-code-examples.md
│   └── 14-roadmap.md
│
├── .gitignore
└── LICENSE
```

---

## File Descriptions

### Source Files (`src/`)

#### COBOL Programs (`src/cobol/`)

| File | Purpose | CGI Endpoint |
|------|---------|-------------|
| `invoice.cob` | Create, read, update invoices. All HT/TVA/TTC calculations. | `/cgi-bin/cobill/invoice` |
| `client.cob` | Create, read, update, delete client records. | `/cgi-bin/cobill/client` |
| `dashboard.cob` | Aggregate invoice data. Compute monthly/yearly stats, URSSAF, VAT threshold. | `/cgi-bin/cobill/dashboard` |
| `pdf-gen.cob` | Read invoice data, generate PostScript source, call Ghostscript. | `/cgi-bin/cobill/pdf` |
| `auth.cob` | Login, session creation/validation, logout. | `/cgi-bin/cobill/auth` |
| `cgi-utils.cob` | Shared module: parse form data, URL-decode, read env vars. | (linked into all programs) |

#### Copybooks (`src/cobol/copybooks/`)

COBOL copybooks are the equivalent of header files in C. They define shared data structures.

| File | Defines |
|------|---------|
| `invoice-record.cpy` | Invoice fields: number, client ID, date, due date, line items, totals, status |
| `client-record.cpy` | Client fields: ID, name, address, SIRET, email, phone |
| `session-record.cpy` | Session fields: token, user ID, creation time, expiry time |
| `config-record.cpy` | Config fields: user name, address, SIRET, IBAN, activity type, URSSAF rate |

#### PostScript (`src/postscript/`)

| File | Purpose |
|------|---------|
| `invoice-template.ps` | Base visual layout. COBOL injects dynamic values into a copy of this template. |

### Web Files (`web/`)

| File | Purpose |
|------|---------|
| `index.html` | Main application shell. Contains HTMX script, navigation, and `#content` div. |
| `landing.html` | Marketing landing page (product features, pricing, CTA). |
| `css/terminal.css` | Green-on-black IBM 3270 retro theme. |
| `css/modern.css` | Clean, professional white theme. |
| `css/common.css` | Layout, grid, buttons, forms — shared between themes. |
| `js/htmx.min.js` | HTMX library, vendored (not loaded from CDN in production). |

### Scripts (`scripts/`)

| File | Purpose |
|------|---------|
| `build.sh` | Compile all `.cob` files to binaries in `bin/`. |
| `deploy.sh` | Copy binaries to `/usr/lib/cgi-bin/cobill/`, web files to `/var/www/cobill/`, restart Apache. |
| `setup-server.sh` | Install GnuCOBOL, Ghostscript, Apache. Configure mod_cgi. Set up directories and permissions. |
| `init-data.sh` | Create empty ISAM data files with correct structure. |

---

## Build Process

```bash
# Compile a single program
cobc -x -o bin/invoice src/cobol/invoice.cob src/cobol/cgi-utils.cob

# Compile all programs
make build

# Deploy to server
make deploy

# Full setup on a fresh server
bash scripts/setup-server.sh
bash scripts/init-data.sh
make build
make deploy
```

---

## Makefile Targets

```makefile
COBC = cobc
COBC_FLAGS = -x
SRC_DIR = src/cobol
BIN_DIR = bin
CGI_DIR = /usr/lib/cgi-bin/cobill
WEB_DIR = /var/www/cobill

PROGRAMS = invoice client dashboard pdf-gen auth
SHARED = $(SRC_DIR)/cgi-utils.cob

.PHONY: build deploy clean

build: $(PROGRAMS:%=$(BIN_DIR)/%)

$(BIN_DIR)/%: $(SRC_DIR)/%.cob $(SHARED)
	$(COBC) $(COBC_FLAGS) -o $@ $< $(SHARED)

deploy: build
	sudo cp $(BIN_DIR)/* $(CGI_DIR)/
	sudo cp -r web/* $(WEB_DIR)/
	sudo chown -R www-data:www-data $(CGI_DIR) $(WEB_DIR)
	sudo systemctl reload apache2

clean:
	rm -f $(BIN_DIR)/*
```

---

## .gitignore

```gitignore
# Compiled binaries
bin/*
!bin/.gitkeep

# Data files (contain user data)
data/*
!data/.gitkeep

# Generated PDFs
pdf/*
!pdf/.gitkeep

# OS files
.DS_Store
Thumbs.db

# Editor files
*.swp
*.swo
*~
.vscode/
.idea/
```
