       IDENTIFICATION DIVISION.
       PROGRAM-ID. SIRENE.

       ENVIRONMENT DIVISION.
       CONFIGURATION SECTION.
       COPY "special-names.cpy".

       INPUT-OUTPUT SECTION.
       FILE-CONTROL.
           SELECT TMP-FILE
               ASSIGN TO WS-TMPFILE
               ORGANIZATION IS LINE SEQUENTIAL
               FILE STATUS IS WS-TMP-STATUS.

           SELECT SESSION-FILE
               ASSIGN TO "data/sessions.dat"
               ORGANIZATION IS INDEXED
               ACCESS MODE IS DYNAMIC
               RECORD KEY IS SES-TOKEN
               FILE STATUS IS WS-AUTH-FS-STATUS.

       DATA DIVISION.
       FILE SECTION.
       FD TMP-FILE.
       01 TMP-LINE PIC X(500).

       FD SESSION-FILE.
       COPY "session-record.cpy".

       WORKING-STORAGE SECTION.
       COPY "cgi-utils-ws.cpy".
       COPY "auth-check-ws.cpy".

       01 WS-TMP-STATUS  PIC XX.
       01 WS-SIRET-IN    PIC X(20).
       01 WS-SIRET       PIC X(14).
       01 WS-SIRET-LEN   PIC 99 VALUE 0.
       01 WS-S-IDX       PIC 9(3).
       01 WS-S-CH        PIC X.

       01 WS-TMPFILE     PIC X(64).
       01 WS-CMD         PIC X(600).
       01 WS-RC          USAGE BINARY-LONG.

       01 WS-NAME        PIC X(200) VALUE SPACES.
       01 WS-ADDRESS     PIC X(200) VALUE SPACES.
       01 WS-ZIP         PIC X(20)  VALUE SPACES.
       01 WS-CITY        PIC X(100) VALUE SPACES.

       01 WS-LINE-NUM    PIC 9 VALUE 0.
       01 WS-EOF         PIC X VALUE "N".

       PROCEDURE DIVISION.
       MAIN-LOGIC.
           PERFORM READ-CGI-INPUT
           PERFORM PARSE-CGI-INPUT
           COPY "auth-check.cpy".
           PERFORM EMIT-HTML-HEADERS

           MOVE SPACES TO WS-SIRET-IN
           MOVE "siret" TO CGI-L-KEY
           PERFORM FIND-FIELD
           IF CGI-L-FOUND = "Y"
               MOVE FUNCTION TRIM(CGI-L-VALUE) TO WS-SIRET-IN
           END-IF

           PERFORM SANITIZE-SIRET

           IF WS-SIRET-LEN NOT = 9 AND WS-SIRET-LEN NOT = 14
               PERFORM RENDER-INVALID
               STOP RUN
           END-IF

           PERFORM BUILD-TMPFILE
           PERFORM RUN-LOOKUP

           IF WS-RC NOT = 0
               PERFORM RENDER-API-ERROR
               PERFORM CLEANUP
               STOP RUN
           END-IF

           PERFORM PARSE-RESULT
           PERFORM CLEANUP

           IF FUNCTION TRIM(WS-NAME) = SPACES
               PERFORM RENDER-NOT-FOUND
               STOP RUN
           END-IF

           PERFORM RENDER-FOUND

           STOP RUN.

      *> Strip non-digits from input, cap at 14 chars (SIRET length).
       SANITIZE-SIRET.
           MOVE 0 TO WS-SIRET-LEN
           MOVE SPACES TO WS-SIRET
           PERFORM VARYING WS-S-IDX FROM 1 BY 1 UNTIL WS-S-IDX > 20
               MOVE WS-SIRET-IN(WS-S-IDX:1) TO WS-S-CH
               IF WS-S-CH >= "0" AND WS-S-CH <= "9"
                   IF WS-SIRET-LEN < 14
                       ADD 1 TO WS-SIRET-LEN
                       MOVE WS-S-CH TO WS-SIRET(WS-SIRET-LEN:1)
                   END-IF
               END-IF
           END-PERFORM
           .

      *> Per-process tmp file (seconds-of-day discriminator is enough
      *> for solo use; CGI is single-shot so no concurrent collision).
       BUILD-TMPFILE.
           MOVE SPACES TO WS-TMPFILE
           STRING "/tmp/sirene-"
                  FUNCTION CURRENT-DATE(9:8)
                  ".txt"
               DELIMITED BY SIZE
               INTO WS-TMPFILE
           END-STRING
           .

      *> Hit recherche-entreprises.api.gouv.fr through curl, pipe to jq
      *> (script in lib/sirene-extract.jq), redirect to tmp file.
      *> SIRET is digits-only here (sanitized), so safe to interpolate.
       RUN-LOOKUP.
           MOVE SPACES TO WS-CMD
           STRING "curl -sS --max-time 5 "
                  "'https://recherche-entreprises.api.gouv.fr"
                  "/search?q="
                  WS-SIRET(1:WS-SIRET-LEN)
                  "&per_page=1' | jq -rf lib/sirene-extract.jq > "
                  FUNCTION TRIM(WS-TMPFILE)
                  " 2>/dev/null"
               DELIMITED BY SIZE
               INTO WS-CMD
           END-STRING
           CALL "SYSTEM" USING WS-CMD RETURNING WS-RC
           .

       PARSE-RESULT.
           OPEN INPUT TMP-FILE
           IF WS-TMP-STATUS NOT = "00"
               EXIT PARAGRAPH
           END-IF
           MOVE 0 TO WS-LINE-NUM
           MOVE "N" TO WS-EOF
           PERFORM UNTIL WS-EOF = "Y"
               READ TMP-FILE
                   AT END MOVE "Y" TO WS-EOF
                   NOT AT END
                       ADD 1 TO WS-LINE-NUM
                       EVALUATE WS-LINE-NUM
                           WHEN 1 MOVE TMP-LINE TO WS-NAME
                           WHEN 2 MOVE TMP-LINE TO WS-ADDRESS
                           WHEN 3 MOVE TMP-LINE TO WS-ZIP
                           WHEN 4 MOVE TMP-LINE TO WS-CITY
                       END-EVALUATE
               END-READ
           END-PERFORM
           CLOSE TMP-FILE
           .

       CLEANUP.
           MOVE SPACES TO WS-CMD
           STRING "rm -f " FUNCTION TRIM(WS-TMPFILE)
               DELIMITED BY SIZE INTO WS-CMD
           CALL "SYSTEM" USING WS-CMD RETURNING WS-RC
           .

      *> Successful enrichment: hint into #sirene-hint, OOB swaps for
      *> the four form inputs (matching ids in client.cob's RENDER-FORM).
       RENDER-FOUND.
           DISPLAY "<span class='sirene-ok'>"
                   "Donnees INSEE importees, verifiez avant validation."
                   "</span>"

           MOVE WS-NAME TO HTML-IN
           PERFORM HTML-ESCAPE
           DISPLAY "<input id='f-name' name='name' required "
                   "hx-swap-oob='true' value='"
                   HTML-OUT(1:HTML-OUT-LEN) "'>"

           MOVE WS-ADDRESS TO HTML-IN
           PERFORM HTML-ESCAPE
           DISPLAY "<input id='f-addr' name='address' "
                   "hx-swap-oob='true' value='"
                   HTML-OUT(1:HTML-OUT-LEN) "'>"

           MOVE WS-ZIP TO HTML-IN
           PERFORM HTML-ESCAPE
           DISPLAY "<input id='f-zip' name='zip' class='small' "
                   "hx-swap-oob='true' value='"
                   HTML-OUT(1:HTML-OUT-LEN) "'>"

           MOVE WS-CITY TO HTML-IN
           PERFORM HTML-ESCAPE
           DISPLAY "<input id='f-city' name='city' "
                   "hx-swap-oob='true' value='"
                   HTML-OUT(1:HTML-OUT-LEN) "'>"
           .

       RENDER-INVALID.
           DISPLAY "<span class='sirene-err'>"
                   "SIRET invalide (9 ou 14 chiffres attendus)."
                   "</span>"
           .

       RENDER-NOT-FOUND.
           DISPLAY "<span class='sirene-err'>"
                   "Aucun resultat pour ce SIRET."
                   "</span>"
           .

       RENDER-API-ERROR.
           DISPLAY "<span class='sirene-err'>"
                   "L'API INSEE n'a pas repondu, reessayer plus tard."
                   "</span>"
           .

       COPY "auth-check-procs.cpy".
       COPY "cgi-utils-procs.cpy".

       END PROGRAM SIRENE.
