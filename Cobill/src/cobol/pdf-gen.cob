       IDENTIFICATION DIVISION.
       PROGRAM-ID. PDF-GEN.

       ENVIRONMENT DIVISION.
       CONFIGURATION SECTION.
       COPY "special-names.cpy".

       INPUT-OUTPUT SECTION.
       FILE-CONTROL.
           SELECT INVOICE-FILE
               ASSIGN TO "data/invoices.dat"
               ORGANIZATION IS INDEXED
               ACCESS MODE IS DYNAMIC
               RECORD KEY IS INV-NUMBER
               ALTERNATE RECORD KEY IS INV-CLIENT-ID
                   WITH DUPLICATES
               FILE STATUS IS WS-INV-STATUS.

           SELECT CLIENT-FILE
               ASSIGN TO "data/clients.dat"
               ORGANIZATION IS INDEXED
               ACCESS MODE IS DYNAMIC
               RECORD KEY IS CLI-ID
               ALTERNATE RECORD KEY IS CLI-NAME
                   WITH DUPLICATES
               FILE STATUS IS WS-CLI-STATUS.

           SELECT PROLOG-FILE
               ASSIGN TO "src/postscript/prolog.ps"
               ORGANIZATION IS LINE SEQUENTIAL
               FILE STATUS IS WS-PROLOG-STATUS.

           SELECT PS-FILE
               ASSIGN TO WS-PS-PATH
               ORGANIZATION IS LINE SEQUENTIAL
               FILE STATUS IS WS-PS-STATUS.

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

       01 WS-INV-STATUS    PIC XX.
       01 WS-CLI-STATUS    PIC XX.
       01 WS-PROLOG-STATUS PIC XX.
       01 WS-PS-STATUS     PIC XX.
       01 WS-EOF           PIC X VALUE "N".

       01 WS-LOOKUP-NUMBER PIC X(9).
       01 WS-PS-PATH       PIC X(64).
       01 WS-PDF-PATH      PIC X(64).
       01 WS-PDF-URL       PIC X(64).
       01 WS-CMD           PIC X(256).
       01 WS-RC            PIC S9(4).

      *> ---- French amount formatter ------------------------------------
      *> Numeric input -> "1 234,56" (FR locale: space thousand, comma dec)
       01 WS-NUM-IN        PIC 9(9)V99.
       01 WS-NUM-EDITED    PIC ZZZ,ZZZ,ZZ9.99.
       01 WS-NUM-FR        PIC X(15).

      *> ---- Date formatter --------------------------------------------
       01 WS-DATE-IN       PIC X(10).
       01 WS-DATE-FR       PIC X(10).

      *> ---- Loop counters ---------------------------------------------
       01 WS-LINE-IDX      PIC 99.
       01 WS-LINE-Y        PIC 9(4).
       01 WS-FIRST-LINE-Y  PIC 9(4) VALUE 590.
       01 WS-LINE-STEP     PIC 9(2) VALUE 25.

      *> ---- Pre-built PS strings (built once, written many times) ------
       01 WS-PS-BUF        PIC X(200).

       PROCEDURE DIVISION.
      *> MAIN — read invoice, build .ps, run gs, redirect to PDF.
       MAIN-LOGIC.
           PERFORM READ-CGI-INPUT
           PERFORM PARSE-CGI-INPUT
           COPY "auth-check.cpy".

           MOVE "number" TO CGI-L-KEY
           PERFORM FIND-FIELD
           IF CGI-L-FOUND NOT = "Y"
                   OR FUNCTION TRIM(CGI-L-VALUE) = SPACES
               PERFORM EMIT-HTML-HEADERS
               PERFORM RENDER-MISSING-NUMBER
               STOP RUN
           END-IF
           MOVE FUNCTION TRIM(CGI-L-VALUE) TO WS-LOOKUP-NUMBER

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

      *> Load invoice by primary key (INV-NUMBER).
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

      *> Pull full client address from clients.dat (the invoice
      *> only stores CLI-ID + CLI-NAME).
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

      *> Build the file paths for this invoice.
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

      *> Write the full PostScript document.
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

      *> Run Ghostscript on the .ps to produce the .pdf.
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

      *> Return a 302 redirect so the browser fetches the static PDF.
       EMIT-REDIRECT.
           DISPLAY "Status: 302 Found"
           DISPLAY "Location: " FUNCTION TRIM(WS-PDF-URL)
           DISPLAY "Content-Type: text/html; charset=utf-8"
           DISPLAY X"0A"
           DISPLAY "<a href='" FUNCTION TRIM(WS-PDF-URL)
                   "'>Download</a>"
           .

      *> Helpers used by callers above.
       PUT-LINE.
           WRITE PS-LINE
           MOVE SPACES TO PS-LINE
           .

       FORMAT-NUM-FR.
      *>   Numeric WS-NUM-IN -> FR-formatted string in WS-NUM-FR.
      *>   "1234.56" -> "1 234,56" (space thousand, comma decimal).
           MOVE WS-NUM-IN TO WS-NUM-EDITED
           MOVE WS-NUM-EDITED TO WS-NUM-FR
           INSPECT WS-NUM-FR REPLACING ALL "," BY " "
           INSPECT WS-NUM-FR REPLACING ALL "." BY ","
           .

       FORMAT-DATE-FR.
      *>   "YYYY-MM-DD" -> "DD/MM/YYYY"
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

      *> Error renderers (HTML output, not redirect).
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

       COPY "auth-check-procs.cpy".
       COPY "cgi-utils-procs.cpy".

       END PROGRAM PDF-GEN.
