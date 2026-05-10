      *> sirene.cob
      *>
      *> Client enrichment from the SIRET (French company id) via
      *> the public DINUM API recherche-entreprises.api.gouv.fr.
      *>
      *> Endpoint:   /cgi-bin/sirene?siret=<siret>
      *> Auth gate:  yes (auth-check.cpy)
      *> Method:     GET (HTMX issues hx-get from the [INSEE] button
      *>             of the client form)
      *>
      *> Flow:
      *>   1. Sanitize the SIRET (digits only, accept 9 or 14).
      *>   2. Pipe curl + jq into a per-process tmp file.
      *>   3. Read 4 lines (name / address / zip / city) from the
      *>      tmp file.
      *>   4. Reply with an HTMX fragment that contains four
      *>      "hx-swap-oob='true'" inputs targeting the matching
      *>      ids in the client form (#f-name, #f-addr, #f-zip,
      *>      #f-city). HTMX dispatches the swaps out-of-band so
      *>      the four fields update from a single response.
      *>
      *> Failure modes: invalid SIRET, API down, SIRET not found
      *> in the registry. Each produces a small HTML error span
      *> the user can dismiss; the manual entry path stays open.
       IDENTIFICATION DIVISION.
       PROGRAM-ID. SIRENE.

       ENVIRONMENT DIVISION.
       CONFIGURATION SECTION.
       COPY "special-names.cpy".

       INPUT-OUTPUT SECTION.
       FILE-CONTROL.
      *>     Per-request scratch file. Written by curl/jq, read
      *>     back line-by-line by PARSE-RESULT.
           SELECT TMP-FILE
               ASSIGN TO WS-TMPFILE
               ORGANIZATION IS LINE SEQUENTIAL
               FILE STATUS IS WS-TMP-STATUS.

      *>     Sessions file, opened by the auth gate to validate
      *>     the COBILL_SID cookie.
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

      *> Tmp file ISAM status (for the line-sequential file). "00"
      *> on success.
       01 WS-TMP-STATUS  PIC XX.

      *> Raw SIRET coming from the form. Up to 20 chars to absorb
      *> spaces, dashes or any extra typing.
       01 WS-SIRET-IN    PIC X(20).
      *> Sanitized SIRET (digits only).
       01 WS-SIRET       PIC X(14).
      *> Length of the sanitized SIRET. Accept only 9 (SIREN) or
      *> 14 (SIRET).
       01 WS-SIRET-LEN   PIC 99 VALUE 0.
       01 WS-S-IDX       PIC 9(3).
       01 WS-S-CH        PIC X.

      *> Path of the per-request tmp file. Generated, not user-
      *> derived, so safe to interpolate in a shell command.
       01 WS-TMPFILE     PIC X(64).
      *> Buffer used to build the shell command (curl + jq + rm).
       01 WS-CMD         PIC X(600).
      *> Return code of CALL "SYSTEM". 0 = success.
       01 WS-RC          USAGE BINARY-LONG.

      *> Fields extracted from the API response. PARSE-RESULT
      *> reads 4 lines from the tmp file into these.
       01 WS-NAME        PIC X(200) VALUE SPACES.
       01 WS-ADDRESS     PIC X(200) VALUE SPACES.
       01 WS-ZIP         PIC X(20)  VALUE SPACES.
       01 WS-CITY        PIC X(100) VALUE SPACES.

       01 WS-LINE-NUM    PIC 9 VALUE 0.
       01 WS-EOF         PIC X VALUE "N".

       PROCEDURE DIVISION.
       MAIN-LOGIC.
      *>   Standard CGI prologue + auth gate.
           PERFORM READ-CGI-INPUT
           PERFORM PARSE-CGI-INPUT
           COPY "auth-check.cpy".
           PERFORM EMIT-HTML-HEADERS

      *>   Pull the SIRET from the query string.
           MOVE SPACES TO WS-SIRET-IN
           MOVE "siret" TO CGI-L-KEY
           PERFORM FIND-FIELD
           IF CGI-L-FOUND = "Y"
               MOVE FUNCTION TRIM(CGI-L-VALUE) TO WS-SIRET-IN
           END-IF

      *>   Keep only digits. After this, WS-SIRET is safe to drop
      *>   into a shell command without quoting concerns.
           PERFORM SANITIZE-SIRET

      *>   A SIREN (legal entity, 9 digits) or full SIRET
      *>   (establishment, 14 digits) is required. Anything else
      *>   gets a 200 with an error span (HTMX swaps it into the
      *>   hint slot).
           IF WS-SIRET-LEN NOT = 9 AND WS-SIRET-LEN NOT = 14
               PERFORM RENDER-INVALID
               STOP RUN
           END-IF

      *>   Build the unique tmp path, then call curl + jq.
           PERFORM BUILD-TMPFILE
           PERFORM RUN-LOOKUP

      *>   Non-zero return code: curl failed (DNS, timeout) or jq
      *>   choked. Treat both as a transient API outage.
           IF WS-RC NOT = 0
               PERFORM RENDER-API-ERROR
               PERFORM CLEANUP
               STOP RUN
           END-IF

      *>   Read the 4-line tmp file, then delete it.
           PERFORM PARSE-RESULT
           PERFORM CLEANUP

      *>   Empty name means the SIRET was syntactically valid but
      *>   the registry returned no result.
           IF FUNCTION TRIM(WS-NAME) = SPACES
               PERFORM RENDER-NOT-FOUND
               STOP RUN
           END-IF

           PERFORM RENDER-FOUND

           STOP RUN.

      *> SANITIZE-SIRET
      *>
      *> Walk the raw input character by character, keep digits,
      *> drop anything else. Cap the result at 14 characters (full
      *> SIRET length). After this paragraph runs, WS-SIRET holds
      *> a digits-only string of length WS-SIRET-LEN.
      *>
      *> Crucial for security: the SIRET is the only piece of user
      *> input that ends up in a shell command. By guaranteeing it
      *> is digits-only, we make shell injection structurally
      *> impossible without resorting to quoting.
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

      *> BUILD-TMPFILE
      *>
      *> Construct a per-request tmp path of the form
      *> /tmp/sirene-HHMMSSCC.txt where HHMMSSCC is the
      *> hour/minute/second/centisecond piece of CURRENT-DATE.
      *> CGI is single-shot (one process per request), so a
      *> collision would require two requests within the same
      *> centisecond from the same user. Acceptable for solo use.
       BUILD-TMPFILE.
           MOVE SPACES TO WS-TMPFILE
           STRING "/tmp/sirene-"
                  FUNCTION CURRENT-DATE(9:8)
                  ".txt"
               DELIMITED BY SIZE
               INTO WS-TMPFILE
           END-STRING
           .

      *> RUN-LOOKUP
      *>
      *> Hit recherche-entreprises.api.gouv.fr through curl, with
      *> a 5-second timeout to keep the request snappy. The JSON
      *> response is piped to jq, which uses lib/sirene-extract.jq
      *> to print four lines (name / address / zip / city) into
      *> the tmp file. stderr is discarded; curl/jq failures show
      *> up as a non-zero return code from CALL "SYSTEM".
      *>
      *> Note: WS-SIRET went through SANITIZE-SIRET so it is
      *> guaranteed digits-only. That is why interpolating it
      *> directly into the shell command is safe.
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

      *> PARSE-RESULT
      *>
      *> Read up to 4 lines from the tmp file written by jq:
      *>   line 1 -> company name
      *>   line 2 -> street address
      *>   line 3 -> ZIP code
      *>   line 4 -> city
      *> A SIRET that the registry does not know about produces an
      *> empty file; in that case all four WS- fields stay blank
      *> and MAIN-LOGIC routes to RENDER-NOT-FOUND.
       PARSE-RESULT.
           OPEN INPUT TMP-FILE
      *>   Tmp file missing: probably curl/jq failed without
      *>   producing output. Stay blank.
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

      *> CLEANUP
      *>
      *> Best-effort delete of the tmp file. The path is generated
      *> server-side so it is safe to interpolate.
       CLEANUP.
           MOVE SPACES TO WS-CMD
           STRING "rm -f " FUNCTION TRIM(WS-TMPFILE)
               DELIMITED BY SIZE INTO WS-CMD
           CALL "SYSTEM" USING WS-CMD RETURNING WS-RC
           .

      *> RENDER-FOUND
      *>
      *> Successful enrichment. Emits five HTML fragments:
      *>   - a hint span that swaps into #sirene-hint
      *>   - four <input> elements carrying hx-swap-oob='true'
      *>     and ids that match the client form (#f-name, #f-addr,
      *>     #f-zip, #f-city). HTMX picks them up and dispatches
      *>     each swap out-of-band, so a single HTTP response
      *>     updates all four fields at once.
      *>
      *> Every value goes through HTML-ESCAPE first to neutralize
      *> any HTML metacharacters the API may have returned.
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

      *> Error renderers. All three reply 200 OK with a small HTML
      *> span; HTMX swaps the span into #sirene-hint and the user
      *> stays on the form to enter the data by hand.

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

      *> Auth gate paragraphs (AUTH-CHECK, AUTH-REDIRECT-LOGIN,
      *> AUTH-PARSE-COOKIE, AUTH-CHECK-EXPIRY) and the standard CGI
      *> helpers (READ-CGI-INPUT, PARSE-CGI-INPUT, URL-DECODE,
      *> HTML-ESCAPE, FIND-FIELD, EMIT-HTML-HEADERS, ...).
       COPY "auth-check-procs.cpy".
       COPY "cgi-utils-procs.cpy".

       END PROGRAM SIRENE.
