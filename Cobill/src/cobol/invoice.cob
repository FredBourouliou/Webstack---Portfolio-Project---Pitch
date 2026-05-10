      *> invoice.cob
      *>
      *> Heart of the application. Invoice CRUD plus the financial
      *> arithmetic: HT total, TVA, TTC, URSSAF contribution, net
      *> revenue. Every monetary computation runs in COBOL native
      *> fixed-point decimal (PIC 9(N)V99) so the values printed
      *> on the PDF match what the user typed, to the cent.
      *>
      *> Endpoint:   /cgi-bin/invoice
      *> Auth gate:  yes
      *> Methods:    GET (list / new / get) and POST (create /
      *>             mark-sent / mark-paid / reopen).
      *>
      *> Recognized actions:
      *>   list         filterable, reverse-chronological table
      *>   new          empty creation form (10 line-item rows)
      *>   create       persist a new invoice (auto-numbered)
      *>   get          load one invoice + render detail view
      *>   mark-sent    DRAFT -> SENT
      *>   mark-paid    SENT  -> PAID, records the paid date
      *>   reopen       PAID  -> SENT (cancel a wrong "mark paid")
      *>
      *> The OVERDUE status is computed on the fly when SENT and
      *> due-date < today, never stored. See COMPUTE-EFFECTIVE-
      *> STATUS.
       IDENTIFICATION DIVISION.
       PROGRAM-ID. INVOICE.

       ENVIRONMENT DIVISION.
       CONFIGURATION SECTION.
       COPY "special-names.cpy".

       INPUT-OUTPUT SECTION.
       FILE-CONTROL.
      *>     Invoice store, primary key INV-NUMBER (YYYY-NNNN),
      *>     alternate key INV-CLIENT-ID for client-scoped lookups.
           SELECT INVOICE-FILE
               ASSIGN TO "data/invoices.dat"
               ORGANIZATION IS INDEXED
               ACCESS MODE IS DYNAMIC
               RECORD KEY IS INV-NUMBER
               ALTERNATE RECORD KEY IS INV-CLIENT-ID
                   WITH DUPLICATES
               FILE STATUS IS WS-INV-STATUS.

      *>     Client file, used to resolve client names in the
      *>     list view and to populate the <select> in the form.
           SELECT CLIENT-FILE
               ASSIGN TO "data/clients.dat"
               ORGANIZATION IS INDEXED
               ACCESS MODE IS DYNAMIC
               RECORD KEY IS CLI-ID
               ALTERNATE RECORD KEY IS CLI-NAME
                   WITH DUPLICATES
               FILE STATUS IS WS-CLI-STATUS.

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
       FD SESSION-FILE.
       COPY "session-record.cpy".

       WORKING-STORAGE SECTION.
       COPY "cgi-utils-ws.cpy".
       COPY "auth-check-ws.cpy".

      *> ISAM file statuses + dispatch state.
       01  WS-INV-STATUS           PIC XX.
       01  WS-CLI-STATUS           PIC XX.
       01  WS-ACTION               PIC X(10) VALUE "list".
       01  WS-EOF                  PIC X     VALUE "N".
       01  WS-ROW-COUNT            PIC 9(4)  VALUE 0.

      *> ----- List view: filters + in-memory buffer -----
      *> List is rendered reverse-chronologically. ISAM scans the
      *> primary key in ascending order, so the program reads
      *> everything into a buffer first, then emits the buffer
      *> backwards. q = free-text client filter, status = SENT |
      *> PAID | OVERDUE | DRAFT.
       01  WS-FILTER-Q             PIC X(50).
       01  WS-FILTER-Q-LOWER       PIC X(50).
       01  WS-FILTER-Q-LEN         PIC 9(3) VALUE 0.
       01  WS-FILTER-STATUS        PIC X(8).
       01  WS-LOWER-NAME           PIC X(50).
       01  WS-SCAN-IDX             PIC 9(3).
       01  WS-MATCHED              PIC X.
       01  WS-STATUS-LBL           PIC X(8).
      *> Total amount of all SENT / OVERDUE rows (the receivables
      *> footer at the bottom of the list).
       01  WS-OUTSTANDING          PIC 9(9)V99 VALUE 0.
       01  WS-DISP-OUTSTANDING     PIC ZZZ,ZZZ,ZZ9.99.

      *> In-memory buffer used by the list view. Capped at 200
      *> rows, which is one year of fairly heavy solo activity.
       01  WS-INV-COUNT            PIC 9(4) VALUE 0.
       01  WS-INV-IDX              PIC 9(4) VALUE 0.
       01  WS-INV-BUF.
           05  WS-BUF OCCURS 200 TIMES.
               10  BUF-NUMBER      PIC X(9).
               10  BUF-CLIENT      PIC X(50).
               10  BUF-DATE        PIC X(10).
               10  BUF-DUE-DATE    PIC X(10).
               10  BUF-TTC         PIC 9(7)V99.
      *>             Stored status from disk.
               10  BUF-STATUS      PIC X(8).
      *>             Effective status after the OVERDUE check.
               10  BUF-EFFECTIVE   PIC X(8).

      *> Output buffer for FORMAT-DATE-FR.
       01  WS-DATE-FR              PIC X(10).

      *> Form parameters and runtime fields.
       01  WS-LOOKUP-NUMBER        PIC X(9).
       01  WS-LOOKUP-ID            PIC X(10).
       01  WS-NEW-STATUS           PIC X(8).
       01  WS-TODAY-FMT            PIC X(10).
       01  WS-EFFECTIVE-STATUS     PIC X(8).

      *> Day-count helpers used by COMPUTE-DAYS-LATE. PIC S9(8)
      *> is the INTEGER-OF-DATE return type (days since 1601).
       01  WS-DAYS-INT             PIC S9(8).
       01  WS-A-DATE               PIC 9(8).
       01  WS-B-DATE               PIC 9(8).
       01  WS-A-INT                PIC S9(8).
       01  WS-B-INT                PIC S9(8).
       01  WS-DAYS-LATE            PIC ZZZ9.

      *> Auto-numbering state. The next invoice number is
      *> YYYY-NNNN where YYYY is the current year and NNNN is
      *> the largest existing sequence + 1. Sequence resets at
      *> year change (so 2026-9999 -> 2027-0001).
       01  WS-YEAR                 PIC 9(4).
       01  WS-NEXT-SEQ             PIC 9(4)  VALUE 0.
       01  WS-CUR-SEQ              PIC 9(4)  VALUE 0.

      *> Numeric parsing helpers. PARSE-NUMERIC-QTY /
      *> PARSE-NUMERIC-RATE-AMOUNT take the raw "1234,56" form
      *> field and store it as a fixed-point number.
       01  WS-NUM-RAW              PIC X(20).
       01  WS-QTY                  PIC 9(4)V99.
       01  WS-RATE                 PIC 9(5)V99.
       01  WS-LINE-TOTAL           PIC 9(7)V99.
       01  WS-TVA-RATE             PIC V9999.
      *> URSSAF rate (22 % for BNC services). Hard-coded; v1.2
      *> reads it from data/config.dat.
       01  WS-URSSAF-RATE          PIC V9999  VALUE 0.2200.

      *> Loop indices for the 10-row line-items table.
       01  WS-LINE-IDX             PIC 99.
       01  WS-LINE-KEY             PIC X(8).

      *> Date helpers used for default issue + due dates.
       01  WS-DATE-RAW             PIC 9(8).
       01  WS-DATE-INT             PIC 9(8).
       01  WS-DATE-FMT             PIC X(10).

      *> Edited (display-formatted) fixed-point amounts. PIC
      *> ZZZZ,ZZ9.99 trims leading zeroes and inserts a comma
      *> thousands separator. The output is later swapped to
      *> French locale (space thousands, comma decimal) in
      *> the renderers.
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
      *>   CGI + auth boilerplate.
           PERFORM READ-CGI-INPUT
           PERFORM PARSE-CGI-INPUT
           COPY "auth-check.cpy".
           PERFORM EMIT-HTML-HEADERS

      *>   Action dispatch. Default action = "list".
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
      *>           DRAFT -> SENT
                   MOVE "SENT"  TO WS-NEW-STATUS
                   PERFORM ACTION-CHANGE-STATUS
               WHEN "mark-paid"
      *>           SENT -> PAID, records the paid date.
                   MOVE "PAID"  TO WS-NEW-STATUS
                   PERFORM ACTION-CHANGE-STATUS
               WHEN "reopen"
      *>           PAID -> SENT, clears the paid date.
                   MOVE "SENT"  TO WS-NEW-STATUS
                   PERFORM ACTION-CHANGE-STATUS
               WHEN OTHER
                   PERFORM RENDER-UNKNOWN-ACTION
           END-EVALUATE

           STOP RUN.

      *> ACTION-LIST
      *>
      *> Filterable, reverse-chronological invoice list. The
      *> filter inputs (search box + status dropdown) use HTMX
      *> with hx-select='#invoices-results' so only the result
      *> region of the response is swapped in, keeping focus on
      *> the input across keystrokes.
      *>
      *> Implementation: LOAD-INVOICES-INTO-BUFFER reads all
      *> matching rows into WS-INV-BUF (capped at 200), then
      *> RENDER-RESULTS-TABLE walks the buffer backwards to emit
      *> the most recent invoices first.
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

      *> LOAD-LIST-FILTERS
      *>
      *> Pull the two filter inputs (q + status) from the form,
      *> lowercase q for case-insensitive substring matching,
      *> and remember its effective length.
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

      *> LOAD-INVOICES-INTO-BUFFER
      *>
      *> Walk the invoice file front-to-back, run each row
      *> through EVAL-AND-BUFFER (filter + add to buffer). The
      *> renderer walks the buffer in reverse so the most recent
      *> invoices appear at the top of the list. Cap at 200 rows
      *> so the buffer never blows up; older invoices simply do
      *> not appear in v1.
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

      *> EVAL-AND-BUFFER
      *>
      *> Decide whether the current INVOICE-RECORD passes the
      *> active filters; if yes, copy the relevant fields into
      *> the buffer and update the outstanding total. The
      *> effective status is also computed here so the list view
      *> does not have to recompute it for every row.
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

      *> COMPUTE-TODAY
      *>
      *> Build today's date as a 10-character "YYYY-MM-DD" string,
      *> stored in WS-TODAY-FMT. ISO format means we can compare
      *> two dates lexicographically (string compare) and get the
      *> same answer as a chronological compare.
       COMPUTE-TODAY.
           MOVE SPACES TO WS-TODAY-FMT
           STRING FUNCTION CURRENT-DATE(1:4) DELIMITED BY SIZE
                  "-"                        DELIMITED BY SIZE
                  FUNCTION CURRENT-DATE(5:2) DELIMITED BY SIZE
                  "-"                        DELIMITED BY SIZE
                  FUNCTION CURRENT-DATE(7:2) DELIMITED BY SIZE
               INTO WS-TODAY-FMT
           .

      *> COMPUTE-EFFECTIVE-STATUS
      *>
      *> The "OVERDUE" status is never written to disk. Instead,
      *> it is derived at render time when:
      *>   - the stored status is not PAID, AND
      *>   - the due date is set, AND
      *>   - the due date is before today.
      *>
      *> This rules out the entire class of bugs that comes from
      *> a stale cached status (no cron, no daily job to keep in
      *> sync). The disk row keeps the true workflow state
      *> (DRAFT / SENT / PAID), and OVERDUE is just a view.
       COMPUTE-EFFECTIVE-STATUS.
           MOVE INV-STATUS TO WS-EFFECTIVE-STATUS
           IF FUNCTION TRIM(INV-STATUS) NOT = "PAID"
                   AND INV-DUE-DATE NOT = SPACES
                   AND INV-DUE-DATE < WS-TODAY-FMT
               MOVE "OVERDUE" TO WS-EFFECTIVE-STATUS
           END-IF
           .

      *> ACTION-CHANGE-STATUS
      *>
      *> Update the stored INV-STATUS to WS-NEW-STATUS (set by
      *> MAIN-LOGIC before this paragraph is invoked). When the
      *> target is "PAID", record today's date in INV-PAID-DATE;
      *> when reopening, clear INV-PAID-DATE so the row reverts
      *> cleanly. Always returns the refreshed list as the
      *> response.
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

      *> SCAN-CLIENT-MATCH
      *>
      *> Substring search: does WS-LOWER-NAME contain
      *> WS-FILTER-Q-LOWER(1:WS-FILTER-Q-LEN) anywhere? Returns
      *> "Y" or "N" in WS-MATCHED. Plain O(n*m) scan; n is at
      *> most 50 (client name length), m is at most 50 (query
      *> length), so the cost is negligible.
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

      *> ACTION-NEW
      *>
      *> Render an empty invoice creation form: client dropdown
      *> populated from data/clients.dat, a date + due-date row
      *> (defaulting to today / today+30), a VAT rate dropdown,
      *> and a 5-row table of line items.
      *>
      *> Sending up to 10 line items is supported by the schema
      *> (see invoice-record.cpy), but the form only renders 5
      *> rows at a time to keep the layout readable. v1.1 can
      *> add an "add row" button if needed.
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

      *> ACTION-CREATE
      *>
      *> Persist a new invoice:
      *>   1. Allocate the next YYYY-NNNN number.
      *>   2. Copy form fields (client, dates, TVA rate) into
      *>      the record.
      *>   3. Read each line item, accumulate HT.
      *>   4. Run the cascading financial calculations
      *>      (TVA, TTC, URSSAF, net revenue).
      *>   5. Set status = DRAFT, write the record.
      *>   6. Render a summary panel.
      *>
      *> All arithmetic is fixed-point decimal with the ROUNDED
      *> phrase, so values match the printed PDF to the cent.
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

      *> READ-LINE-ITEM
      *>
      *> Pull one line item (desc<N>, qty<N>, rate<N>) from the
      *> form, convert qty and rate to fixed-point numbers, store
      *> them in the OCCURS slot at index WS-LINE-IDX, and add
      *> the line total to the running HT.
      *>
      *> An empty description is treated as "row not used" and
      *> the paragraph exits without writing anything; that keeps
      *> the LINE-COUNT honest when the user only fills the first
      *> few rows.
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

      *> ACTION-GET
      *>
      *> Load one invoice by primary key and render its detail
      *> view (header, full line items table, totals, status
      *> badge, action buttons). Missing or unknown number drops
      *> into RENDER-NOT-FOUND.
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

      *> COMPUTE-DAYS-LATE
      *>
      *> Days late = today - due date, clamped to >= 0. Converts
      *> both ISO dates into day-count integers via
      *> INTEGER-OF-DATE so the difference works cleanly across
      *> month and year boundaries.
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

      *> ----- Helpers -----

      *> LOOKUP-CLIENT-NAME
      *>
      *> Look up the client by INV-CLIENT-ID and copy CLI-NAME
      *> into INV-CLIENT-NAME, snapshotting the trade name so
      *> the invoice keeps showing it even if the client renames
      *> itself later. Silent on missing client (the FK column
      *> stays empty).
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

      *> OPEN-INVOICE-FILE-IO
      *>
      *> Same idempotent bootstrap pattern used by client.cob and
      *> auth.cob: open I-O, and if the file does not exist yet
      *> (status "35"), create it with OPEN OUTPUT then reopen
      *> I-O.
       OPEN-INVOICE-FILE-IO.
           OPEN I-O INVOICE-FILE
           IF WS-INV-STATUS = "35"
               OPEN OUTPUT INVOICE-FILE
               CLOSE INVOICE-FILE
               OPEN I-O INVOICE-FILE
           END-IF
           .

      *> ASSIGN-NEXT-NUMBER
      *>
      *> Allocate the next free YYYY-NNNN. Scan the invoice file
      *> end-to-end, find the largest NNNN that already starts
      *> with the current year, then add 1. NNNN resets to 0001
      *> at the year change (so 2026-9999 -> 2027-0001).
      *>
      *> Returns the formatted number in WS-LOOKUP-NUMBER. Cost
      *> is O(n) but n is bounded by the year's invoice count
      *> (<= 1000 in practice for solo activity).
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

      *> ----- Date helpers -----
      *> COMPUTE-DEFAULT-DATES sets WS-DATE-FMT to today's
      *> ISO date. A subsequent call to ADVANCE-DATE-30 shifts
      *> WS-DATE-FMT to today + 30 days using INTEGER-OF-DATE /
      *> DATE-OF-INTEGER for clean month-end handling.

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

      *> ----- Numeric parsing -----
      *>
      *> FUNCTION NUMVAL converts a string like "12.34" into a
      *> numeric COBOL value. We always check for empty / blank
      *> input first; passing an all-space string to NUMVAL would
      *> raise a runtime size error.
      *>
      *> Three wrappers because the destination has a different
      *> PIC: qty (PIC 9(4)V99), unit rate / line amount
      *> (PIC 9(5)V99), and VAT rate (PIC V9999, decimal only).

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

      *> ----- Error renderers -----
      *> Each emits an HTML fragment that HTMX swaps into
      *> #content. Status code stays 200 so the swap fires; the
      *> message in the body conveys what went wrong.

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

      *> Auth gate paragraphs and shared CGI helpers.
       COPY "auth-check-procs.cpy".
       COPY "cgi-utils-procs.cpy".

       END PROGRAM INVOICE.
