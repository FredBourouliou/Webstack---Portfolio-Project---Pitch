       IDENTIFICATION DIVISION.
       PROGRAM-ID. AUTH.

       ENVIRONMENT DIVISION.
       CONFIGURATION SECTION.
       COPY "special-names.cpy".

       INPUT-OUTPUT SECTION.
       FILE-CONTROL.
           SELECT SESSION-FILE
               ASSIGN TO "data/sessions.dat"
               ORGANIZATION IS INDEXED
               ACCESS MODE IS DYNAMIC
               RECORD KEY IS SES-TOKEN
               FILE STATUS IS WS-SES-STATUS.

       DATA DIVISION.
       FILE SECTION.
       FD SESSION-FILE.
       COPY "session-record.cpy".

       WORKING-STORAGE SECTION.
       COPY "cgi-utils-ws.cpy".

       01 WS-SES-STATUS    PIC XX.
       01 WS-ACTION        PIC X(10) VALUE SPACES.

       01 WS-SUBMITTED-USER PIC X(30).
       01 WS-SUBMITTED-PASS PIC X(60).

       01 WS-AUTH-USER     PIC X(30) VALUE "admin".
       01 WS-EXPECTED-PASS PIC X(60).
       01 WS-EXPECTED-HASH PIC X(128).
       01 WS-AUTH-MODE     PIC X(8) VALUE "PLAIN".
       01 WS-AUTH-OK       PIC X VALUE "N".

      *> crypt(3) FFI buffers (null-terminated C strings).
       01 WS-PASS-CSTR     PIC X(64).
       01 WS-HASH-CSTR     PIC X(128).
       01 WS-CRYPT-RC      USAGE POINTER.
       01 WS-RESULT-VIEW   PIC X(128) BASED.
       01 WS-CMP-IDX       PIC 9(4).

       01 WS-NEW-TOKEN     PIC X(32) VALUE SPACES.
       01 WS-RAND-A        PIC 9(10).
       01 WS-RAND-B        PIC 9(10).
       01 WS-DATE-PART     PIC X(14).

       01 WS-NOW-FMT       PIC X(19).
       01 WS-EXPIRES-FMT   PIC X(19).
       01 WS-TODAY-INT     PIC S9(8).
       01 WS-TODAY-DATE    PIC 9(8).
       01 WS-TODAY-FMT     PIC X(10).
       01 WS-EXPIRES-INT   PIC S9(8).
       01 WS-EXPIRES-DATE  PIC 9(8).

       01 WS-COOKIE-TOKEN  PIC X(32).

       PROCEDURE DIVISION.
       MAIN-LOGIC.
           PERFORM READ-CGI-INPUT
           PERFORM PARSE-CGI-INPUT

           MOVE "action" TO CGI-L-KEY
           PERFORM FIND-FIELD
           IF CGI-L-FOUND = "Y"
               MOVE FUNCTION TRIM(CGI-L-VALUE) TO WS-ACTION
           END-IF

           EVALUATE FUNCTION TRIM(WS-ACTION)
               WHEN "login"
                   PERFORM ACTION-LOGIN
               WHEN "logout"
                   PERFORM ACTION-LOGOUT
               WHEN OTHER
                   PERFORM RENDER-LOGIN-NEEDED
           END-EVALUATE

           STOP RUN.

      *> ACTION-LOGIN — verify creds, create session, set cookie,
      *> redirect home.
       ACTION-LOGIN.
           PERFORM PULL-CREDENTIALS
           PERFORM LOAD-EXPECTED-CREDENTIAL
           PERFORM VERIFY-PASSWORD

           IF FUNCTION TRIM(WS-SUBMITTED-USER)
                  NOT = FUNCTION TRIM(WS-AUTH-USER)
                  OR WS-AUTH-OK NOT = "Y"
               PERFORM RENDER-LOGIN-FAILED
               EXIT PARAGRAPH
           END-IF

           PERFORM GENERATE-TOKEN
           PERFORM COMPUTE-EXPIRY
           PERFORM PERSIST-SESSION
           PERFORM EMIT-LOGIN-SUCCESS
           .

       PULL-CREDENTIALS.
           MOVE SPACES TO WS-SUBMITTED-USER
           MOVE SPACES TO WS-SUBMITTED-PASS

           MOVE "username" TO CGI-L-KEY
           PERFORM FIND-FIELD
           IF CGI-L-FOUND = "Y"
               MOVE CGI-L-VALUE TO WS-SUBMITTED-USER
           END-IF

           MOVE "password" TO CGI-L-KEY
           PERFORM FIND-FIELD
           IF CGI-L-FOUND = "Y"
               MOVE CGI-L-VALUE TO WS-SUBMITTED-PASS
           END-IF
           .

      *> LOAD-EXPECTED-CREDENTIAL — read COBILL_AUTH_HASH (sha512crypt)
      *> if set, otherwise fall back to plaintext COBILL_AUTH_PASS.
       LOAD-EXPECTED-CREDENTIAL.
           MOVE SPACES TO WS-EXPECTED-HASH
           ACCEPT WS-EXPECTED-HASH FROM ENVIRONMENT "COBILL_AUTH_HASH"
               ON EXCEPTION
                   MOVE SPACES TO WS-EXPECTED-HASH
           END-ACCEPT

           IF FUNCTION TRIM(WS-EXPECTED-HASH) NOT = SPACES
              AND WS-EXPECTED-HASH(1:1) = "$"
               MOVE "HASH" TO WS-AUTH-MODE
               EXIT PARAGRAPH
           END-IF

           MOVE "PLAIN" TO WS-AUTH-MODE
           ACCEPT WS-EXPECTED-PASS FROM ENVIRONMENT "COBILL_AUTH_PASS"
               ON EXCEPTION
                   MOVE SPACES TO WS-EXPECTED-PASS
           END-ACCEPT
           IF FUNCTION TRIM(WS-EXPECTED-PASS) = SPACES
               MOVE "cobill" TO WS-EXPECTED-PASS
           END-IF
           .

      *> VERIFY-PASSWORD — set WS-AUTH-OK to "Y" iff submitted
      *> password matches. HASH mode calls crypt(3); PLAIN trims
      *> and compares.
       VERIFY-PASSWORD.
           MOVE "N" TO WS-AUTH-OK

           IF WS-AUTH-MODE = "PLAIN"
               IF FUNCTION TRIM(WS-SUBMITTED-PASS)
                      = FUNCTION TRIM(WS-EXPECTED-PASS)
                   MOVE "Y" TO WS-AUTH-OK
               END-IF
               EXIT PARAGRAPH
           END-IF

           IF FUNCTION TRIM(WS-SUBMITTED-PASS) = SPACES
               EXIT PARAGRAPH
           END-IF

           MOVE LOW-VALUES TO WS-PASS-CSTR
           STRING FUNCTION TRIM(WS-SUBMITTED-PASS) DELIMITED BY SIZE
                  X"00"                            DELIMITED BY SIZE
               INTO WS-PASS-CSTR
           END-STRING

           MOVE LOW-VALUES TO WS-HASH-CSTR
           STRING FUNCTION TRIM(WS-EXPECTED-HASH) DELIMITED BY SIZE
                  X"00"                           DELIMITED BY SIZE
               INTO WS-HASH-CSTR
           END-STRING

      *>   crypt(3) returns NULL on bad salt prefix.
           CALL "crypt"
               USING WS-PASS-CSTR, WS-HASH-CSTR
               RETURNING WS-CRYPT-RC
           END-CALL

           IF WS-CRYPT-RC = NULL
               EXIT PARAGRAPH
           END-IF

      *>   Compare crypt() result and stored hash byte-by-byte
      *>   until both null-terminate.
           SET ADDRESS OF WS-RESULT-VIEW TO WS-CRYPT-RC
           MOVE "Y" TO WS-AUTH-OK
           PERFORM VARYING WS-CMP-IDX FROM 1 BY 1
                   UNTIL WS-CMP-IDX > 128
               IF WS-RESULT-VIEW(WS-CMP-IDX:1) = X"00"
                  AND WS-HASH-CSTR(WS-CMP-IDX:1) = X"00"
                   EXIT PERFORM
               END-IF
               IF WS-RESULT-VIEW(WS-CMP-IDX:1)
                      NOT = WS-HASH-CSTR(WS-CMP-IDX:1)
                   MOVE "N" TO WS-AUTH-OK
                   EXIT PERFORM
               END-IF
           END-PERFORM
           .

      *> Token = YYYYMMDDhhmmss + "-" + 17 random digits, then
      *> truncated to 32 chars by PIC X(32).
       GENERATE-TOKEN.
           COMPUTE WS-RAND-A =
               FUNCTION RANDOM(FUNCTION SECONDS-PAST-MIDNIGHT)
                                                 * 9999999999
           COMPUTE WS-RAND-B = FUNCTION RANDOM   * 9999999999

           MOVE FUNCTION CURRENT-DATE(1:14) TO WS-DATE-PART

           MOVE SPACES TO WS-NEW-TOKEN
           STRING WS-DATE-PART DELIMITED BY SIZE
                  "-"          DELIMITED BY SIZE
                  WS-RAND-A    DELIMITED BY SIZE
                  WS-RAND-B    DELIMITED BY SIZE
               INTO WS-NEW-TOKEN
           .

       COMPUTE-EXPIRY.
      *>   Today YYYY-MM-DD.
           STRING FUNCTION CURRENT-DATE(1:4) DELIMITED BY SIZE
                  "-"                        DELIMITED BY SIZE
                  FUNCTION CURRENT-DATE(5:2) DELIMITED BY SIZE
                  "-"                        DELIMITED BY SIZE
                  FUNCTION CURRENT-DATE(7:2) DELIMITED BY SIZE
               INTO WS-TODAY-FMT

      *>   Now (YYYY-MM-DD hh:mm:ss).
           MOVE SPACES TO WS-NOW-FMT
           STRING WS-TODAY-FMT                   DELIMITED BY SIZE
                  " "                            DELIMITED BY SIZE
                  FUNCTION CURRENT-DATE(9:2)     DELIMITED BY SIZE
                  ":"                            DELIMITED BY SIZE
                  FUNCTION CURRENT-DATE(11:2)    DELIMITED BY SIZE
                  ":"                            DELIMITED BY SIZE
                  FUNCTION CURRENT-DATE(13:2)    DELIMITED BY SIZE
               INTO WS-NOW-FMT

      *>   Expiry = today + 1 day, midnight.
           STRING FUNCTION CURRENT-DATE(1:4) DELIMITED BY SIZE
                  FUNCTION CURRENT-DATE(5:2) DELIMITED BY SIZE
                  FUNCTION CURRENT-DATE(7:2) DELIMITED BY SIZE
               INTO WS-TODAY-DATE
           COMPUTE WS-TODAY-INT  = FUNCTION INTEGER-OF-DATE(
                                       WS-TODAY-DATE)
           COMPUTE WS-EXPIRES-INT = WS-TODAY-INT + 1
           COMPUTE WS-EXPIRES-DATE =
               FUNCTION DATE-OF-INTEGER(WS-EXPIRES-INT)

           MOVE SPACES TO WS-EXPIRES-FMT
           STRING WS-EXPIRES-DATE(1:4) DELIMITED BY SIZE
                  "-"                  DELIMITED BY SIZE
                  WS-EXPIRES-DATE(5:2) DELIMITED BY SIZE
                  "-"                  DELIMITED BY SIZE
                  WS-EXPIRES-DATE(7:2) DELIMITED BY SIZE
                  " 00:00:00"          DELIMITED BY SIZE
               INTO WS-EXPIRES-FMT
           .

       PERSIST-SESSION.
           OPEN I-O SESSION-FILE
           IF WS-SES-STATUS = "35"
               OPEN OUTPUT SESSION-FILE
               CLOSE SESSION-FILE
               OPEN I-O SESSION-FILE
           END-IF

           MOVE WS-NEW-TOKEN  TO SES-TOKEN
           MOVE WS-AUTH-USER  TO SES-USER
           MOVE WS-NOW-FMT    TO SES-CREATED
           MOVE WS-EXPIRES-FMT TO SES-EXPIRES
           MOVE "Y"           TO SES-ACTIVE

           WRITE SESSION-RECORD
               INVALID KEY
                   CONTINUE
               NOT INVALID KEY
                   CONTINUE
           END-WRITE

           CLOSE SESSION-FILE
           .

       EMIT-LOGIN-SUCCESS.
           DISPLAY "Status: 302 Found"
           DISPLAY "Location: /app.html"
           DISPLAY "Set-Cookie: COBILL_SID="
                   FUNCTION TRIM(WS-NEW-TOKEN)
                   "; Path=/; HttpOnly; Max-Age=86400; SameSite=Lax"
           DISPLAY "Content-Type: text/html; charset=utf-8"
           DISPLAY X"0A"
           DISPLAY "<a href='/app.html'>Logged in</a>"
           .

      *> ACTION-LOGOUT — flip session inactive, clear cookie,
      *> redirect to login page.
       ACTION-LOGOUT.
           MOVE SPACES TO WS-COOKIE-TOKEN
           PERFORM EXTRACT-COOKIE-TOKEN

           IF FUNCTION TRIM(WS-COOKIE-TOKEN) NOT = SPACES
               OPEN I-O SESSION-FILE
               IF WS-SES-STATUS = "00"
                   MOVE WS-COOKIE-TOKEN TO SES-TOKEN
                   READ SESSION-FILE
                       INVALID KEY
                           CONTINUE
                       NOT INVALID KEY
                           MOVE "N" TO SES-ACTIVE
                           REWRITE SESSION-RECORD
                               INVALID KEY CONTINUE
                               NOT INVALID KEY CONTINUE
                           END-REWRITE
                   END-READ
                   CLOSE SESSION-FILE
               END-IF
           END-IF

           PERFORM EMIT-LOGOUT
           .

       EXTRACT-COOKIE-TOKEN.
           MOVE 0 TO CGI-W-IDX
           INSPECT CGI-COOKIE TALLYING CGI-W-IDX
               FOR CHARACTERS BEFORE INITIAL "COBILL_SID="
           IF CGI-W-IDX >= FUNCTION LENGTH(CGI-COOKIE)
               EXIT PARAGRAPH
           END-IF
           ADD 12 TO CGI-W-IDX
           MOVE 1 TO CGI-W-IDX2
           PERFORM UNTIL CGI-W-IDX > 512
                      OR CGI-W-IDX2 > 32
                      OR CGI-COOKIE(CGI-W-IDX:1) = ";"
                      OR CGI-COOKIE(CGI-W-IDX:1) = SPACE
               MOVE CGI-COOKIE(CGI-W-IDX:1)
                   TO WS-COOKIE-TOKEN(CGI-W-IDX2:1)
               ADD 1 TO CGI-W-IDX
               ADD 1 TO CGI-W-IDX2
           END-PERFORM
           .

       EMIT-LOGOUT.
      *>   HTMX requests get HX-Redirect; plain GET gets 302.
           ACCEPT CGI-W-IN FROM ENVIRONMENT "HTTP_HX_REQUEST"
               ON EXCEPTION
                   MOVE SPACES TO CGI-W-IN
           END-ACCEPT

           IF FUNCTION TRIM(CGI-W-IN(1:8)) = "true"
               DISPLAY "HX-Redirect: /login.html"
               DISPLAY "Set-Cookie: COBILL_SID=; Path=/; "
                       "Max-Age=0"
               DISPLAY "Content-Type: text/html; charset=utf-8"
               DISPLAY X"0A"
               DISPLAY "logged out"
           ELSE
               DISPLAY "Status: 302 Found"
               DISPLAY "Location: /login.html"
               DISPLAY "Set-Cookie: COBILL_SID=; Path=/; "
                       "Max-Age=0"
               DISPLAY "Content-Type: text/html; charset=utf-8"
               DISPLAY X"0A"
               DISPLAY "<a href='/login.html'>Logged out</a>"
           END-IF
           .

      *> Renderers for unauthenticated entry points.
       RENDER-LOGIN-NEEDED.
           DISPLAY "Status: 302 Found"
           DISPLAY "Location: /login.html"
           DISPLAY "Content-Type: text/html; charset=utf-8"
           DISPLAY X"0A"
           DISPLAY "<a href='/login.html'>Login</a>"
           .

       RENDER-LOGIN-FAILED.
           DISPLAY "Status: 401 Unauthorized"
           DISPLAY "Content-Type: text/html; charset=utf-8"
           DISPLAY X"0A"
           DISPLAY "<section class='panel'>"
           DISPLAY "  <h2>LOGIN FAILED</h2>"
           DISPLAY "  <p>Bad username or password.</p>"
           DISPLAY "  <a class='btn-primary' href='/login.html'>"
                   "[BACK]</a>"
           DISPLAY "</section>"
           .

       COPY "cgi-utils-procs.cpy".

       END PROGRAM AUTH.
