       IDENTIFICATION DIVISION.
       PROGRAM-ID. DASHBOARD.

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
       FD SESSION-FILE.
       COPY "session-record.cpy".

       WORKING-STORAGE SECTION.
       COPY "cgi-utils-ws.cpy".
       COPY "auth-check-ws.cpy".

       01 WS-INV-STATUS    PIC XX.
       01 WS-EOF           PIC X     VALUE "N".
       01 WS-ACTION        PIC X(10) VALUE "urssaf".

      *> URSSAF / activity config (TODO: load from config.dat).
       01 WS-URSSAF-RATE   PIC V9999  VALUE 0.2200.
       01 WS-ACTIVITY      PIC X(20)  VALUE "BNC (Services)".
       01 WS-VAT-THRESH    PIC 9(7)V99 VALUE 36800.00.
       01 WS-VAT-MAJORE    PIC 9(7)V99 VALUE 39100.00.

      *> ---- Date helpers ---------------------------------------------
       01 WS-CUR-YEAR-NUM  PIC 9(4).
       01 WS-CUR-YEAR      PIC X(4).
       01 WS-FILTER-YEAR   PIC X(4).
       01 WS-INV-MONTH     PIC 99.
       01 WS-INV-Q         PIC 9.

      *> ---- Aggregates ----------------------------------------------
       01 WS-COUNT-TOTAL   PIC 9(4)   VALUE 0.

       01 WS-MONTH-AGGS.
           05 WS-MONTH OCCURS 12 TIMES.
               10 M-COUNT  PIC 9(4)    VALUE 0.
               10 M-HT     PIC 9(9)V99 VALUE 0.

       01 WS-Q-AGGS.
           05 WS-Q OCCURS 4 TIMES.
               10 Q-COUNT  PIC 9(4)    VALUE 0.
               10 Q-HT     PIC 9(9)V99 VALUE 0.
               10 Q-TVA    PIC 9(9)V99 VALUE 0.
               10 Q-URSSAF PIC 9(9)V99 VALUE 0.

       01 WS-YTD-HT        PIC 9(9)V99 VALUE 0.
       01 WS-YTD-TVA       PIC 9(9)V99 VALUE 0.
       01 WS-YTD-TTC       PIC 9(9)V99 VALUE 0.
       01 WS-YTD-URSSAF    PIC 9(9)V99 VALUE 0.
       01 WS-YTD-NET       PIC 9(9)V99 VALUE 0.

      *> Max month HT — drives the bar-chart scale.
       01 WS-MAX-HT        PIC 9(9)V99 VALUE 0.
       01 WS-BAR-PCT       PIC 9(3)   VALUE 0.

      *> Aging buckets for non-PAID invoices.
      *> idx 1=not yet due, 2=1-30, 3=31-60, 4=61-90, 5=90+ days late.
       01 WS-AGE-LABELS.
           05 FILLER PIC X(16) VALUE "Not yet due     ".
           05 FILLER PIC X(16) VALUE "1-30 days late  ".
           05 FILLER PIC X(16) VALUE "31-60 days late ".
           05 FILLER PIC X(16) VALUE "61-90 days late ".
           05 FILLER PIC X(16) VALUE "Over 90 days    ".
       01 WS-AGE-LABEL-TBL REDEFINES WS-AGE-LABELS.
           05 WS-AGE-LABEL OCCURS 5 TIMES PIC X(16).

       01 WS-AGING.
           05 WS-AGE-COUNT  OCCURS 5 TIMES PIC 9(4) VALUE 0.
           05 WS-AGE-TOTAL  OCCURS 5 TIMES PIC 9(9)V99 VALUE 0.

       01 WS-AGE-IDX        PIC 9   VALUE 0.
       01 WS-DAYS-DIFF      PIC S9(4).
       01 WS-DUE-DATE-RAW   PIC 9(8).
       01 WS-DUE-INT        PIC S9(8).
       01 WS-DAYS-DIFF-DISP PIC ZZZ9.

      *> Overdue list (capped at 50; rendered in ISAM-read order
      *> which is roughly chronological).
       01 WS-OD-MAX         PIC 9(3) VALUE 50.
       01 WS-OD-COUNT       PIC 9(3) VALUE 0.
       01 WS-OD OCCURS 50 TIMES.
           05 OD-NUMBER     PIC X(9).
           05 OD-CLIENT     PIC X(50).
           05 OD-DUE        PIC X(10).
           05 OD-DAYS       PIC 9(4).
           05 OD-TTC        PIC 9(9)V99.

      *> VAT threshold tracking.
       01 WS-VAT-PCT       PIC 9(3)   VALUE 0.
       01 WS-VAT-PCT-DISP  PIC ZZ9.
       01 WS-VAT-BAR-PCT   PIC 9(3)   VALUE 0.
       01 WS-VAT-LEVEL     PIC X(8)   VALUE "safe".
       01 WS-DAYS-IN       PIC 9(3)   VALUE 0.
       01 WS-DAILY-RATE    PIC 9(7)V99 VALUE 0.
       01 WS-DAYS-TO-CROSS PIC 9(4)   VALUE 0.
       01 WS-JAN1-DATE     PIC 9(8).
       01 WS-JAN1-INT      PIC S9(8).
       01 WS-TODAY-DATE    PIC 9(8).
       01 WS-TODAY-INT     PIC S9(8).
       01 WS-CROSS-INT     PIC S9(8).
       01 WS-CROSS-DATE    PIC 9(8).
       01 WS-CROSS-FR      PIC X(10).
       01 WS-PROJ-EOY      PIC 9(9)V99.

      *> Display formatters (FR locale: space + comma).
       01 WS-NUM-IN        PIC 9(9)V99.
       01 WS-NUM-EDITED    PIC ZZZ,ZZZ,ZZ9.99.
       01 WS-NUM-FR        PIC X(15).

       01 WS-IDX           PIC 99.
       01 WS-MONTH-LBL     PIC X(3).

       PROCEDURE DIVISION.
       MAIN-LOGIC.
           PERFORM READ-CGI-INPUT
           PERFORM PARSE-CGI-INPUT
           COPY "auth-check.cpy".
           PERFORM EMIT-HTML-HEADERS

           PERFORM RESOLVE-YEAR
           PERFORM AGGREGATE-INVOICES
           PERFORM RENDER-DASHBOARD
           STOP RUN.

      *> Year filter: ?year=YYYY ; default = current year.
       RESOLVE-YEAR.
           MOVE FUNCTION CURRENT-DATE(1:4) TO WS-CUR-YEAR
           MOVE WS-CUR-YEAR TO WS-FILTER-YEAR

           MOVE "year" TO CGI-L-KEY
           PERFORM FIND-FIELD
           IF CGI-L-FOUND = "Y"
                   AND FUNCTION TRIM(CGI-L-VALUE) NOT = SPACES
               MOVE CGI-L-VALUE(1:4) TO WS-FILTER-YEAR
           END-IF
           .

      *> Walk the invoice file, accumulate per-month + per-quarter,
      *> for the selected year only.
       AGGREGATE-INVOICES.
           PERFORM COMPUTE-TODAY-INT

           OPEN INPUT INVOICE-FILE
           IF WS-INV-STATUS NOT = "00"
               EXIT PARAGRAPH
           END-IF

           MOVE "N" TO WS-EOF
           PERFORM UNTIL WS-EOF = "Y"
               READ INVOICE-FILE NEXT RECORD
                   AT END
                       MOVE "Y" TO WS-EOF
                   NOT AT END
                       PERFORM ACCUMULATE-ONE
               END-READ
           END-PERFORM

           CLOSE INVOICE-FILE
           PERFORM COMPUTE-MAX-MONTH
           .

       ACCUMULATE-ONE.
      *>   Skip if year doesn't match.
           IF INV-DATE(1:4) NOT = WS-FILTER-YEAR
               EXIT PARAGRAPH
           END-IF

           ADD 1 TO WS-COUNT-TOTAL

           MOVE INV-DATE(6:2) TO WS-INV-MONTH
           IF WS-INV-MONTH < 1 OR WS-INV-MONTH > 12
               EXIT PARAGRAPH
           END-IF

           ADD 1                TO M-COUNT(WS-INV-MONTH)
           ADD INV-AMOUNT-HT    TO M-HT(WS-INV-MONTH)

      *>   Quarter = (month-1) / 3 + 1.
           COMPUTE WS-INV-Q = (WS-INV-MONTH - 1) / 3 + 1

           ADD 1                  TO Q-COUNT(WS-INV-Q)
           ADD INV-AMOUNT-HT      TO Q-HT(WS-INV-Q)
           ADD INV-AMOUNT-TVA     TO Q-TVA(WS-INV-Q)
           COMPUTE Q-URSSAF(WS-INV-Q) ROUNDED =
               Q-HT(WS-INV-Q) * WS-URSSAF-RATE

           ADD INV-AMOUNT-HT      TO WS-YTD-HT
           ADD INV-AMOUNT-TVA     TO WS-YTD-TVA
           ADD INV-AMOUNT-TTC     TO WS-YTD-TTC

      *>   Aging only matters for non-PAID invoices.
           IF FUNCTION TRIM(INV-STATUS) NOT = "PAID"
                   AND INV-DUE-DATE NOT = SPACES
               PERFORM CLASSIFY-AGE
           END-IF
           .

      *> Compute days_diff = today - due_date, drop in a bucket,
      *> append to overdue list when late.
       CLASSIFY-AGE.
           STRING INV-DUE-DATE(1:4) DELIMITED BY SIZE
                  INV-DUE-DATE(6:2) DELIMITED BY SIZE
                  INV-DUE-DATE(9:2) DELIMITED BY SIZE
               INTO WS-DUE-DATE-RAW
           COMPUTE WS-DUE-INT = FUNCTION INTEGER-OF-DATE(
                                    WS-DUE-DATE-RAW)
           COMPUTE WS-DAYS-DIFF = WS-TODAY-INT - WS-DUE-INT

           EVALUATE TRUE
               WHEN WS-DAYS-DIFF <= 0
                   MOVE 1 TO WS-AGE-IDX
               WHEN WS-DAYS-DIFF <= 30
                   MOVE 2 TO WS-AGE-IDX
               WHEN WS-DAYS-DIFF <= 60
                   MOVE 3 TO WS-AGE-IDX
               WHEN WS-DAYS-DIFF <= 90
                   MOVE 4 TO WS-AGE-IDX
               WHEN OTHER
                   MOVE 5 TO WS-AGE-IDX
           END-EVALUATE

           ADD 1 TO WS-AGE-COUNT(WS-AGE-IDX)
           ADD INV-AMOUNT-TTC TO WS-AGE-TOTAL(WS-AGE-IDX)

           IF WS-DAYS-DIFF > 0
                   AND WS-OD-COUNT < WS-OD-MAX
               ADD 1 TO WS-OD-COUNT
               MOVE INV-NUMBER       TO OD-NUMBER(WS-OD-COUNT)
               MOVE INV-CLIENT-NAME  TO OD-CLIENT(WS-OD-COUNT)
               MOVE INV-DUE-DATE     TO OD-DUE(WS-OD-COUNT)
               MOVE WS-DAYS-DIFF     TO OD-DAYS(WS-OD-COUNT)
               MOVE INV-AMOUNT-TTC   TO OD-TTC(WS-OD-COUNT)
           END-IF
           .

       COMPUTE-MAX-MONTH.
           MOVE 0 TO WS-MAX-HT
           PERFORM VARYING WS-IDX FROM 1 BY 1 UNTIL WS-IDX > 12
               IF M-HT(WS-IDX) > WS-MAX-HT
                   MOVE M-HT(WS-IDX) TO WS-MAX-HT
               END-IF
           END-PERFORM

      *>   YTD URSSAF and net derive from YTD HT.
           COMPUTE WS-YTD-URSSAF ROUNDED =
               WS-YTD-HT * WS-URSSAF-RATE
           SUBTRACT WS-YTD-URSSAF FROM WS-YTD-HT
               GIVING WS-YTD-NET
           .

      *> RENDER — section header, monthly chart, quarterly table,
      *> YTD totals.
       RENDER-DASHBOARD.
           DISPLAY "<section class='panel' id='dashboard-panel'>"
           DISPLAY "  <header class='panel-head'>"
           DISPLAY "    <h2>URSSAF DASHBOARD &mdash; YEAR "
                   FUNCTION TRIM(WS-FILTER-YEAR) "</h2>"
           DISPLAY "    <p class='muted'>Activity: "
                   FUNCTION TRIM(WS-ACTIVITY)
                   " &middot; rate "
                   "22%"
                   "</p>"
           DISPLAY "  </header>"

           IF WS-COUNT-TOTAL = 0
               DISPLAY "  <p><em>No invoices for "
                       FUNCTION TRIM(WS-FILTER-YEAR) ".</em></p>"
               DISPLAY "</section>"
               EXIT PARAGRAPH
           END-IF

           PERFORM RENDER-MONTHLY-CHART
           PERFORM RENDER-QUARTERLY-TABLE
           PERFORM RENDER-VAT-THRESHOLD
           PERFORM RENDER-OUTSTANDING
           PERFORM RENDER-YTD

           DISPLAY "</section>"
           .

      *> Monthly bar chart (pure CSS, no JS).
       RENDER-MONTHLY-CHART.
           DISPLAY "  <h3>Monthly revenue (HT)</h3>"
           DISPLAY "  <ul class='barchart'>"
           PERFORM VARYING WS-IDX FROM 1 BY 1 UNTIL WS-IDX > 12
               PERFORM RENDER-MONTH-BAR
           END-PERFORM
           DISPLAY "  </ul>"
           .

       RENDER-MONTH-BAR.
           PERFORM RESOLVE-MONTH-LABEL
           MOVE M-HT(WS-IDX) TO WS-NUM-IN
           PERFORM FORMAT-NUM-FR

           IF WS-MAX-HT = 0
               MOVE 0 TO WS-BAR-PCT
           ELSE
               COMPUTE WS-BAR-PCT =
                   M-HT(WS-IDX) * 100 / WS-MAX-HT
           END-IF

           DISPLAY "    <li>"
           DISPLAY "      <span class='bar-label'>"
                   WS-MONTH-LBL "</span>"
           DISPLAY "      <span class='bar-track'>"
           DISPLAY "        <span class='bar-fill' style='width:"
                   FUNCTION TRIM(WS-BAR-PCT) "%'></span>"
           DISPLAY "      </span>"
           DISPLAY "      <span class='bar-value'>"
                   FUNCTION TRIM(WS-NUM-FR) " EUR</span>"
           DISPLAY "    </li>"
           .

       RESOLVE-MONTH-LABEL.
           EVALUATE WS-IDX
               WHEN  1 MOVE "JAN" TO WS-MONTH-LBL
               WHEN  2 MOVE "FEB" TO WS-MONTH-LBL
               WHEN  3 MOVE "MAR" TO WS-MONTH-LBL
               WHEN  4 MOVE "APR" TO WS-MONTH-LBL
               WHEN  5 MOVE "MAY" TO WS-MONTH-LBL
               WHEN  6 MOVE "JUN" TO WS-MONTH-LBL
               WHEN  7 MOVE "JUL" TO WS-MONTH-LBL
               WHEN  8 MOVE "AUG" TO WS-MONTH-LBL
               WHEN  9 MOVE "SEP" TO WS-MONTH-LBL
               WHEN 10 MOVE "OCT" TO WS-MONTH-LBL
               WHEN 11 MOVE "NOV" TO WS-MONTH-LBL
               WHEN 12 MOVE "DEC" TO WS-MONTH-LBL
           END-EVALUATE
           .

      *> Quarterly summary table.
       RENDER-QUARTERLY-TABLE.
           DISPLAY "  <h3>Quarterly URSSAF declarations</h3>"
           DISPLAY "  <table>"
           DISPLAY "    <thead><tr>"
           DISPLAY "      <th>QUARTER</th>"
           DISPLAY "      <th>INVOICES</th>"
           DISPLAY "      <th class='num'>HT</th>"
           DISPLAY "      <th class='num'>TVA</th>"
           DISPLAY "      <th class='num'>URSSAF DUE</th>"
           DISPLAY "    </tr></thead>"
           DISPLAY "    <tbody>"

           PERFORM VARYING WS-IDX FROM 1 BY 1 UNTIL WS-IDX > 4
               PERFORM RENDER-QUARTER-ROW
           END-PERFORM

           DISPLAY "    </tbody>"
           DISPLAY "  </table>"
           .

       RENDER-QUARTER-ROW.
           DISPLAY "      <tr>"
           EVALUATE WS-IDX
               WHEN 1 DISPLAY "        <td>Q1 (Jan-Mar)</td>"
               WHEN 2 DISPLAY "        <td>Q2 (Apr-Jun)</td>"
               WHEN 3 DISPLAY "        <td>Q3 (Jul-Sep)</td>"
               WHEN 4 DISPLAY "        <td>Q4 (Oct-Dec)</td>"
           END-EVALUATE
           DISPLAY "        <td>" Q-COUNT(WS-IDX) "</td>"

           MOVE Q-HT(WS-IDX) TO WS-NUM-IN
           PERFORM FORMAT-NUM-FR
           DISPLAY "        <td class='num'>"
                   FUNCTION TRIM(WS-NUM-FR) " EUR</td>"

           MOVE Q-TVA(WS-IDX) TO WS-NUM-IN
           PERFORM FORMAT-NUM-FR
           DISPLAY "        <td class='num'>"
                   FUNCTION TRIM(WS-NUM-FR) " EUR</td>"

           MOVE Q-URSSAF(WS-IDX) TO WS-NUM-IN
           PERFORM FORMAT-NUM-FR
           DISPLAY "        <td class='num'>"
                   FUNCTION TRIM(WS-NUM-FR) " EUR</td>"
           DISPLAY "      </tr>"
           .

      *> YTD totals.
       RENDER-YTD.
           DISPLAY "  <h3>Year to date</h3>"
           DISPLAY "  <table class='totals'>"

           MOVE WS-YTD-HT TO WS-NUM-IN
           PERFORM FORMAT-NUM-FR
           DISPLAY "    <tr><th>Total H.T.</th>"
                   "<td class='num'>"
                   FUNCTION TRIM(WS-NUM-FR) " EUR</td></tr>"

           MOVE WS-YTD-TVA TO WS-NUM-IN
           PERFORM FORMAT-NUM-FR
           DISPLAY "    <tr><th>TVA collected</th>"
                   "<td class='num'>"
                   FUNCTION TRIM(WS-NUM-FR) " EUR</td></tr>"

           MOVE WS-YTD-TTC TO WS-NUM-IN
           PERFORM FORMAT-NUM-FR
           DISPLAY "    <tr class='ttc'><th>Total T.T.C.</th>"
                   "<td class='num'>"
                   FUNCTION TRIM(WS-NUM-FR) " EUR</td></tr>"

           MOVE WS-YTD-URSSAF TO WS-NUM-IN
           PERFORM FORMAT-NUM-FR
           DISPLAY "    <tr><th>URSSAF due (22%)</th>"
                   "<td class='num'>"
                   FUNCTION TRIM(WS-NUM-FR) " EUR</td></tr>"

           MOVE WS-YTD-NET TO WS-NUM-IN
           PERFORM FORMAT-NUM-FR
           DISPLAY "    <tr><th>Net revenue</th>"
                   "<td class='num'>"
                   FUNCTION TRIM(WS-NUM-FR) " EUR</td></tr>"

           DISPLAY "  </table>"
           .

      *> VAT threshold tracker.
      *> Computes:
      *>   pct  = ytd / threshold * 100
      *>   level = safe / warn / alert / exceeded
      *>   crossing date = jan1 + threshold / daily_rate
       RENDER-VAT-THRESHOLD.
           PERFORM COMPUTE-VAT-METRICS

           DISPLAY "  <h3>VAT threshold</h3>"

           MOVE WS-YTD-HT TO WS-NUM-IN
           PERFORM FORMAT-NUM-FR

           DISPLAY "  <div class='vat-tracker vat-"
                   FUNCTION TRIM(WS-VAT-LEVEL) "'>"
           DISPLAY "    <div class='vat-bar'>"
           DISPLAY "      <div class='vat-fill' style='width:"
                   FUNCTION TRIM(WS-VAT-BAR-PCT) "%'></div>"
           DISPLAY "    </div>"
           MOVE WS-VAT-PCT TO WS-VAT-PCT-DISP
           DISPLAY "    <p class='vat-summary'>"
                   FUNCTION TRIM(WS-VAT-PCT-DISP) "% &middot; "
                   FUNCTION TRIM(WS-NUM-FR) " EUR / "

           MOVE WS-VAT-THRESH TO WS-NUM-IN
           PERFORM FORMAT-NUM-FR
           DISPLAY "      "
                   FUNCTION TRIM(WS-NUM-FR)
                   " EUR (services BNC)"
                   "</p>"

           PERFORM RENDER-VAT-CALL-TO-ACTION
           DISPLAY "  </div>"
           .

       COMPUTE-VAT-METRICS.
      *>   Compute year-to-date %.
           IF WS-VAT-THRESH = 0
               MOVE 0 TO WS-VAT-PCT
           ELSE
               COMPUTE WS-VAT-PCT ROUNDED =
                   WS-YTD-HT * 100 / WS-VAT-THRESH
           END-IF

      *>   Bar fill is capped at 100 visually.
           IF WS-VAT-PCT > 100
               MOVE 100 TO WS-VAT-BAR-PCT
           ELSE
               MOVE WS-VAT-PCT TO WS-VAT-BAR-PCT
           END-IF

      *>   Severity level for CSS theming.
           EVALUATE TRUE
               WHEN WS-VAT-PCT >= 100
                   MOVE "exceeded" TO WS-VAT-LEVEL
               WHEN WS-VAT-PCT >= 90
                   MOVE "alert"    TO WS-VAT-LEVEL
               WHEN WS-VAT-PCT >= 80
                   MOVE "warn"     TO WS-VAT-LEVEL
               WHEN OTHER
                   MOVE "safe"     TO WS-VAT-LEVEL
           END-EVALUATE

           PERFORM COMPUTE-CROSSING-DATE
           .

       COMPUTE-TODAY-INT.
      *>   Build today + jan1 of the filtered year as date integers,
      *>   so every later step (aging, vat projection) can subtract.
           STRING WS-FILTER-YEAR DELIMITED BY SIZE
                  "0101"         DELIMITED BY SIZE
               INTO WS-JAN1-DATE
           STRING FUNCTION CURRENT-DATE(1:8)
                  DELIMITED BY SIZE
               INTO WS-TODAY-DATE
           COMPUTE WS-JAN1-INT  = FUNCTION INTEGER-OF-DATE(
                                      WS-JAN1-DATE)
           COMPUTE WS-TODAY-INT = FUNCTION INTEGER-OF-DATE(
                                      WS-TODAY-DATE)
           .

       COMPUTE-CROSSING-DATE.
           MOVE 0 TO WS-DAYS-IN
           MOVE 0 TO WS-DAYS-TO-CROSS
           MOVE 0 TO WS-PROJ-EOY
           MOVE SPACES TO WS-CROSS-FR

           IF WS-YTD-HT = 0
               EXIT PARAGRAPH
           END-IF

           COMPUTE WS-DAYS-IN = WS-TODAY-INT - WS-JAN1-INT + 1
           IF WS-DAYS-IN <= 0
      *>       Filter year is in the future, no projection.
               EXIT PARAGRAPH
           END-IF

      *>   Project end-of-year HT at current pace.
           COMPUTE WS-DAILY-RATE ROUNDED =
               WS-YTD-HT / WS-DAYS-IN
           COMPUTE WS-PROJ-EOY ROUNDED =
               WS-DAILY-RATE * 365

      *>   Days needed (from jan1) to reach the threshold.
           IF WS-DAILY-RATE > 0
               COMPUTE WS-DAYS-TO-CROSS ROUNDED =
                   WS-VAT-THRESH / WS-DAILY-RATE
           END-IF

      *>   Convert that day-of-year to a calendar date (FR format).
           IF WS-DAYS-TO-CROSS > 0
                   AND WS-DAYS-TO-CROSS <= 365
               COMPUTE WS-CROSS-INT =
                   WS-JAN1-INT + WS-DAYS-TO-CROSS - 1
               COMPUTE WS-CROSS-DATE =
                   FUNCTION DATE-OF-INTEGER(WS-CROSS-INT)
               STRING WS-CROSS-DATE(7:2) DELIMITED BY SIZE
                      "/"                DELIMITED BY SIZE
                      WS-CROSS-DATE(5:2) DELIMITED BY SIZE
                      "/"                DELIMITED BY SIZE
                      WS-CROSS-DATE(1:4) DELIMITED BY SIZE
                   INTO WS-CROSS-FR
           END-IF
           .

       RENDER-VAT-CALL-TO-ACTION.
           EVALUATE FUNCTION TRIM(WS-VAT-LEVEL)
               WHEN "exceeded"
                   DISPLAY "    <p class='vat-cta warn'>"
                           "Threshold exceeded &mdash; "
                           "TVA must be charged on every "
                           "invoice from now on."
                           "</p>"
               WHEN "alert"
                   PERFORM EMIT-VAT-PROJECTION
               WHEN "warn"
                   PERFORM EMIT-VAT-PROJECTION
               WHEN OTHER
                   PERFORM EMIT-VAT-PROJECTION
           END-EVALUATE
           .

       EMIT-VAT-PROJECTION.
           IF WS-DAYS-IN = 0
               EXIT PARAGRAPH
           END-IF

           MOVE WS-PROJ-EOY TO WS-NUM-IN
           PERFORM FORMAT-NUM-FR

           IF WS-CROSS-FR NOT = SPACES
               DISPLAY "    <p class='vat-cta'>"
                       "Estimated crossing : "
                       FUNCTION TRIM(WS-CROSS-FR)
                       " &middot; projected EOY: "
                       FUNCTION TRIM(WS-NUM-FR)
                       " EUR"
                       "</p>"
           ELSE
               DISPLAY "    <p class='vat-cta muted'>"
                       "At current pace, threshold "
                       "won't be crossed this year "
                       "(projected EOY: "
                       FUNCTION TRIM(WS-NUM-FR)
                       " EUR)."
                       "</p>"
           END-IF
           .

      *> Outstanding receivables — aging buckets + overdue list.
       RENDER-OUTSTANDING.
           DISPLAY "  <h3>Outstanding receivables</h3>"

           IF WS-OD-COUNT = 0
                   AND WS-AGE-COUNT(1) = 0
               DISPLAY "  <p class='muted'>"
                       "No outstanding invoices."
                       "</p>"
               EXIT PARAGRAPH
           END-IF

           PERFORM RENDER-AGING-TABLE
           IF WS-OD-COUNT > 0
               PERFORM RENDER-OVERDUE-LIST
           END-IF
           .

       RENDER-AGING-TABLE.
           DISPLAY "  <table>"
           DISPLAY "    <thead><tr>"
           DISPLAY "      <th>BUCKET</th>"
           DISPLAY "      <th>INVOICES</th>"
           DISPLAY "      <th class='num'>OUTSTANDING</th>"
           DISPLAY "    </tr></thead>"
           DISPLAY "    <tbody>"

           PERFORM VARYING WS-IDX FROM 1 BY 1 UNTIL WS-IDX > 5
               PERFORM RENDER-AGING-ROW
           END-PERFORM

           DISPLAY "    </tbody>"
           DISPLAY "  </table>"
           .

       RENDER-AGING-ROW.
           IF WS-AGE-COUNT(WS-IDX) = 0
               EXIT PARAGRAPH
           END-IF

           MOVE WS-AGE-TOTAL(WS-IDX) TO WS-NUM-IN
           PERFORM FORMAT-NUM-FR

           EVALUATE WS-IDX
               WHEN 1 DISPLAY "      <tr class='aging-fresh'>"
               WHEN 2 DISPLAY "      <tr class='aging-30'>"
               WHEN 3 DISPLAY "      <tr class='aging-60'>"
               WHEN 4 DISPLAY "      <tr class='aging-90'>"
               WHEN 5 DISPLAY "      <tr class='aging-old'>"
           END-EVALUATE

           DISPLAY "        <td>"
                   FUNCTION TRIM(WS-AGE-LABEL(WS-IDX))
                   "</td>"
           DISPLAY "        <td>" WS-AGE-COUNT(WS-IDX) "</td>"
           DISPLAY "        <td class='num'>"
                   FUNCTION TRIM(WS-NUM-FR) " EUR</td>"
           DISPLAY "      </tr>"
           .

       RENDER-OVERDUE-LIST.
           DISPLAY "  <h4>Overdue invoices</h4>"
           DISPLAY "  <table>"
           DISPLAY "    <thead><tr>"
           DISPLAY "      <th>NUMBER</th>"
           DISPLAY "      <th>CLIENT</th>"
           DISPLAY "      <th>DUE</th>"
           DISPLAY "      <th class='num'>DAYS LATE</th>"
           DISPLAY "      <th class='num'>AMOUNT</th>"
           DISPLAY "    </tr></thead>"
           DISPLAY "    <tbody>"

           PERFORM VARYING WS-IDX FROM 1 BY 1
                   UNTIL WS-IDX > WS-OD-COUNT
               PERFORM RENDER-OVERDUE-ROW
           END-PERFORM

           DISPLAY "    </tbody>"
           DISPLAY "  </table>"
           .

       RENDER-OVERDUE-ROW.
           DISPLAY "      <tr>"
           DISPLAY "        <td><a class='inv-link'"
           DISPLAY "             hx-get='/cgi-bin/invoice"
                   "?action=get&number="
                   FUNCTION TRIM(OD-NUMBER(WS-IDX)) "'"
           DISPLAY "             hx-target='#content'"
           DISPLAY "             hx-swap='innerHTML'>"
                   FUNCTION TRIM(OD-NUMBER(WS-IDX))
                   "</a></td>"
           DISPLAY "        <td>"
                   FUNCTION TRIM(OD-CLIENT(WS-IDX))
                   "</td>"

      *>   Format due date FR.
           DISPLAY "        <td>"
                   OD-DUE(WS-IDX)(9:2) "/"
                   OD-DUE(WS-IDX)(6:2) "/"
                   OD-DUE(WS-IDX)(1:4)
                   "</td>"

           MOVE OD-DAYS(WS-IDX) TO WS-DAYS-DIFF-DISP
           DISPLAY "        <td class='num warn'>"
                   FUNCTION TRIM(WS-DAYS-DIFF-DISP)
                   "</td>"

           MOVE OD-TTC(WS-IDX) TO WS-NUM-IN
           PERFORM FORMAT-NUM-FR
           DISPLAY "        <td class='num'>"
                   FUNCTION TRIM(WS-NUM-FR) " EUR</td>"
           DISPLAY "      </tr>"
           .

      *> FR amount formatter (same as invoice / pdf-gen).
       FORMAT-NUM-FR.
           MOVE WS-NUM-IN TO WS-NUM-EDITED
           MOVE WS-NUM-EDITED TO WS-NUM-FR
           INSPECT WS-NUM-FR REPLACING ALL "," BY " "
           INSPECT WS-NUM-FR REPLACING ALL "." BY ","
           .

       COPY "auth-check-procs.cpy".
       COPY "cgi-utils-procs.cpy".

       END PROGRAM DASHBOARD.
