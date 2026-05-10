      *> pdf-gen.cob
      *>
      *> Build a PDF invoice from an INVOICE-RECORD by writing a
      *> PostScript document and converting it through Ghostscript.
      *> The PostScript text is constructed line by line in this
      *> program; no HTML, no headless browser, no third-party
      *> PDF library are involved.
      *>
      *> Endpoint:   /cgi-bin/pdf?number=YYYY-NNNN
      *> Auth gate:  yes
      *> Method:     GET
      *>
      *> Outputs:
      *>   pdf/INV-YYYY-NNNN.ps    (PostScript source, kept for
      *>                            audit / debugging)
      *>   pdf/INV-YYYY-NNNN.pdf   (Ghostscript output)
      *>
      *> On success, the program replies with a 302 redirect to
      *> /pdf/INV-... .pdf, which Apache then serves as a static
      *> file. On failure (missing number, invoice not found,
      *> Ghostscript error) it emits an HTML error page.
      *>
      *> PostScript layout: A4 portrait, 595 x 842 points. All
      *> placement coordinates are in PostScript points
      *> (1 pt = 1/72 inch), origin at the bottom-left corner.
       IDENTIFICATION DIVISION.
       PROGRAM-ID. PDF-GEN.

       ENVIRONMENT DIVISION.
       CONFIGURATION SECTION.
       COPY "special-names.cpy".

       INPUT-OUTPUT SECTION.
       FILE-CONTROL.
      *>     Invoice store, READ by primary key to load the row
      *>     whose number was given in the URL.
           SELECT INVOICE-FILE
               ASSIGN TO "data/invoices.dat"
               ORGANIZATION IS INDEXED
               ACCESS MODE IS DYNAMIC
               RECORD KEY IS INV-NUMBER
               ALTERNATE RECORD KEY IS INV-CLIENT-ID
                   WITH DUPLICATES
               FILE STATUS IS WS-INV-STATUS.

      *>     Client file, used to enrich the invoice with the
      *>     full postal address (the invoice itself only stores
      *>     CLI-ID + a snapshot of CLI-NAME).
           SELECT CLIENT-FILE
               ASSIGN TO "data/clients.dat"
               ORGANIZATION IS INDEXED
               ACCESS MODE IS DYNAMIC
               RECORD KEY IS CLI-ID
               ALTERNATE RECORD KEY IS CLI-NAME
                   WITH DUPLICATES
               FILE STATUS IS WS-CLI-STATUS.

      *>     Static PostScript prolog (procedure definitions,
      *>     font setup, helpers) shared by every PDF. Copied
      *>     verbatim into the generated .ps file.
           SELECT PROLOG-FILE
               ASSIGN TO "src/postscript/prolog.ps"
               ORGANIZATION IS LINE SEQUENTIAL
               FILE STATUS IS WS-PROLOG-STATUS.

      *>     Per-invoice PostScript output, written line by line.
           SELECT PS-FILE
               ASSIGN TO WS-PS-PATH
               ORGANIZATION IS LINE SEQUENTIAL
               FILE STATUS IS WS-PS-STATUS.

      *>     Session file (opened by the auth gate).
           SELECT SESSION-FILE
               ASSIGN TO "data/sessions.dat"
               ORGANIZATION IS INDEXED
               ACCESS MODE IS DYNAMIC
               RECORD KEY IS SES-TOKEN
               FILE STATUS IS WS-AUTH-FS-STATUS.

       DATA DIVISION.
       FILE SECTION.
       FD INVOICE-FILE.
       COPY "invoice-record.cpy".

       FD CLIENT-FILE.
       COPY "client-record.cpy".

       FD PROLOG-FILE.
       01 PROLOG-LINE PIC X(200).

       FD PS-FILE.
       01 PS-LINE     PIC X(200).

       FD SESSION-FILE.
       COPY "session-record.cpy".

       WORKING-STORAGE SECTION.
       COPY "cgi-utils-ws.cpy".
       COPY "auth-check-ws.cpy".

      *> ISAM file statuses ("00" = success on each file).
       01 WS-INV-STATUS    PIC XX.
       01 WS-CLI-STATUS    PIC XX.
       01 WS-PROLOG-STATUS PIC XX.
       01 WS-PS-STATUS     PIC XX.
       01 WS-EOF           PIC X VALUE "N".

      *> Invoice number pulled from the query string. Format is
      *> YYYY-NNNN (9 chars including the dash).
       01 WS-LOOKUP-NUMBER PIC X(9).

      *> Generated file paths: server-side, derived from
      *> INV-NUMBER, never from raw user input. Safe to use as
      *> shell arguments.
       01 WS-PS-PATH       PIC X(64).
       01 WS-PDF-PATH      PIC X(64).
       01 WS-PDF-URL       PIC X(64).

      *> Shell command buffer for the Ghostscript call, plus
      *> the return code.
       01 WS-CMD           PIC X(256).
       01 WS-RC            PIC S9(4).

      *> ----- French amount formatter -----
      *> WS-NUM-IN -> WS-NUM-FR with locale-correct separators:
      *> thousands as non-breaking spaces, comma as decimal.
       01 WS-NUM-IN        PIC 9(9)V99.
       01 WS-NUM-EDITED    PIC ZZZ,ZZZ,ZZ9.99.
       01 WS-NUM-FR        PIC X(15).

      *> ----- Date formatter -----
      *> WS-DATE-IN  = "YYYY-MM-DD"
      *> WS-DATE-FR  = "DD/MM/YYYY"
       01 WS-DATE-IN       PIC X(10).
       01 WS-DATE-FR       PIC X(10).

      *> ----- Loop counters for line items in the PS table -----
      *> WS-FIRST-LINE-Y / WS-LINE-STEP set where the first
      *> table row starts (in PostScript points, y axis runs
      *> bottom-up) and how much vertical space each row uses.
       01 WS-LINE-IDX      PIC 99.
       01 WS-LINE-Y        PIC 9(4).
       01 WS-FIRST-LINE-Y  PIC 9(4) VALUE 590.
       01 WS-LINE-STEP     PIC 9(2) VALUE 25.

      *> Scratch buffer used while building one PostScript line
      *> before writing it to PS-FILE.
       01 WS-PS-BUF        PIC X(200).

       PROCEDURE DIVISION.
      *> MAIN-LOGIC
      *>
      *> Five-step pipeline:
      *>   1. Read the CGI request, gate on auth.
      *>   2. Extract ?number= and load the matching invoice from
      *>      data/invoices.dat. Missing or unknown number short
      *>      circuits to an HTML error page.
      *>   3. Enrich with the client's full address.
      *>   4. Render the .ps source, then run Ghostscript on it.
      *>   5. Reply with a 302 redirect to the generated PDF, which
      *>      Apache serves as a static file from /pdf/.
       MAIN-LOGIC.
           PERFORM READ-CGI-INPUT
           PERFORM PARSE-CGI-INPUT
           COPY "auth-check.cpy".

      *>   Required parameter check.
           MOVE "number" TO CGI-L-KEY
           PERFORM FIND-FIELD
           IF CGI-L-FOUND NOT = "Y"
                   OR FUNCTION TRIM(CGI-L-VALUE) = SPACES
               PERFORM EMIT-HTML-HEADERS
               PERFORM RENDER-MISSING-NUMBER
               STOP RUN
           END-IF
           MOVE FUNCTION TRIM(CGI-L-VALUE) TO WS-LOOKUP-NUMBER

      *>   Load the invoice header + line items. Missing row
      *>   surfaces as a "not found" panel rather than a 500.
           PERFORM LOAD-INVOICE
           IF WS-INV-STATUS NOT = "00"
               PERFORM EMIT-HTML-HEADERS
               PERFORM RENDER-NOT-FOUND
               STOP RUN
           END-IF

           PERFORM LOAD-CLIENT-DETAILS
           PERFORM BUILD-PATHS
           PERFORM WRITE-PS-FILE
           PERFORM RUN-GHOSTSCRIPT
           PERFORM EMIT-REDIRECT

           STOP RUN.

      *> LOAD-INVOICE
      *>
      *> Indexed READ by INV-NUMBER. INVALID KEY (status "23")
      *> means the row does not exist; we map that to a generic
      *> "not found" code so the caller stays simple.
       LOAD-INVOICE.
           OPEN INPUT INVOICE-FILE
           IF WS-INV-STATUS NOT = "00"
               EXIT PARAGRAPH
           END-IF
           MOVE WS-LOOKUP-NUMBER TO INV-NUMBER
           READ INVOICE-FILE
               INVALID KEY
                   CLOSE INVOICE-FILE
                   MOVE "23" TO WS-INV-STATUS
               NOT INVALID KEY
                   CLOSE INVOICE-FILE
                   MOVE "00" TO WS-INV-STATUS
           END-READ
           .

      *> LOAD-CLIENT-DETAILS
      *>
      *> Resolve the foreign key (CLI-ID) into the full client
      *> record so we can print the address on the PDF. Falls
      *> through silently if the client has been soft-deleted
      *> or the FK is blank; the invoice still renders with the
      *> name snapshot already on the record.
       LOAD-CLIENT-DETAILS.
           IF FUNCTION TRIM(INV-CLIENT-ID) = SPACES
               EXIT PARAGRAPH
           END-IF
           OPEN INPUT CLIENT-FILE
           IF WS-CLI-STATUS NOT = "00"
               EXIT PARAGRAPH
           END-IF
           MOVE INV-CLIENT-ID TO CLI-ID
           READ CLIENT-FILE
               INVALID KEY
                   CONTINUE
               NOT INVALID KEY
                   CONTINUE
           END-READ
           CLOSE CLIENT-FILE
           .

      *> BUILD-PATHS
      *>
      *> Compose the three derived paths used downstream:
      *>   WS-PS-PATH   = "pdf/INV-YYYY-NNNN.ps"   (filesystem)
      *>   WS-PDF-PATH  = "pdf/INV-YYYY-NNNN.pdf"  (filesystem)
      *>   WS-PDF-URL   = "/pdf/INV-YYYY-NNNN.pdf" (browser URL)
      *>
      *> INV-NUMBER is server-generated so these paths are safe
      *> to pass to the shell unquoted.
       BUILD-PATHS.
           MOVE SPACES TO WS-PS-PATH
           STRING "pdf/INV-"  DELIMITED BY SIZE
                  FUNCTION TRIM(INV-NUMBER) DELIMITED BY SIZE
                  ".ps"       DELIMITED BY SIZE
               INTO WS-PS-PATH

           MOVE SPACES TO WS-PDF-PATH
           STRING "pdf/INV-"  DELIMITED BY SIZE
                  FUNCTION TRIM(INV-NUMBER) DELIMITED BY SIZE
                  ".pdf"      DELIMITED BY SIZE
               INTO WS-PDF-PATH

           MOVE SPACES TO WS-PDF-URL
           STRING "/pdf/INV-" DELIMITED BY SIZE
                  FUNCTION TRIM(INV-NUMBER) DELIMITED BY SIZE
                  ".pdf"      DELIMITED BY SIZE
               INTO WS-PDF-URL
           .

      *> WRITE-PS-FILE
      *>
      *> Emit the PostScript source line by line. The document
      *> is structured top-to-bottom:
      *>   - DSC header (PS-Adobe-3.0, title, bounding box)
      *>   - prolog block (font helpers, copied from prolog.ps)
      *>   - page setup
      *>   - invoice header (logo strap, invoice number)
      *>   - from/to addresses block
      *>   - issue date + due date
      *>   - line items table (header + up to 10 rows)
      *>   - totals block (HT, TVA, TTC)
      *>   - legal mentions
      *>   - footer
      *>
      *> The PostScript file is kept on disk after Ghostscript
      *> converts it: handy for reproducing a PDF byte-for-byte
      *> later, or for debugging layout issues.
       WRITE-PS-FILE.
           OPEN OUTPUT PS-FILE
           PERFORM WRITE-DOC-HEADER
           PERFORM COPY-PROLOG
           PERFORM WRITE-PAGE-SETUP
           PERFORM WRITE-INVOICE-HEADER
           PERFORM WRITE-FROM-TO
           PERFORM WRITE-DATES
           PERFORM WRITE-TABLE-HEADER
           PERFORM WRITE-LINE-ITEMS
           PERFORM WRITE-TOTALS
           PERFORM WRITE-LEGAL
           PERFORM WRITE-FOOTER
           CLOSE PS-FILE
           .

       WRITE-DOC-HEADER.
           MOVE "%!PS-Adobe-3.0" TO PS-LINE
           PERFORM PUT-LINE

           MOVE SPACES TO PS-LINE
           STRING "%%Title: COBILL Invoice "
                       DELIMITED BY SIZE
                  FUNCTION TRIM(INV-NUMBER)
                       DELIMITED BY SIZE
               INTO PS-LINE
           PERFORM PUT-LINE

           MOVE "%%Creator: COBILL pdf-gen.cob"     TO PS-LINE
           PERFORM PUT-LINE
           MOVE "%%BoundingBox: 0 0 595 842"        TO PS-LINE
           PERFORM PUT-LINE
           MOVE "%%DocumentMedia: A4 595 842 80 white ()" TO PS-LINE
           PERFORM PUT-LINE
           MOVE "%%Pages: 1"                        TO PS-LINE
           PERFORM PUT-LINE
           MOVE "%%LanguageLevel: 2"                TO PS-LINE
           PERFORM PUT-LINE
           MOVE "%%EndComments"                     TO PS-LINE
           PERFORM PUT-LINE

           MOVE "%%BeginProlog" TO PS-LINE
           PERFORM PUT-LINE
           .

       COPY-PROLOG.
           OPEN INPUT PROLOG-FILE
           IF WS-PROLOG-STATUS NOT = "00"
               EXIT PARAGRAPH
           END-IF
           MOVE "N" TO WS-EOF
           PERFORM UNTIL WS-EOF = "Y"
               READ PROLOG-FILE
                   AT END MOVE "Y" TO WS-EOF
                   NOT AT END
                       WRITE PS-LINE FROM PROLOG-LINE
               END-READ
           END-PERFORM
           CLOSE PROLOG-FILE

           MOVE "%%EndProlog" TO PS-LINE
           PERFORM PUT-LINE
           .

       WRITE-PAGE-SETUP.
           MOVE "%%Page: 1 1" TO PS-LINE
           PERFORM PUT-LINE
           .

      *> HEADER — sender brand + invoice number.
       WRITE-INVOICE-HEADER.
           MOVE "/Helvetica-Bold 22 selectFont"     TO PS-LINE
           PERFORM PUT-LINE
           MOVE "0.10 0.20 0.50 setrgbcolor"        TO PS-LINE
           PERFORM PUT-LINE
           MOVE "72 780 (LE COBOL) drawAt"          TO PS-LINE
           PERFORM PUT-LINE
           MOVE "/Helvetica 9 selectFont"           TO PS-LINE
           PERFORM PUT-LINE
           MOVE "0.50 setgray"                      TO PS-LINE
           PERFORM PUT-LINE
           MOVE "72 766 (COBOL-Powered Invoicing) drawAt"
               TO PS-LINE
           PERFORM PUT-LINE
           MOVE "/Helvetica-Bold 18 selectFont"     TO PS-LINE
           PERFORM PUT-LINE
           MOVE "0 setgray"                         TO PS-LINE
           PERFORM PUT-LINE
           MOVE "523 780 (FACTURE) drawRight"       TO PS-LINE
           PERFORM PUT-LINE
           MOVE "/Helvetica 11 selectFont"          TO PS-LINE
           PERFORM PUT-LINE

           MOVE SPACES TO PS-LINE
           STRING "523 763 (No "
                       DELIMITED BY SIZE
                  FUNCTION TRIM(INV-NUMBER)
                       DELIMITED BY SIZE
                  ") drawRight"
                       DELIMITED BY SIZE
               INTO PS-LINE
           PERFORM PUT-LINE

           MOVE "72 752 523 0.5 0.7 hr"             TO PS-LINE
           PERFORM PUT-LINE
           .

      *> FROM/TO blocks. Sender is hardcoded (will read config.dat later).
       WRITE-FROM-TO.
           MOVE "0 setgray"                          TO PS-LINE
           PERFORM PUT-LINE
           MOVE "/Helvetica-Bold 9 selectFont"       TO PS-LINE
           PERFORM PUT-LINE
           MOVE "72 730 (DE) drawAt"                 TO PS-LINE
           PERFORM PUT-LINE
           MOVE "350 730 (CLIENT) drawAt"            TO PS-LINE
           PERFORM PUT-LINE
           MOVE "/Helvetica 10 selectFont"           TO PS-LINE
           PERFORM PUT-LINE

      *>   Sender (left). Placeholders for now.
           MOVE "72 715 (Votre raison sociale) drawAt"
               TO PS-LINE
           PERFORM PUT-LINE
           MOVE "72 702 (Votre adresse) drawAt" TO PS-LINE
           PERFORM PUT-LINE
           MOVE "72 689 (Code postal Ville, France) drawAt"
               TO PS-LINE
           PERFORM PUT-LINE
           MOVE "72 676 (SIRET: 000 000 000 00000) drawAt"
               TO PS-LINE
           PERFORM PUT-LINE

      *>   Client (right).
           PERFORM EMIT-CLIENT-NAME
           PERFORM EMIT-CLIENT-ADDRESS
           PERFORM EMIT-CLIENT-CITY
           PERFORM EMIT-CLIENT-SIRET
           .

       EMIT-CLIENT-NAME.
           MOVE SPACES TO PS-LINE
           STRING "350 715 ("           DELIMITED BY SIZE
                  FUNCTION TRIM(INV-CLIENT-NAME)
                                        DELIMITED BY SIZE
                  ") drawAt"            DELIMITED BY SIZE
               INTO PS-LINE
           PERFORM PUT-LINE
           .

       EMIT-CLIENT-ADDRESS.
           IF FUNCTION TRIM(CLI-ADDRESS) = SPACES
               EXIT PARAGRAPH
           END-IF
           MOVE SPACES TO PS-LINE
           STRING "350 702 ("           DELIMITED BY SIZE
                  FUNCTION TRIM(CLI-ADDRESS)
                                        DELIMITED BY SIZE
                  ") drawAt"            DELIMITED BY SIZE
               INTO PS-LINE
           PERFORM PUT-LINE
           .

       EMIT-CLIENT-CITY.
           IF FUNCTION TRIM(CLI-ZIP) = SPACES
                   AND FUNCTION TRIM(CLI-CITY) = SPACES
               EXIT PARAGRAPH
           END-IF
           MOVE SPACES TO PS-LINE
           STRING "350 689 ("           DELIMITED BY SIZE
                  FUNCTION TRIM(CLI-ZIP)
                                        DELIMITED BY SIZE
                  " "                   DELIMITED BY SIZE
                  FUNCTION TRIM(CLI-CITY)
                                        DELIMITED BY SIZE
                  ", "                  DELIMITED BY SIZE
                  FUNCTION TRIM(CLI-COUNTRY)
                                        DELIMITED BY SIZE
                  ") drawAt"            DELIMITED BY SIZE
               INTO PS-LINE
           PERFORM PUT-LINE
           .

       EMIT-CLIENT-SIRET.
           IF FUNCTION TRIM(CLI-SIRET) = SPACES
               EXIT PARAGRAPH
           END-IF
           MOVE SPACES TO PS-LINE
           STRING "350 676 (SIRET: "    DELIMITED BY SIZE
                  FUNCTION TRIM(CLI-SIRET)
                                        DELIMITED BY SIZE
                  ") drawAt"            DELIMITED BY SIZE
               INTO PS-LINE
           PERFORM PUT-LINE
           .

       WRITE-DATES.
           MOVE "0.40 setgray"               TO PS-LINE
           PERFORM PUT-LINE
           MOVE "/Helvetica 9 selectFont"    TO PS-LINE
           PERFORM PUT-LINE

           MOVE INV-DATE TO WS-DATE-IN
           PERFORM FORMAT-DATE-FR
           MOVE SPACES TO PS-LINE
           STRING "72 650 (Date d'emission : "
                                        DELIMITED BY SIZE
                  WS-DATE-FR            DELIMITED BY SIZE
                  ") drawAt"            DELIMITED BY SIZE
               INTO PS-LINE
           PERFORM PUT-LINE

           MOVE INV-DUE-DATE TO WS-DATE-IN
           PERFORM FORMAT-DATE-FR
           MOVE SPACES TO PS-LINE
           STRING "72 638 (Echeance        : "
                                        DELIMITED BY SIZE
                  WS-DATE-FR            DELIMITED BY SIZE
                  ") drawAt"            DELIMITED BY SIZE
               INTO PS-LINE
           PERFORM PUT-LINE
           .

      *> Line-items table.
       WRITE-TABLE-HEADER.
           MOVE "72 612 451 18 0.94 rowBg"      TO PS-LINE
           PERFORM PUT-LINE
           MOVE "0 setgray"                      TO PS-LINE
           PERFORM PUT-LINE
           MOVE "/Helvetica-Bold 10 selectFont"  TO PS-LINE
           PERFORM PUT-LINE
           MOVE "78  617 (Description) drawAt"   TO PS-LINE
           PERFORM PUT-LINE
           MOVE "350 617 (Qte)         drawAt"   TO PS-LINE
           PERFORM PUT-LINE
           MOVE "410 617 (PU HT)       drawAt"   TO PS-LINE
           PERFORM PUT-LINE
           MOVE "523 617 (Total HT)    drawRight" TO PS-LINE
           PERFORM PUT-LINE
           MOVE "72 610 523 0.4 0.6 hr"          TO PS-LINE
           PERFORM PUT-LINE
           MOVE "/Helvetica 10 selectFont"       TO PS-LINE
           PERFORM PUT-LINE
           .

       WRITE-LINE-ITEMS.
           PERFORM VARYING WS-LINE-IDX FROM 1 BY 1
                   UNTIL WS-LINE-IDX > INV-LINE-COUNT
               PERFORM EMIT-LINE-ITEM
           END-PERFORM
           .

       EMIT-LINE-ITEM.
      *>   Each row drops 25pt below the previous one.
           COMPUTE WS-LINE-Y =
               WS-FIRST-LINE-Y - (WS-LINE-IDX - 1) * WS-LINE-STEP

           MOVE "0 setgray" TO PS-LINE
           PERFORM PUT-LINE

      *>   Description
           MOVE SPACES TO PS-LINE
           STRING "78  "                DELIMITED BY SIZE
                  WS-LINE-Y             DELIMITED BY SIZE
                  " ("                  DELIMITED BY SIZE
                  FUNCTION TRIM(INV-DESC(WS-LINE-IDX))
                                        DELIMITED BY SIZE
                  ") drawAt"            DELIMITED BY SIZE
               INTO PS-LINE
           PERFORM PUT-LINE

      *>   Qty
           MOVE INV-QTY(WS-LINE-IDX) TO WS-NUM-IN
           PERFORM FORMAT-NUM-FR
           MOVE SPACES TO PS-LINE
           STRING "350 "                DELIMITED BY SIZE
                  WS-LINE-Y             DELIMITED BY SIZE
                  " ("                  DELIMITED BY SIZE
                  FUNCTION TRIM(WS-NUM-FR)
                                        DELIMITED BY SIZE
                  ") drawAt"            DELIMITED BY SIZE
               INTO PS-LINE
           PERFORM PUT-LINE

      *>   Unit rate
           MOVE INV-UNIT-RATE(WS-LINE-IDX) TO WS-NUM-IN
           PERFORM FORMAT-NUM-FR
           MOVE SPACES TO PS-LINE
           STRING "410 "                DELIMITED BY SIZE
                  WS-LINE-Y             DELIMITED BY SIZE
                  " ("                  DELIMITED BY SIZE
                  FUNCTION TRIM(WS-NUM-FR)
                                        DELIMITED BY SIZE
                  ") drawAt"            DELIMITED BY SIZE
               INTO PS-LINE
           PERFORM PUT-LINE

      *>   Line total
           MOVE INV-LINE-TOTAL(WS-LINE-IDX) TO WS-NUM-IN
           PERFORM FORMAT-NUM-FR
           MOVE SPACES TO PS-LINE
           STRING "523 "                DELIMITED BY SIZE
                  WS-LINE-Y             DELIMITED BY SIZE
                  " ("                  DELIMITED BY SIZE
                  FUNCTION TRIM(WS-NUM-FR)
                                        DELIMITED BY SIZE
                  ") drawRight"         DELIMITED BY SIZE
               INTO PS-LINE
           PERFORM PUT-LINE

      *>   Row separator (10pt below the row baseline)
           MOVE SPACES TO PS-LINE
           STRING "72 "                 DELIMITED BY SIZE
                  WS-LINE-Y             DELIMITED BY SIZE
                  " 10 sub 523 0.2 0.92 hr"
                                        DELIMITED BY SIZE
               INTO PS-LINE
           PERFORM PUT-LINE
           .

      *> Totals block (right-aligned).
       WRITE-TOTALS.
           MOVE "/Helvetica 10 selectFont"       TO PS-LINE
           PERFORM PUT-LINE
           MOVE "0 setgray"                      TO PS-LINE
           PERFORM PUT-LINE

           MOVE INV-AMOUNT-HT TO WS-NUM-IN
           PERFORM FORMAT-NUM-FR
           MOVE "380 525 (Total H.T.) drawAt"    TO PS-LINE
           PERFORM PUT-LINE
           PERFORM EMIT-RIGHT-AMOUNT-525

           MOVE INV-AMOUNT-TVA TO WS-NUM-IN
           PERFORM FORMAT-NUM-FR
           MOVE "380 510 (TVA) drawAt"           TO PS-LINE
           PERFORM PUT-LINE
           PERFORM EMIT-RIGHT-AMOUNT-510

           MOVE "380 502 523 0.6 0.3 hr"         TO PS-LINE
           PERFORM PUT-LINE

           MOVE "/Helvetica-Bold 11 selectFont"  TO PS-LINE
           PERFORM PUT-LINE
           MOVE "0 setgray"                      TO PS-LINE
           PERFORM PUT-LINE
           MOVE INV-AMOUNT-TTC TO WS-NUM-IN
           PERFORM FORMAT-NUM-FR
           MOVE "380 487 (Total T.T.C.) drawAt"  TO PS-LINE
           PERFORM PUT-LINE
           PERFORM EMIT-RIGHT-AMOUNT-487

           MOVE "380 478 523 0.3 0.5 hr"         TO PS-LINE
           PERFORM PUT-LINE

           MOVE "/Helvetica 9 selectFont"        TO PS-LINE
           PERFORM PUT-LINE
           MOVE "0.4 setgray"                    TO PS-LINE
           PERFORM PUT-LINE

           MOVE INV-URSSAF-AMOUNT TO WS-NUM-IN
           PERFORM FORMAT-NUM-FR
           MOVE "380 462 (URSSAF) drawAt"        TO PS-LINE
           PERFORM PUT-LINE
           PERFORM EMIT-RIGHT-AMOUNT-462

           MOVE INV-NET-REVENUE TO WS-NUM-IN
           PERFORM FORMAT-NUM-FR
           MOVE "380 449 (Revenu net) drawAt"    TO PS-LINE
           PERFORM PUT-LINE
           PERFORM EMIT-RIGHT-AMOUNT-449
           .

       EMIT-RIGHT-AMOUNT-525.
           MOVE 525 TO WS-LINE-Y
           PERFORM EMIT-AMOUNT-AT
           .

       EMIT-RIGHT-AMOUNT-510.
           MOVE 510 TO WS-LINE-Y
           PERFORM EMIT-AMOUNT-AT
           .

       EMIT-RIGHT-AMOUNT-487.
           MOVE 487 TO WS-LINE-Y
           PERFORM EMIT-AMOUNT-AT
           .

       EMIT-RIGHT-AMOUNT-462.
           MOVE 462 TO WS-LINE-Y
           PERFORM EMIT-AMOUNT-AT
           .

       EMIT-RIGHT-AMOUNT-449.
           MOVE 449 TO WS-LINE-Y
           PERFORM EMIT-AMOUNT-AT
           .

      *>   Helper: write `523 <y> (<WS-NUM-FR> EUR) drawRight`
      *>   where <y> = WS-LINE-Y.
       EMIT-AMOUNT-AT.
           MOVE SPACES TO PS-LINE
           STRING "523 "                DELIMITED BY SIZE
                  WS-LINE-Y             DELIMITED BY SIZE
                  " ("                  DELIMITED BY SIZE
                  FUNCTION TRIM(WS-NUM-FR)
                                        DELIMITED BY SIZE
                  " EUR) drawRight"     DELIMITED BY SIZE
               INTO PS-LINE
           PERFORM PUT-LINE
           .

      *> Legal mentions + footer.
       WRITE-LEGAL.
           MOVE "0 setgray"                          TO PS-LINE
           PERFORM PUT-LINE
           MOVE "/Helvetica-Bold 9 selectFont"       TO PS-LINE
           PERFORM PUT-LINE
           MOVE "72 405 (MENTIONS LEGALES) drawAt"   TO PS-LINE
           PERFORM PUT-LINE
           MOVE "/Helvetica 8 selectFont"            TO PS-LINE
           PERFORM PUT-LINE
           MOVE "0.30 setgray"                       TO PS-LINE
           PERFORM PUT-LINE
           MOVE SPACES TO PS-LINE
           STRING
               "72 388 (Paiement par virement bancaire "
                                                  DELIMITED BY SIZE
               "sous 30 jours.) drawAt"
                                                  DELIMITED BY SIZE
               INTO PS-LINE
           PERFORM PUT-LINE

           MOVE SPACES TO PS-LINE
           STRING
               "72 376 (IBAN : FR76 XXXX XXXX XXXX "
                                                  DELIMITED BY SIZE
               "XXXX XXXX XXX) drawAt"
                                                  DELIMITED BY SIZE
               INTO PS-LINE
           PERFORM PUT-LINE

           MOVE "72 364 (BIC  : XXXXXXXX) drawAt"    TO PS-LINE
           PERFORM PUT-LINE

           MOVE SPACES TO PS-LINE
           STRING
               "72 344 (En cas de retard, penalite "
                                                  DELIMITED BY SIZE
               "de 3 fois le taux d'interet legal) drawAt"
                                                  DELIMITED BY SIZE
               INTO PS-LINE
           PERFORM PUT-LINE

           MOVE SPACES TO PS-LINE
           STRING
               "72 332 (\(art. L441-10 du Code de commerce\). "
                                                  DELIMITED BY SIZE
               "Indemnite forfaitaire) drawAt"
                                                  DELIMITED BY SIZE
               INTO PS-LINE
           PERFORM PUT-LINE

           MOVE SPACES TO PS-LINE
           STRING
               "72 320 (de recouvrement : 40,00 EUR "
                                                  DELIMITED BY SIZE
               "\(art. D441-5\).) drawAt"
                                                  DELIMITED BY SIZE
               INTO PS-LINE
           PERFORM PUT-LINE

           MOVE SPACES TO PS-LINE
           STRING
               "72 296 (Pas d'escompte pour paiement "
                                                  DELIMITED BY SIZE
               "anticipe.) drawAt"
                                                  DELIMITED BY SIZE
               INTO PS-LINE
           PERFORM PUT-LINE
           .

       WRITE-FOOTER.
           MOVE "72 70 523 0.3 0.5 hr"               TO PS-LINE
           PERFORM PUT-LINE
           MOVE "/Helvetica 8 selectFont"            TO PS-LINE
           PERFORM PUT-LINE
           MOVE "0.55 setgray"                       TO PS-LINE
           PERFORM PUT-LINE
           MOVE SPACES TO PS-LINE
           STRING
               "72  56 (Powered by LE COBOL  -  "  DELIMITED BY SIZE
               "COBOL + PostScript + HTMX  -  "    DELIMITED BY SIZE
               "lecobol.com) drawAt"               DELIMITED BY SIZE
               INTO PS-LINE
           PERFORM PUT-LINE
           MOVE "523 56 (Page 1 / 1) drawRight"      TO PS-LINE
           PERFORM PUT-LINE
           MOVE "showpage"                           TO PS-LINE
           PERFORM PUT-LINE
           MOVE "%%Trailer"                          TO PS-LINE
           PERFORM PUT-LINE
           MOVE "%%EOF"                              TO PS-LINE
           PERFORM PUT-LINE
           .

      *> RUN-GHOSTSCRIPT
      *>
      *> Convert the .ps source into a PDF. Ghostscript flags:
      *>   -sDEVICE=pdfwrite       output device
      *>   -dNOPAUSE -dBATCH       non-interactive
      *>   -dQUIET                 suppress banner
      *>   -dPDFSETTINGS=/prepress high-quality output (embeds
      *>                           fonts, preserves vectors)
      *>
      *> Both WS-PDF-PATH and WS-PS-PATH come from BUILD-PATHS
      *> and contain only [A-Z0-9-/_.] characters, so it is safe
      *> to interpolate them straight into the shell command.
       RUN-GHOSTSCRIPT.
           MOVE SPACES TO WS-CMD
           STRING "gs -sDEVICE=pdfwrite -dNOPAUSE -dBATCH -dQUIET "
                                            DELIMITED BY SIZE
                  "-dPDFSETTINGS=/prepress -sOutputFile="
                                            DELIMITED BY SIZE
                  FUNCTION TRIM(WS-PDF-PATH)
                                            DELIMITED BY SIZE
                  " "                       DELIMITED BY SIZE
                  FUNCTION TRIM(WS-PS-PATH)
                                            DELIMITED BY SIZE
               INTO WS-CMD
           CALL "SYSTEM" USING WS-CMD
           .

      *> EMIT-REDIRECT
      *>
      *> Reply with a 302 to /pdf/INV-... .pdf so Apache serves
      *> the static file directly (no CGI roundtrip per byte).
      *> The HTML body is just a fallback link for clients that
      *> ignore Location.
       EMIT-REDIRECT.
           DISPLAY "Status: 302 Found"
           DISPLAY "Location: " FUNCTION TRIM(WS-PDF-URL)
           DISPLAY "Content-Type: text/html; charset=utf-8"
           DISPLAY X"0A"
           DISPLAY "<a href='" FUNCTION TRIM(WS-PDF-URL)
                   "'>Download</a>"
           .

      *> ----- Helpers -----

      *> PUT-LINE
      *>
      *> Append PS-LINE to the PostScript output file and reset
      *> the buffer to spaces. Most callers build PS-LINE with
      *> STRING, then call PUT-LINE.
       PUT-LINE.
           WRITE PS-LINE
           MOVE SPACES TO PS-LINE
           .

      *> FORMAT-NUM-FR
      *>
      *> WS-NUM-IN -> WS-NUM-FR with French separators (space
      *> thousands, comma decimal). The PIC ZZZ,ZZZ,ZZ9.99 edit
      *> mask produces "1,234.56"; two INSPECT passes flip ","
      *> to " " and "." to ",".
       FORMAT-NUM-FR.
           MOVE WS-NUM-IN TO WS-NUM-EDITED
           MOVE WS-NUM-EDITED TO WS-NUM-FR
           INSPECT WS-NUM-FR REPLACING ALL "," BY " "
           INSPECT WS-NUM-FR REPLACING ALL "." BY ","
           .

      *> FORMAT-DATE-FR
      *>
      *> Convert an ISO date "YYYY-MM-DD" into the French print
      *> format "DD/MM/YYYY". Falls back to a 10-char copy if
      *> the dashes are not where expected.
       FORMAT-DATE-FR.
           MOVE SPACES TO WS-DATE-FR
           IF WS-DATE-IN(5:1) = "-" AND WS-DATE-IN(8:1) = "-"
               STRING WS-DATE-IN(9:2) DELIMITED BY SIZE
                      "/"             DELIMITED BY SIZE
                      WS-DATE-IN(6:2) DELIMITED BY SIZE
                      "/"             DELIMITED BY SIZE
                      WS-DATE-IN(1:4) DELIMITED BY SIZE
                   INTO WS-DATE-FR
           ELSE
               MOVE WS-DATE-IN(1:10) TO WS-DATE-FR
           END-IF
           .

      *> ----- Error renderers -----
      *> Reached when the request is invalid or the invoice is
      *> unknown. Emit an HTML fragment rather than a redirect
      *> so the user sees what went wrong inside the app shell.

       RENDER-MISSING-NUMBER.
           DISPLAY "<div class='echo'>"
           DISPLAY "  <h2>MISSING NUMBER</h2>"
           DISPLAY "  <p>Field <code>number</code> is required."
                   "</p>"
           DISPLAY "</div>"
           .

       RENDER-NOT-FOUND.
           DISPLAY "<div class='echo'>"
           DISPLAY "  <h2>INVOICE NOT FOUND</h2>"
           DISPLAY "  <p>number="
                   FUNCTION TRIM(WS-LOOKUP-NUMBER) "</p>"
           DISPLAY "</div>"
           .

      *> Auth gate paragraphs and shared CGI helpers.
       COPY "auth-check-procs.cpy".
       COPY "cgi-utils-procs.cpy".

       END PROGRAM PDF-GEN.
