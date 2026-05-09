       IDENTIFICATION DIVISION.
       PROGRAM-ID. INVOICE.

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
       FD SESSION-FILE.
       COPY "session-record.cpy".

       WORKING-STORAGE SECTION.
       COPY "cgi-utils-ws.cpy".
       COPY "auth-check-ws.cpy".

       01  WS-INV-STATUS           PIC XX.
       01  WS-CLI-STATUS           PIC XX.
       01  WS-ACTION               PIC X(10) VALUE "list".
       01  WS-EOF                  PIC X     VALUE "N".
       01  WS-ROW-COUNT            PIC 9(4)  VALUE 0.

      *> List filters + buffer for reverse-chronological emit.
       01  WS-FILTER-Q             PIC X(50).
       01  WS-FILTER-Q-LOWER       PIC X(50).
       01  WS-FILTER-Q-LEN         PIC 9(3) VALUE 0.
       01  WS-FILTER-STATUS        PIC X(8).
       01  WS-LOWER-NAME           PIC X(50).
       01  WS-SCAN-IDX             PIC 9(3).
       01  WS-MATCHED              PIC X.
       01  WS-STATUS-LBL           PIC X(8).
       01  WS-OUTSTANDING          PIC 9(9)V99 VALUE 0.
       01  WS-DISP-OUTSTANDING     PIC ZZZ,ZZZ,ZZ9.99.

       01  WS-INV-COUNT            PIC 9(4) VALUE 0.
       01  WS-INV-IDX              PIC 9(4) VALUE 0.
       01  WS-INV-BUF.
           05  WS-BUF OCCURS 200 TIMES.
               10  BUF-NUMBER      PIC X(9).
               10  BUF-CLIENT      PIC X(50).
               10  BUF-DATE        PIC X(10).
               10  BUF-DUE-DATE    PIC X(10).
               10  BUF-TTC         PIC 9(7)V99.
               10  BUF-STATUS      PIC X(8).
               10  BUF-EFFECTIVE   PIC X(8).

       01  WS-DATE-FR              PIC X(10).

       01  WS-LOOKUP-NUMBER        PIC X(9).
       01  WS-LOOKUP-ID            PIC X(10).
       01  WS-NEW-STATUS           PIC X(8).
       01  WS-TODAY-FMT            PIC X(10).
       01  WS-EFFECTIVE-STATUS     PIC X(8).
       01  WS-DAYS-INT             PIC S9(8).
       01  WS-A-DATE               PIC 9(8).
       01  WS-B-DATE               PIC 9(8).
       01  WS-A-INT                PIC S9(8).
       01  WS-B-INT                PIC S9(8).
       01  WS-DAYS-LATE            PIC ZZZ9.

      *> Year + sequence for auto-numbering (YYYY-NNNN).
       01  WS-YEAR                 PIC 9(4).
       01  WS-NEXT-SEQ             PIC 9(4)  VALUE 0.
       01  WS-CUR-SEQ              PIC 9(4)  VALUE 0.

      *> Numeric parsing helpers.
       01  WS-NUM-RAW              PIC X(20).
       01  WS-QTY                  PIC 9(4)V99.
       01  WS-RATE                 PIC 9(5)V99.
       01  WS-LINE-TOTAL           PIC 9(7)V99.
       01  WS-TVA-RATE             PIC V9999.
       01  WS-URSSAF-RATE          PIC V9999  VALUE 0.2200.

      *> Scratch fields for accumulating line totals.
       01  WS-LINE-IDX             PIC 99.
       01  WS-LINE-KEY             PIC X(8).

      *> Current date helpers (today / today + 30).
       01  WS-DATE-RAW             PIC 9(8).
       01  WS-DATE-INT             PIC 9(8).
       01  WS-DATE-FMT             PIC X(10).

      *> Display-edited amounts (ZZZ,ZZ9.99).
       01  WS-DISP-HT              PIC ZZZZ,ZZ9.99.
       01  WS-DISP-TVA             PIC ZZZZ,ZZ9.99.
       01  WS-DISP-TTC             PIC ZZZZ,ZZ9.99.
       01  WS-DISP-URSSAF          PIC ZZZZ,ZZ9.99.
       01  WS-DISP-NET             PIC ZZZZ,ZZ9.99.
       01  WS-DISP-LINE            PIC ZZZZ,ZZ9.99.
       01  WS-DISP-QTY             PIC ZZZ9.99.
       01  WS-DISP-RATE            PIC ZZZZ9.99.

       PROCEDURE DIVISION.
       MAIN-LOGIC.
           PERFORM READ-CGI-INPUT
           PERFORM PARSE-CGI-INPUT
           COPY "auth-check.cpy".
           PERFORM EMIT-HTML-HEADERS

           MOVE "action" TO CGI-L-KEY
           PERFORM FIND-FIELD
           IF CGI-L-FOUND = "Y"
               MOVE FUNCTION TRIM(CGI-L-VALUE) TO WS-ACTION
           END-IF

           EVALUATE FUNCTION TRIM(WS-ACTION)
               WHEN "list"
                   PERFORM ACTION-LIST
               WHEN "new"
                   PERFORM ACTION-NEW
               WHEN "create"
                   PERFORM ACTION-CREATE
               WHEN "get"
                   PERFORM ACTION-GET
               WHEN "mark-sent"
                   MOVE "SENT"  TO WS-NEW-STATUS
                   PERFORM ACTION-CHANGE-STATUS
               WHEN "mark-paid"
                   MOVE "PAID"  TO WS-NEW-STATUS
                   PERFORM ACTION-CHANGE-STATUS
               WHEN "reopen"
                   MOVE "SENT"  TO WS-NEW-STATUS
                   PERFORM ACTION-CHANGE-STATUS
               WHEN OTHER
                   PERFORM RENDER-UNKNOWN-ACTION
           END-EVALUATE

           STOP RUN.

      *> ACTION-LIST — filterable, reverse-chronological table.
      *> Always emits the whole panel; the filter form uses
      *> hx-select to inject only #invoices-results so input focus
      *> is preserved across keystrokes.
       ACTION-LIST.
           PERFORM LOAD-LIST-FILTERS
           PERFORM LOAD-INVOICES-INTO-BUFFER

           DISPLAY "<section class='panel' id='invoices-panel'>"
           DISPLAY "  <header class='panel-head'>"
           DISPLAY "    <h2>INVOICES</h2>"
           DISPLAY "    <button class='btn-primary'"
           DISPLAY "            hx-get='/cgi-bin/invoice"
                   "?action=new'"
           DISPLAY "            hx-target='#content'"
           DISPLAY "            hx-swap='innerHTML'>"
           DISPLAY "      [+ NEW INVOICE]"
           DISPLAY "    </button>"
           DISPLAY "  </header>"

           PERFORM RENDER-FILTERS
           PERFORM RENDER-RESULTS

           DISPLAY "</section>"
           .

       RENDER-FILTERS.
           MOVE FUNCTION TRIM(WS-FILTER-Q) TO HTML-IN
           PERFORM HTML-ESCAPE

           DISPLAY "  <form class='filters'"
           DISPLAY "        hx-get='/cgi-bin/invoice?action=list'"
           DISPLAY "        hx-target='#invoices-results'"
           DISPLAY "        hx-swap='outerHTML'"
           DISPLAY "        hx-select='#invoices-results'"
           DISPLAY "        hx-trigger='input changed "
                   "delay:300ms, change'>"

           DISPLAY "    <input type='search' name='q'"
           DISPLAY "           placeholder='search client...'"
           DISPLAY "           value='"
                   HTML-OUT(1:HTML-OUT-LEN) "'>"

           DISPLAY "    <select name='status'>"
           PERFORM RENDER-STATUS-OPTIONS
           DISPLAY "    </select>"

           DISPLAY "  </form>"
           .

       RENDER-STATUS-OPTIONS.
           PERFORM RENDER-STATUS-OPTION-ALL
           MOVE "DRAFT"   TO WS-STATUS-LBL
           PERFORM RENDER-STATUS-OPTION
           MOVE "SENT"    TO WS-STATUS-LBL
           PERFORM RENDER-STATUS-OPTION
           MOVE "PAID"    TO WS-STATUS-LBL
           PERFORM RENDER-STATUS-OPTION
           MOVE "OVERDUE" TO WS-STATUS-LBL
           PERFORM RENDER-STATUS-OPTION
           .

       RENDER-STATUS-OPTION-ALL.
           IF FUNCTION TRIM(WS-FILTER-STATUS) = SPACES
               DISPLAY "      <option value='' selected>"
                       "all statuses</option>"
           ELSE
               DISPLAY "      <option value=''>"
                       "all statuses</option>"
           END-IF
           .

       RENDER-STATUS-OPTION.
      *>   WS-STATUS-LBL holds the option label; mark selected if
      *>   it matches the current filter.
           IF FUNCTION TRIM(WS-FILTER-STATUS)
              = FUNCTION TRIM(WS-STATUS-LBL)
               DISPLAY "      <option value='"
                       FUNCTION TRIM(WS-STATUS-LBL)
                       "' selected>"
                       FUNCTION TRIM(WS-STATUS-LBL)
                       "</option>"
           ELSE
               DISPLAY "      <option value='"
                       FUNCTION TRIM(WS-STATUS-LBL)
                       "'>"
                       FUNCTION TRIM(WS-STATUS-LBL)
                       "</option>"
           END-IF
           .

       RENDER-RESULTS.
           DISPLAY "  <div id='invoices-results'>"

           IF WS-INV-COUNT = 0
               IF FUNCTION TRIM(WS-FILTER-Q) = SPACES
                       AND FUNCTION TRIM(WS-FILTER-STATUS) = SPACES
                   DISPLAY "    <p><em>No invoices yet.</em></p>"
               ELSE
                   DISPLAY "    <p><em>No matches.</em></p>"
               END-IF
           ELSE
               PERFORM RENDER-RESULTS-TABLE
           END-IF

           DISPLAY "  </div>"
           .

       RENDER-RESULTS-TABLE.
           DISPLAY "    <table>"
           DISPLAY "      <thead><tr>"
           DISPLAY "        <th>NUMBER</th>"
           DISPLAY "        <th>CLIENT</th>"
           DISPLAY "        <th>DATE</th>"
           DISPLAY "        <th class='num'>AMOUNT TTC</th>"
           DISPLAY "        <th>STATUS</th>"
           DISPLAY "        <th>ACTIONS</th>"
           DISPLAY "      </tr></thead>"
           DISPLAY "      <tbody>"

      *>   Emit buffered rows in reverse order (newest first).
           PERFORM VARYING WS-INV-IDX FROM WS-INV-COUNT BY -1
                   UNTIL WS-INV-IDX < 1
               PERFORM RENDER-BUFFERED-ROW
           END-PERFORM

           DISPLAY "      </tbody>"
           DISPLAY "    </table>"

           MOVE WS-OUTSTANDING TO WS-DISP-OUTSTANDING
           DISPLAY "    <p class='list-footer'>"
                   WS-INV-COUNT " invoice(s) "
                   "&middot; outstanding "
                   FUNCTION TRIM(WS-DISP-OUTSTANDING)
                   " EUR</p>"
           .

       RENDER-BUFFERED-ROW.
           DISPLAY "        <tr>"

           MOVE BUF-NUMBER(WS-INV-IDX) TO HTML-IN
           PERFORM HTML-ESCAPE
           DISPLAY "          <td>"
                   HTML-OUT(1:HTML-OUT-LEN) "</td>"

           MOVE BUF-CLIENT(WS-INV-IDX) TO HTML-IN
           PERFORM HTML-ESCAPE
           DISPLAY "          <td>"
                   HTML-OUT(1:HTML-OUT-LEN) "</td>"

           MOVE BUF-DATE(WS-INV-IDX) TO HTML-IN
           PERFORM FORMAT-DATE-FR
           DISPLAY "          <td>" WS-DATE-FR "</td>"

           MOVE BUF-TTC(WS-INV-IDX) TO WS-DISP-TTC
           DISPLAY "          <td class='num'>"
                   FUNCTION TRIM(WS-DISP-TTC) " EUR</td>"

           DISPLAY "          <td><span class='badge badge-"
                   FUNCTION LOWER-CASE(
                       FUNCTION TRIM(BUF-EFFECTIVE(WS-INV-IDX)))
                   "'>"
                   FUNCTION TRIM(BUF-EFFECTIVE(WS-INV-IDX))
                   "</span></td>"

           DISPLAY "          <td class='row-actions'>"
           DISPLAY "            <button class='btn'"
           DISPLAY "                    hx-get='/cgi-bin/invoice"
                   "?action=get&number="
                   FUNCTION TRIM(BUF-NUMBER(WS-INV-IDX)) "'"
           DISPLAY "                    hx-target='#content'"
           DISPLAY "                    hx-swap='innerHTML'>"
           DISPLAY "              [VIEW]"
           DISPLAY "            </button>"

           IF FUNCTION TRIM(BUF-STATUS(WS-INV-IDX)) NOT = "PAID"
               DISPLAY "            <button class='btn btn-paid'"
               DISPLAY "                    hx-post='/cgi-bin/inv"
                       "oice?action=mark-paid&number="
                       FUNCTION TRIM(BUF-NUMBER(WS-INV-IDX)) "'"
               DISPLAY "                    hx-target='#content'"
               DISPLAY "                    hx-swap='innerHTML'"
               DISPLAY "                    hx-confirm='Mark "
                       FUNCTION TRIM(BUF-NUMBER(WS-INV-IDX))
                       " as paid?'>"
               DISPLAY "              [&check; PAID]"
               DISPLAY "            </button>"
           END-IF
           DISPLAY "          </td>"

           DISPLAY "        </tr>"
           .

      *> Pull q + status from CGI, lowercase q for case-insensitive
      *> match, record its effective length.
       LOAD-LIST-FILTERS.
           MOVE SPACES TO WS-FILTER-Q
           MOVE SPACES TO WS-FILTER-Q-LOWER
           MOVE 0      TO WS-FILTER-Q-LEN
           MOVE SPACES TO WS-FILTER-STATUS

           MOVE "q" TO CGI-L-KEY
           PERFORM FIND-FIELD
           IF CGI-L-FOUND = "Y"
               MOVE CGI-L-VALUE TO WS-FILTER-Q
               MOVE FUNCTION LOWER-CASE(WS-FILTER-Q)
                   TO WS-FILTER-Q-LOWER
               INSPECT WS-FILTER-Q-LOWER TALLYING WS-FILTER-Q-LEN
                   FOR CHARACTERS BEFORE INITIAL SPACE
           END-IF

           MOVE "status" TO CGI-L-KEY
           PERFORM FIND-FIELD
           IF CGI-L-FOUND = "Y"
               MOVE FUNCTION TRIM(CGI-L-VALUE) TO WS-FILTER-STATUS
           END-IF
           .

      *> Read every invoice, apply filters, buffer matches in
      *> primary-key order (oldest first). The renderer walks the
      *> buffer backwards so the newest comes out on top.
       LOAD-INVOICES-INTO-BUFFER.
           MOVE 0 TO WS-INV-COUNT
           MOVE 0 TO WS-OUTSTANDING
           PERFORM COMPUTE-TODAY

           OPEN INPUT INVOICE-FILE
           IF WS-INV-STATUS NOT = "00"
               EXIT PARAGRAPH
           END-IF

           MOVE "N" TO WS-EOF
           PERFORM UNTIL WS-EOF = "Y"
                      OR WS-INV-COUNT >= 200
               READ INVOICE-FILE NEXT RECORD
                   AT END
                       MOVE "Y" TO WS-EOF
                   NOT AT END
                       PERFORM EVAL-AND-BUFFER
               END-READ
           END-PERFORM

           CLOSE INVOICE-FILE
           .

       EVAL-AND-BUFFER.
      *>   Apply status filter.
           IF FUNCTION TRIM(WS-FILTER-STATUS) NOT = SPACES
               IF FUNCTION TRIM(INV-STATUS)
                  NOT = FUNCTION TRIM(WS-FILTER-STATUS)
                   EXIT PARAGRAPH
               END-IF
           END-IF

      *>   Apply client-name substring filter (case-insensitive).
           IF WS-FILTER-Q-LEN > 0
               MOVE FUNCTION LOWER-CASE(INV-CLIENT-NAME)
                   TO WS-LOWER-NAME
               PERFORM SCAN-CLIENT-MATCH
               IF WS-MATCHED NOT = "Y"
                   EXIT PARAGRAPH
               END-IF
           END-IF

           ADD 1 TO WS-INV-COUNT
           MOVE INV-NUMBER       TO BUF-NUMBER(WS-INV-COUNT)
           MOVE INV-CLIENT-NAME  TO BUF-CLIENT(WS-INV-COUNT)
           MOVE INV-DATE         TO BUF-DATE(WS-INV-COUNT)
           MOVE INV-DUE-DATE     TO BUF-DUE-DATE(WS-INV-COUNT)
           MOVE INV-AMOUNT-TTC   TO BUF-TTC(WS-INV-COUNT)
           MOVE INV-STATUS       TO BUF-STATUS(WS-INV-COUNT)

      *>   Compute the displayed status: stored unless overdue.
           PERFORM COMPUTE-EFFECTIVE-STATUS
           MOVE WS-EFFECTIVE-STATUS TO BUF-EFFECTIVE(WS-INV-COUNT)

           IF FUNCTION TRIM(INV-STATUS) NOT = "PAID"
               ADD INV-AMOUNT-TTC TO WS-OUTSTANDING
           END-IF
           .

      *> Today's date as YYYY-MM-DD, for lexicographic compare.
       COMPUTE-TODAY.
           MOVE SPACES TO WS-TODAY-FMT
           STRING FUNCTION CURRENT-DATE(1:4) DELIMITED BY SIZE
                  "-"                        DELIMITED BY SIZE
                  FUNCTION CURRENT-DATE(5:2) DELIMITED BY SIZE
                  "-"                        DELIMITED BY SIZE
                  FUNCTION CURRENT-DATE(7:2) DELIMITED BY SIZE
               INTO WS-TODAY-FMT
           .

      *> Effective status: stored value, except SENT/DRAFT past due
      *> become OVERDUE for display purposes only.
       COMPUTE-EFFECTIVE-STATUS.
           MOVE INV-STATUS TO WS-EFFECTIVE-STATUS
           IF FUNCTION TRIM(INV-STATUS) NOT = "PAID"
                   AND INV-DUE-DATE NOT = SPACES
                   AND INV-DUE-DATE < WS-TODAY-FMT
               MOVE "OVERDUE" TO WS-EFFECTIVE-STATUS
           END-IF
           .

      *> ACTION-CHANGE-STATUS — REWRITE one invoice with WS-NEW-STATUS.
      *> Sets / clears INV-PAID-DATE depending on the target status.
       ACTION-CHANGE-STATUS.
           MOVE "number" TO CGI-L-KEY
           PERFORM FIND-FIELD
           IF CGI-L-FOUND NOT = "Y"
                   OR FUNCTION TRIM(CGI-L-VALUE) = SPACES
               PERFORM RENDER-UNKNOWN-ACTION
               EXIT PARAGRAPH
           END-IF
           MOVE FUNCTION TRIM(CGI-L-VALUE) TO WS-LOOKUP-NUMBER

           OPEN I-O INVOICE-FILE
           IF WS-INV-STATUS NOT = "00"
               PERFORM RENDER-NOT-FOUND
               EXIT PARAGRAPH
           END-IF

           MOVE WS-LOOKUP-NUMBER TO INV-NUMBER
           READ INVOICE-FILE
               INVALID KEY
                   CLOSE INVOICE-FILE
                   PERFORM RENDER-NOT-FOUND
                   EXIT PARAGRAPH
               NOT INVALID KEY
                   MOVE WS-NEW-STATUS TO INV-STATUS
                   IF FUNCTION TRIM(WS-NEW-STATUS) = "PAID"
                       PERFORM COMPUTE-TODAY
                       MOVE WS-TODAY-FMT TO INV-PAID-DATE
                   ELSE
                       MOVE SPACES TO INV-PAID-DATE
                   END-IF
                   REWRITE INVOICE-RECORD
                       INVALID KEY
                           CLOSE INVOICE-FILE
                           PERFORM RENDER-WRITE-ERROR
                           EXIT PARAGRAPH
                       NOT INVALID KEY
                           CONTINUE
                   END-REWRITE
           END-READ

           CLOSE INVOICE-FILE
           PERFORM ACTION-LIST
           .

      *> Substring scan: does WS-LOWER-NAME contain
      *> WS-FILTER-Q-LOWER(1:WS-FILTER-Q-LEN)?
       SCAN-CLIENT-MATCH.
           MOVE "N" TO WS-MATCHED
           PERFORM VARYING WS-SCAN-IDX FROM 1 BY 1
                   UNTIL WS-SCAN-IDX
                       > 50 - WS-FILTER-Q-LEN + 1
                      OR WS-MATCHED = "Y"
               IF WS-LOWER-NAME(WS-SCAN-IDX:WS-FILTER-Q-LEN)
                  = WS-FILTER-Q-LOWER(1:WS-FILTER-Q-LEN)
                   MOVE "Y" TO WS-MATCHED
               END-IF
           END-PERFORM
           .

      *> "YYYY-MM-DD" -> "DD/MM/YYYY". Falls back to source on bad
      *> input.
       FORMAT-DATE-FR.
           MOVE SPACES TO WS-DATE-FR
           IF HTML-IN(5:1) = "-" AND HTML-IN(8:1) = "-"
               STRING HTML-IN(9:2) DELIMITED BY SIZE
                      "/"          DELIMITED BY SIZE
                      HTML-IN(6:2) DELIMITED BY SIZE
                      "/"          DELIMITED BY SIZE
                      HTML-IN(1:4) DELIMITED BY SIZE
                   INTO WS-DATE-FR
           ELSE
               MOVE HTML-IN(1:10) TO WS-DATE-FR
           END-IF
           .

      *> ACTION-NEW — empty invoice form. Builds a client dropdown
      *> by reading clients.dat sequentially.
       ACTION-NEW.
           PERFORM COMPUTE-DEFAULT-DATES

           DISPLAY "<section class='panel'>"
           DISPLAY "  <h2>NEW INVOICE</h2>"
           DISPLAY "  <form hx-post='/cgi-bin/invoice"
                   "?action=create'"
           DISPLAY "        hx-target='#content'"
           DISPLAY "        hx-swap='innerHTML'>"

           DISPLAY "    <div class='form-row'>"
           DISPLAY "      <label for='f-client'>CLIENT....:"
                   "</label>"
           DISPLAY "      <select id='f-client' name='client_id'"
                   " required>"
           DISPLAY "        <option value=''>"
                   "&mdash; pick a client &mdash;</option>"
           PERFORM EMIT-CLIENT-OPTIONS
           DISPLAY "      </select>"
           DISPLAY "    </div>"

           DISPLAY "    <div class='form-row form-row-double'>"
           DISPLAY "      <label for='f-date'>DATE......:</label>"
           DISPLAY "      <input id='f-date' name='date'"
                   " type='date' required value='"
                   WS-DATE-FMT "'>"
           PERFORM ADVANCE-DATE-30
           DISPLAY "      <input id='f-due' name='due_date'"
                   " type='date' required value='"
                   WS-DATE-FMT "'>"
           DISPLAY "    </div>"

           DISPLAY "    <div class='form-row'>"
           DISPLAY "      <label for='f-tva'>TVA RATE..:</label>"
           DISPLAY "      <select id='f-tva' name='tva_rate'>"
           DISPLAY "        <option value='0.20' selected>"
                   "20% (standard)</option>"
           DISPLAY "        <option value='0.10'>"
                   "10% (intermediate)</option>"
           DISPLAY "        <option value='0.055'>"
                   "5.5% (reduced)</option>"
           DISPLAY "        <option value='0.00'>"
                   "0% (art. 293 B / franchise)</option>"
           DISPLAY "      </select>"
           DISPLAY "    </div>"

           DISPLAY "    <h3>LINE ITEMS</h3>"
           DISPLAY "    <table class='line-items'>"
           DISPLAY "      <thead><tr>"
           DISPLAY "        <th>#</th>"
           DISPLAY "        <th>DESCRIPTION</th>"
           DISPLAY "        <th>QTY</th>"
           DISPLAY "        <th>UNIT RATE (EUR)</th>"
           DISPLAY "      </tr></thead>"
           DISPLAY "      <tbody>"
           PERFORM EMIT-EMPTY-LINE-ROWS
           DISPLAY "      </tbody>"
           DISPLAY "    </table>"

           DISPLAY "    <div class='form-actions'>"
           DISPLAY "      <button type='submit' "
                   "class='btn-primary'>[CREATE INVOICE]</button>"
           DISPLAY "      <button type='button' class='btn'"
           DISPLAY "              hx-get='/cgi-bin/invoice"
                   "?action=list'"
           DISPLAY "              hx-target='#content'"
           DISPLAY "              hx-swap='innerHTML'>"
           DISPLAY "        [CANCEL]"
           DISPLAY "      </button>"
           DISPLAY "    </div>"

           DISPLAY "  </form>"
           DISPLAY "</section>"
           .

       EMIT-CLIENT-OPTIONS.
           OPEN INPUT CLIENT-FILE
           IF WS-CLI-STATUS NOT = "00"
               EXIT PARAGRAPH
           END-IF

           MOVE "N" TO WS-EOF
           PERFORM UNTIL WS-EOF = "Y"
               READ CLIENT-FILE NEXT RECORD
                   AT END
                       MOVE "Y" TO WS-EOF
                   NOT AT END
                       IF CLI-DELETED NOT = "Y"
                           PERFORM RENDER-CLIENT-OPTION
                       END-IF
               END-READ
           END-PERFORM

           CLOSE CLIENT-FILE
           .

       RENDER-CLIENT-OPTION.
           MOVE CLI-NAME TO HTML-IN
           PERFORM HTML-ESCAPE
           DISPLAY "        <option value='"
                   FUNCTION TRIM(CLI-ID) "'>"
                   FUNCTION TRIM(CLI-ID) " &mdash; "
                   HTML-OUT(1:HTML-OUT-LEN)
                   "</option>"
           .

       EMIT-EMPTY-LINE-ROWS.
           PERFORM VARYING WS-LINE-IDX FROM 1 BY 1
                   UNTIL WS-LINE-IDX > 5
               DISPLAY "        <tr>"
               DISPLAY "          <td>" WS-LINE-IDX "</td>"
               DISPLAY "          <td><input name='desc"
                       WS-LINE-IDX "'></td>"
               DISPLAY "          <td><input name='qty"
                       WS-LINE-IDX "' type='number' "
                       "step='0.01' min='0'></td>"
               DISPLAY "          <td><input name='rate"
                       WS-LINE-IDX "' type='number' "
                       "step='0.01' min='0'></td>"
               DISPLAY "        </tr>"
           END-PERFORM
           .

      *> ACTION-CREATE — read form, compute, write, render summary.
       ACTION-CREATE.
           PERFORM ASSIGN-NEXT-NUMBER

           PERFORM OPEN-INVOICE-FILE-IO
           IF WS-INV-STATUS NOT = "00"
               PERFORM RENDER-WRITE-ERROR
               EXIT PARAGRAPH
           END-IF

           INITIALIZE INVOICE-RECORD
           MOVE WS-LOOKUP-NUMBER TO INV-NUMBER

           MOVE "client_id" TO CGI-L-KEY
           PERFORM FIND-FIELD
           MOVE FUNCTION TRIM(CGI-L-VALUE) TO INV-CLIENT-ID

           PERFORM LOOKUP-CLIENT-NAME

           MOVE "date" TO CGI-L-KEY
           PERFORM FIND-FIELD
           MOVE CGI-L-VALUE TO INV-DATE

           MOVE "due_date" TO CGI-L-KEY
           PERFORM FIND-FIELD
           MOVE CGI-L-VALUE TO INV-DUE-DATE

           MOVE "tva_rate" TO CGI-L-KEY
           PERFORM FIND-FIELD
           MOVE CGI-L-VALUE TO WS-NUM-RAW
           PERFORM PARSE-NUMERIC-RATE
           MOVE WS-TVA-RATE TO INV-TVA-RATE

           MOVE WS-URSSAF-RATE TO INV-URSSAF-RATE

      *>   Read up to 5 line items, accumulate amount HT.
           MOVE 0 TO INV-AMOUNT-HT
           MOVE 0 TO INV-LINE-COUNT
           PERFORM VARYING WS-LINE-IDX FROM 1 BY 1
                   UNTIL WS-LINE-IDX > 5
               PERFORM READ-LINE-ITEM
           END-PERFORM

      *>   Calculations.
           COMPUTE INV-AMOUNT-TVA ROUNDED =
               INV-AMOUNT-HT * INV-TVA-RATE
           ADD INV-AMOUNT-HT INV-AMOUNT-TVA
               GIVING INV-AMOUNT-TTC
           COMPUTE INV-URSSAF-AMOUNT ROUNDED =
               INV-AMOUNT-HT * INV-URSSAF-RATE
           SUBTRACT INV-URSSAF-AMOUNT FROM INV-AMOUNT-HT
               GIVING INV-NET-REVENUE

           MOVE "DRAFT" TO INV-STATUS
           PERFORM COMPUTE-TODAY
           MOVE WS-TODAY-FMT TO INV-CREATED

           WRITE INVOICE-RECORD
               INVALID KEY
                   CLOSE INVOICE-FILE
                   PERFORM RENDER-WRITE-ERROR
                   EXIT PARAGRAPH
               NOT INVALID KEY
                   CONTINUE
           END-WRITE

           CLOSE INVOICE-FILE
           PERFORM RENDER-CREATE-SUMMARY
           .

       READ-LINE-ITEM.
           MOVE SPACES TO WS-LINE-KEY
           STRING "desc" DELIMITED BY SIZE
                  WS-LINE-IDX DELIMITED BY SIZE
               INTO WS-LINE-KEY

           MOVE WS-LINE-KEY TO CGI-L-KEY
           PERFORM FIND-FIELD
           IF CGI-L-FOUND NOT = "Y"
               EXIT PARAGRAPH
           END-IF
           IF FUNCTION TRIM(CGI-L-VALUE) = SPACES
               EXIT PARAGRAPH
           END-IF
           MOVE CGI-L-VALUE TO INV-DESC(WS-LINE-IDX)

           MOVE SPACES TO WS-LINE-KEY
           STRING "qty" DELIMITED BY SIZE
                  WS-LINE-IDX DELIMITED BY SIZE
               INTO WS-LINE-KEY
           MOVE WS-LINE-KEY TO CGI-L-KEY
           PERFORM FIND-FIELD
           MOVE CGI-L-VALUE TO WS-NUM-RAW
           PERFORM PARSE-NUMERIC-QTY
           MOVE WS-QTY TO INV-QTY(WS-LINE-IDX)

           MOVE SPACES TO WS-LINE-KEY
           STRING "rate" DELIMITED BY SIZE
                  WS-LINE-IDX DELIMITED BY SIZE
               INTO WS-LINE-KEY
           MOVE WS-LINE-KEY TO CGI-L-KEY
           PERFORM FIND-FIELD
           MOVE CGI-L-VALUE TO WS-NUM-RAW
           PERFORM PARSE-NUMERIC-RATE-AMOUNT
           MOVE WS-RATE TO INV-UNIT-RATE(WS-LINE-IDX)

           COMPUTE INV-LINE-TOTAL(WS-LINE-IDX) ROUNDED =
               WS-QTY * WS-RATE

           ADD INV-LINE-TOTAL(WS-LINE-IDX) TO INV-AMOUNT-HT
           ADD 1 TO INV-LINE-COUNT
           .

      *> ACTION-GET — read + render one invoice.
       ACTION-GET.
           MOVE "number" TO CGI-L-KEY
           PERFORM FIND-FIELD
           IF CGI-L-FOUND NOT = "Y"
                   OR FUNCTION TRIM(CGI-L-VALUE) = SPACES
               PERFORM RENDER-NOT-FOUND
               EXIT PARAGRAPH
           END-IF
           MOVE FUNCTION TRIM(CGI-L-VALUE) TO WS-LOOKUP-NUMBER

           OPEN INPUT INVOICE-FILE
           IF WS-INV-STATUS NOT = "00"
               PERFORM RENDER-NOT-FOUND
               EXIT PARAGRAPH
           END-IF

           MOVE WS-LOOKUP-NUMBER TO INV-NUMBER
           READ INVOICE-FILE
               INVALID KEY
                   CLOSE INVOICE-FILE
                   PERFORM RENDER-NOT-FOUND
                   EXIT PARAGRAPH
               NOT INVALID KEY
                   CLOSE INVOICE-FILE
                   PERFORM RENDER-INVOICE-DETAIL
           END-READ
           .

       RENDER-INVOICE-DETAIL.
           PERFORM COMPUTE-TODAY
           PERFORM COMPUTE-EFFECTIVE-STATUS

           DISPLAY "<section class='panel'>"
           DISPLAY "  <header class='panel-head'>"
           DISPLAY "    <h2>INVOICE "
                   FUNCTION TRIM(INV-NUMBER)
                   " <span class='badge badge-"
                   FUNCTION LOWER-CASE(
                       FUNCTION TRIM(WS-EFFECTIVE-STATUS))
                   "'>"
                   FUNCTION TRIM(WS-EFFECTIVE-STATUS)
                   "</span></h2>"
           DISPLAY "    <div class='actions'>"
           DISPLAY "      <a class='btn-primary'"
           DISPLAY "         href='/cgi-bin/pdf-gen?number="
                   FUNCTION TRIM(INV-NUMBER) "'"
           DISPLAY "         target='_blank'>"
           DISPLAY "        [DOWNLOAD PDF]"
           DISPLAY "      </a>"
           PERFORM RENDER-STATUS-BUTTONS
           DISPLAY "      <button class='btn'"
           DISPLAY "              hx-get='/cgi-bin/invoice"
                   "?action=list'"
           DISPLAY "              hx-target='#content'"
           DISPLAY "              hx-swap='innerHTML'>"
           DISPLAY "        [BACK]"
           DISPLAY "      </button>"
           DISPLAY "    </div>"
           DISPLAY "  </header>"

           DISPLAY "  <dl class='kv'>"

           MOVE INV-CLIENT-NAME TO HTML-IN
           PERFORM HTML-ESCAPE
           DISPLAY "    <dt>Client</dt>"
           DISPLAY "    <dd>"
                   HTML-OUT(1:HTML-OUT-LEN) " ("
                   FUNCTION TRIM(INV-CLIENT-ID) ")</dd>"

           MOVE INV-DATE TO HTML-IN
           PERFORM FORMAT-DATE-FR
           DISPLAY "    <dt>Date</dt>"
           DISPLAY "    <dd>" WS-DATE-FR "</dd>"

           MOVE INV-DUE-DATE TO HTML-IN
           PERFORM FORMAT-DATE-FR
           DISPLAY "    <dt>Due</dt>"
           DISPLAY "    <dd>" WS-DATE-FR
           IF FUNCTION TRIM(WS-EFFECTIVE-STATUS) = "OVERDUE"
               PERFORM COMPUTE-DAYS-LATE
               DISPLAY "  &middot; <span class='warn'>"
                       FUNCTION TRIM(WS-DAYS-LATE)
                       " day(s) late</span>"
           END-IF
           DISPLAY "</dd>"

           IF FUNCTION TRIM(INV-STATUS) = "PAID"
               MOVE INV-PAID-DATE TO HTML-IN
               PERFORM FORMAT-DATE-FR
               DISPLAY "    <dt>Paid on</dt>"
               DISPLAY "    <dd>" WS-DATE-FR "</dd>"
           END-IF
           DISPLAY "  </dl>"

           DISPLAY "  <table>"
           DISPLAY "    <thead><tr>"
           DISPLAY "      <th>#</th>"
           DISPLAY "      <th>DESCRIPTION</th>"
           DISPLAY "      <th>QTY</th>"
           DISPLAY "      <th>RATE</th>"
           DISPLAY "      <th>TOTAL</th>"
           DISPLAY "    </tr></thead>"
           DISPLAY "    <tbody>"

           PERFORM VARYING WS-LINE-IDX FROM 1 BY 1
                   UNTIL WS-LINE-IDX > INV-LINE-COUNT
               DISPLAY "      <tr>"
               DISPLAY "        <td>" WS-LINE-IDX "</td>"

               MOVE INV-DESC(WS-LINE-IDX) TO HTML-IN
               PERFORM HTML-ESCAPE
               DISPLAY "        <td>"
                       HTML-OUT(1:HTML-OUT-LEN) "</td>"

               MOVE INV-QTY(WS-LINE-IDX) TO WS-DISP-QTY
               DISPLAY "        <td class='num'>"
                       FUNCTION TRIM(WS-DISP-QTY) "</td>"

               MOVE INV-UNIT-RATE(WS-LINE-IDX) TO WS-DISP-RATE
               DISPLAY "        <td class='num'>"
                       FUNCTION TRIM(WS-DISP-RATE) "</td>"

               MOVE INV-LINE-TOTAL(WS-LINE-IDX) TO WS-DISP-LINE
               DISPLAY "        <td class='num'>"
                       FUNCTION TRIM(WS-DISP-LINE) "</td>"
               DISPLAY "      </tr>"
           END-PERFORM

           DISPLAY "    </tbody>"
           DISPLAY "  </table>"

           PERFORM EMIT-TOTALS-PANEL

           DISPLAY "</section>"
           .

      *> Status-aware action buttons for the detail header.
      *> Stored status drives transitions; OVERDUE is display-only.
       RENDER-STATUS-BUTTONS.
           EVALUATE FUNCTION TRIM(INV-STATUS)
               WHEN "DRAFT"
                   PERFORM EMIT-MARK-SENT-BTN
                   PERFORM EMIT-MARK-PAID-BTN
               WHEN "SENT"
                   PERFORM EMIT-MARK-PAID-BTN
               WHEN "PAID"
                   PERFORM EMIT-REOPEN-BTN
               WHEN OTHER
                   CONTINUE
           END-EVALUATE
           .

       EMIT-MARK-SENT-BTN.
           DISPLAY "      <button class='btn'"
           DISPLAY "              hx-post='/cgi-bin/invoice"
                   "?action=mark-sent&number="
                   FUNCTION TRIM(INV-NUMBER) "'"
           DISPLAY "              hx-target='#content'"
           DISPLAY "              hx-swap='innerHTML'>"
           DISPLAY "        [MARK AS SENT]"
           DISPLAY "      </button>"
           .

       EMIT-MARK-PAID-BTN.
           DISPLAY "      <button class='btn btn-paid'"
           DISPLAY "              hx-post='/cgi-bin/invoice"
                   "?action=mark-paid&number="
                   FUNCTION TRIM(INV-NUMBER) "'"
           DISPLAY "              hx-target='#content'"
           DISPLAY "              hx-swap='innerHTML'>"
           DISPLAY "        [MARK AS PAID]"
           DISPLAY "      </button>"
           .

       EMIT-REOPEN-BTN.
           DISPLAY "      <button class='btn'"
           DISPLAY "              hx-post='/cgi-bin/invoice"
                   "?action=reopen&number="
                   FUNCTION TRIM(INV-NUMBER) "'"
           DISPLAY "              hx-target='#content'"
           DISPLAY "              hx-swap='innerHTML'"
           DISPLAY "              hx-confirm='Reopen "
                   FUNCTION TRIM(INV-NUMBER) "?'>"
           DISPLAY "        [REOPEN]"
           DISPLAY "      </button>"
           .

      *> Days late = today - due_date (positive integer).
       COMPUTE-DAYS-LATE.
           MOVE 0 TO WS-DAYS-LATE
           IF INV-DUE-DATE = SPACES
               EXIT PARAGRAPH
           END-IF

      *>   Pack INV-DUE-DATE "YYYY-MM-DD" into PIC 9(8) "YYYYMMDD".
           STRING INV-DUE-DATE(1:4) DELIMITED BY SIZE
                  INV-DUE-DATE(6:2) DELIMITED BY SIZE
                  INV-DUE-DATE(9:2) DELIMITED BY SIZE
               INTO WS-A-DATE

           STRING WS-TODAY-FMT(1:4) DELIMITED BY SIZE
                  WS-TODAY-FMT(6:2) DELIMITED BY SIZE
                  WS-TODAY-FMT(9:2) DELIMITED BY SIZE
               INTO WS-B-DATE

           COMPUTE WS-A-INT = FUNCTION INTEGER-OF-DATE(WS-A-DATE)
           COMPUTE WS-B-INT = FUNCTION INTEGER-OF-DATE(WS-B-DATE)
           COMPUTE WS-DAYS-INT = WS-B-INT - WS-A-INT
           IF WS-DAYS-INT > 0
               MOVE WS-DAYS-INT TO WS-DAYS-LATE
           END-IF
           .

       RENDER-CREATE-SUMMARY.
           DISPLAY "<section class='panel'>"
           DISPLAY "  <header class='panel-head'>"
           DISPLAY "    <h2>INVOICE CREATED &mdash; "
                   FUNCTION TRIM(INV-NUMBER) "</h2>"
           DISPLAY "    <div class='actions'>"
           DISPLAY "      <a class='btn-primary'"
           DISPLAY "         href='/cgi-bin/pdf-gen?number="
                   FUNCTION TRIM(INV-NUMBER) "'"
           DISPLAY "         target='_blank'>"
           DISPLAY "        [DOWNLOAD PDF]"
           DISPLAY "      </a>"
           DISPLAY "      <button class='btn'"
           DISPLAY "              hx-get='/cgi-bin/invoice"
                   "?action=list'"
           DISPLAY "              hx-target='#content'"
           DISPLAY "              hx-swap='innerHTML'>"
           DISPLAY "        [BACK TO LIST]"
           DISPLAY "      </button>"
           DISPLAY "    </div>"
           DISPLAY "  </header>"
           PERFORM EMIT-TOTALS-PANEL
           DISPLAY "</section>"
           .

       EMIT-TOTALS-PANEL.
           MOVE INV-AMOUNT-HT     TO WS-DISP-HT
           MOVE INV-AMOUNT-TVA    TO WS-DISP-TVA
           MOVE INV-AMOUNT-TTC    TO WS-DISP-TTC
           MOVE INV-URSSAF-AMOUNT TO WS-DISP-URSSAF
           MOVE INV-NET-REVENUE   TO WS-DISP-NET

           DISPLAY "  <table class='totals'>"
           DISPLAY "    <tr><th>Total H.T.</th>"
                   "<td class='num'>"
                   FUNCTION TRIM(WS-DISP-HT) " EUR</td></tr>"
           DISPLAY "    <tr><th>TVA</th>"
                   "<td class='num'>"
                   FUNCTION TRIM(WS-DISP-TVA) " EUR</td></tr>"
           DISPLAY "    <tr class='ttc'><th>Total T.T.C.</th>"
                   "<td class='num'>"
                   FUNCTION TRIM(WS-DISP-TTC) " EUR</td></tr>"
           DISPLAY "    <tr><th>URSSAF (22%)</th>"
                   "<td class='num'>"
                   FUNCTION TRIM(WS-DISP-URSSAF) " EUR</td></tr>"
           DISPLAY "    <tr><th>Net revenue</th>"
                   "<td class='num'>"
                   FUNCTION TRIM(WS-DISP-NET) " EUR</td></tr>"
           DISPLAY "  </table>"
           .

      *> Helpers.
       LOOKUP-CLIENT-NAME.
           MOVE SPACES TO INV-CLIENT-NAME
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
                   MOVE CLI-NAME TO INV-CLIENT-NAME
           END-READ
           CLOSE CLIENT-FILE
           .

       OPEN-INVOICE-FILE-IO.
           OPEN I-O INVOICE-FILE
           IF WS-INV-STATUS = "35"
               OPEN OUTPUT INVOICE-FILE
               CLOSE INVOICE-FILE
               OPEN I-O INVOICE-FILE
           END-IF
           .

      *> Auto-number: scan invoices.dat, find max NNNN for current
      *> year, return YYYY-(NNNN+1) in WS-LOOKUP-NUMBER.
       ASSIGN-NEXT-NUMBER.
           MOVE FUNCTION CURRENT-DATE(1:4) TO WS-YEAR
           MOVE 0 TO WS-NEXT-SEQ

           OPEN INPUT INVOICE-FILE
           IF WS-INV-STATUS NOT = "00"
      *>       File doesn't exist (or unreadable) — start at 1.
               MOVE 1 TO WS-NEXT-SEQ
               PERFORM FORMAT-NEXT-NUMBER
               EXIT PARAGRAPH
           END-IF

           MOVE "N" TO WS-EOF
           PERFORM UNTIL WS-EOF = "Y"
               READ INVOICE-FILE NEXT RECORD
                   AT END
                       MOVE "Y" TO WS-EOF
                   NOT AT END
                       IF INV-NUMBER(1:4) = WS-YEAR
                           MOVE 0 TO WS-CUR-SEQ
                           COMPUTE WS-CUR-SEQ =
                               FUNCTION NUMVAL(INV-NUMBER(6:4))
                           IF WS-CUR-SEQ > WS-NEXT-SEQ
                               MOVE WS-CUR-SEQ TO WS-NEXT-SEQ
                           END-IF
                       END-IF
               END-READ
           END-PERFORM

           CLOSE INVOICE-FILE
           ADD 1 TO WS-NEXT-SEQ
           PERFORM FORMAT-NEXT-NUMBER
           .

       FORMAT-NEXT-NUMBER.
           MOVE SPACES TO WS-LOOKUP-NUMBER
           STRING WS-YEAR     DELIMITED BY SIZE
                  "-"         DELIMITED BY SIZE
                  WS-NEXT-SEQ DELIMITED BY SIZE
               INTO WS-LOOKUP-NUMBER
           .

      *> Date helpers — today and today+30 in YYYY-MM-DD.
       COMPUTE-DEFAULT-DATES.
           MOVE FUNCTION CURRENT-DATE(1:8) TO WS-DATE-RAW
           PERFORM FORMAT-DATE-RAW
           .

       ADVANCE-DATE-30.
           COMPUTE WS-DATE-INT = FUNCTION INTEGER-OF-DATE(
               WS-DATE-RAW)
           ADD 30 TO WS-DATE-INT
           COMPUTE WS-DATE-RAW = FUNCTION DATE-OF-INTEGER(
               WS-DATE-INT)
           PERFORM FORMAT-DATE-RAW
           .

       FORMAT-DATE-RAW.
           MOVE SPACES TO WS-DATE-FMT
           STRING WS-DATE-RAW(1:4) DELIMITED BY SIZE
                  "-"              DELIMITED BY SIZE
                  WS-DATE-RAW(5:2) DELIMITED BY SIZE
                  "-"              DELIMITED BY SIZE
                  WS-DATE-RAW(7:2) DELIMITED BY SIZE
               INTO WS-DATE-FMT
           .

      *> Numeric parsing — robust against empty / whitespace input.
       PARSE-NUMERIC-QTY.
           IF FUNCTION TRIM(WS-NUM-RAW) = SPACES
               MOVE 0 TO WS-QTY
           ELSE
               COMPUTE WS-QTY = FUNCTION NUMVAL(WS-NUM-RAW)
           END-IF
           .

       PARSE-NUMERIC-RATE-AMOUNT.
           IF FUNCTION TRIM(WS-NUM-RAW) = SPACES
               MOVE 0 TO WS-RATE
           ELSE
               COMPUTE WS-RATE = FUNCTION NUMVAL(WS-NUM-RAW)
           END-IF
           .

       PARSE-NUMERIC-RATE.
           IF FUNCTION TRIM(WS-NUM-RAW) = SPACES
               MOVE 0 TO WS-TVA-RATE
           ELSE
               COMPUTE WS-TVA-RATE = FUNCTION NUMVAL(WS-NUM-RAW)
           END-IF
           .

      *> Error renderers.
       RENDER-NOT-FOUND.
           DISPLAY "<div class='echo'>"
           DISPLAY "  <h2>INVOICE NOT FOUND</h2>"
           DISPLAY "  <p>number="
                   FUNCTION TRIM(WS-LOOKUP-NUMBER) "</p>"
           DISPLAY "</div>"
           .

       RENDER-WRITE-ERROR.
           DISPLAY "<div class='echo'>"
           DISPLAY "  <h2>WRITE FAILED</h2>"
           DISPLAY "  <p>FILE STATUS = " WS-INV-STATUS "</p>"
           DISPLAY "</div>"
           .

       RENDER-UNKNOWN-ACTION.
           DISPLAY "<div class='echo'>"
           DISPLAY "  <h2>UNKNOWN ACTION</h2>"
           DISPLAY "  <p>action="
                   FUNCTION TRIM(WS-ACTION) "</p>"
           DISPLAY "</div>"
           .

       COPY "auth-check-procs.cpy".
       COPY "cgi-utils-procs.cpy".

       END PROGRAM INVOICE.
