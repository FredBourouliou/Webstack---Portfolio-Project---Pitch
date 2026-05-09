COBC      := cobc
COBC_FLAGS := -x -I src/cobol/copybooks
SRC_DIR   := src/cobol
BIN_DIR   := bin
DATA_DIR  := data

PROGRAMS  := hello client invoice pdf-gen dashboard auth sirene

PS_SRC    := src/postscript/invoice-template.ps
PDF_OUT   := pdf/invoice-2026-0001.pdf
PNG_OUT   := pdf/invoice-2026-0001.png

BINARIES  := $(addprefix $(BIN_DIR)/,$(PROGRAMS))

# auth.cob calls libc crypt(3). -fstatic-call emits a direct C call
# rather than going through GnuCOBOL's module loader.
UNAME_S := $(shell uname -s)
ifeq ($(UNAME_S),Linux)
    AUTH_LIBS := -fstatic-call -lcrypt
else ifeq ($(UNAME_S),Darwin)
    LIBXCRYPT_PREFIX := $(shell brew --prefix libxcrypt 2>/dev/null)
    ifneq ($(LIBXCRYPT_PREFIX),)
        AUTH_LIBS := -fstatic-call -L$(LIBXCRYPT_PREFIX)/lib -lcrypt
    else
        AUTH_LIBS :=
    endif
else
    AUTH_LIBS :=
endif

.PHONY: build clean serve reset-data pdf png pdf-watch

build: $(BINARIES)

$(BIN_DIR)/%: $(SRC_DIR)/%.cob \
              $(wildcard $(SRC_DIR)/copybooks/*.cpy) \
              | $(BIN_DIR)
	$(COBC) $(COBC_FLAGS) -o $@ $< $(EXTRA_LIBS)

$(BIN_DIR)/auth: EXTRA_LIBS := $(AUTH_LIBS)

$(BIN_DIR):
	@mkdir -p $@

serve: build | $(DATA_DIR)
	python3 scripts/dev-server.py 8080

$(DATA_DIR):
	@mkdir -p $@

reset-data:
	rm -f $(DATA_DIR)/*.dat $(DATA_DIR)/*.idx

pdf: $(PDF_OUT)

png: $(PNG_OUT)

$(PDF_OUT): $(PS_SRC)
	gs -sDEVICE=pdfwrite -dNOPAUSE -dBATCH -dQUIET \
	   -dPDFSETTINGS=/prepress -sOutputFile=$@ $<

$(PNG_OUT): $(PS_SRC)
	gs -sDEVICE=png16m -dNOPAUSE -dBATCH -dQUIET \
	   -r150 -sOutputFile=$@ $<

clean:
	rm -f $(BINARIES)
	rm -f $(PDF_OUT) $(PNG_OUT)
	rm -f pdf/INV-*.ps pdf/INV-*.pdf
