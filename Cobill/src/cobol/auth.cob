      *> auth.cob
      *>
      *> Authentication endpoint. Single-user "admin" account in
      *> v1; multi-user is planned for v1.2 (see docs/14-roadmap.md).
      *>
      *> Endpoint:   /cgi-bin/auth
      *> Method:     POST for login/logout (HTMX form submissions)
      *> Auth gate:  no (this binary IS the auth gate)
      *>
      *> Recognized actions (via the "action" form field):
      *>   login   -> validate credentials, create a session, set
      *>              the COBILL_SID cookie, redirect to /app.html.
      *>   logout  -> flip the matching session row inactive,
      *>              clear the cookie, redirect to /login.html.
      *>
      *> Credential storage:
      *>   - COBILL_AUTH_HASH (preferred): sha512crypt-format hash
      *>     ("$6$...") read from /etc/cobill/cobill.env via Apache
      *>     PassEnv. Verified by calling libc crypt(3) through FFI.
      *>   - COBILL_AUTH_PASS (fallback): plaintext password, used
      *>     only when no hash is configured. Intended for dev /
      *>     smoke tests.
      *>
      *> Sessions:
      *>   Stored in data/sessions.dat (ISAM, key = token). Token
      *>   format = YYYYMMDDhhmmss + "-" + 17 random digits,
      *>   truncated to 32 chars. Lifetime 24 hours. Cookie is
      *>   HttpOnly + SameSite=Lax + Path=/, so JavaScript on the
      *>   page cannot read it and cross-site requests do not
      *>   send it.
       IDENTIFICATION DIVISION.
       PROGRAM-ID. AUTH.

       ENVIRONMENT DIVISION.
       CONFIGURATION SECTION.
       COPY "special-names.cpy".

       INPUT-OUTPUT SECTION.
       FILE-CONTROL.
      *>     Session store. Indexed (B-tree) on SES-TOKEN, which is
      *>     the random 32-char value sent to the browser in the
      *>     COBILL_SID cookie.
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

      *> ISAM file status. "00" = success, "35" = file not found
      *> (handled specially in PERSIST-SESSION by creating it).
       01 WS-SES-STATUS    PIC XX.
      *> Action requested by the client (login | logout).
       01 WS-ACTION        PIC X(10) VALUE SPACES.

      *> Credentials submitted by the form.
       01 WS-SUBMITTED-USER PIC X(30).
       01 WS-SUBMITTED-PASS PIC X(60).

      *> Expected credentials. Username is hard-coded for v1 (single
      *> admin); password is loaded from the environment at runtime.
       01 WS-AUTH-USER     PIC X(30) VALUE "admin".
       01 WS-EXPECTED-PASS PIC X(60).
       01 WS-EXPECTED-HASH PIC X(128).
      *> Which credential format is in use: HASH (preferred,
      *> sha512crypt) or PLAIN (dev fallback).
       01 WS-AUTH-MODE     PIC X(8) VALUE "PLAIN".
      *> Verification result, set by VERIFY-PASSWORD.
       01 WS-AUTH-OK       PIC X VALUE "N".

      *> Buffers used to interop with libc crypt(3). C strings are
      *> null-terminated, so we pre-fill the buffer with LOW-VALUES
      *> (binary zero) and overwrite the leading bytes with the
      *> text. crypt(3) returns a pointer to a static buffer holding
      *> "$6$salt$hash" on success or NULL on failure.
       01 WS-PASS-CSTR     PIC X(64).
       01 WS-HASH-CSTR     PIC X(128).
       01 WS-CRYPT-RC      USAGE POINTER.
      *> BASED item used as a "view" of the memory crypt(3) returns.
      *> We point WS-RESULT-VIEW at the pointer with SET ADDRESS OF
      *> and then read it as a normal PIC X(128).
       01 WS-RESULT-VIEW   PIC X(128) BASED.
       01 WS-CMP-IDX       PIC 9(4).

      *> Session token built by GENERATE-TOKEN.
       01 WS-NEW-TOKEN     PIC X(32) VALUE SPACES.
       01 WS-RAND-A        PIC 9(10).
       01 WS-RAND-B        PIC 9(10).
       01 WS-DATE-PART     PIC X(14).

      *> Timestamps used to fill SES-CREATED / SES-EXPIRES.
       01 WS-NOW-FMT       PIC X(19).
       01 WS-EXPIRES-FMT   PIC X(19).
       01 WS-TODAY-INT     PIC S9(8).
       01 WS-TODAY-DATE    PIC 9(8).
       01 WS-TODAY-FMT     PIC X(10).
       01 WS-EXPIRES-INT   PIC S9(8).
       01 WS-EXPIRES-DATE  PIC 9(8).

      *> Token extracted from the COBILL_SID cookie during logout.
       01 WS-COOKIE-TOKEN  PIC X(32).

       PROCEDURE DIVISION.
       MAIN-LOGIC.
      *>   Read REQUEST_METHOD, QUERY_STRING, CONTENT_LENGTH and the
      *>   POST body, then split everything into key/value pairs.
           PERFORM READ-CGI-INPUT
           PERFORM PARSE-CGI-INPUT

      *>   Dispatch on the "action" form field.
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
      *>           Bare /cgi-bin/auth without action: bounce to the
      *>           login page.
                   PERFORM RENDER-LOGIN-NEEDED
           END-EVALUATE

           STOP RUN.

      *> ACTION-LOGIN
      *>
      *> Verify the submitted credentials against the configured
      *> expected credential (hash preferred, plaintext fallback).
      *> On success, create a fresh session, persist it, and reply
      *> with a 302 + Set-Cookie. On failure, return a 401 with a
      *> small "LOGIN FAILED" panel.
       ACTION-LOGIN.
           PERFORM PULL-CREDENTIALS
           PERFORM LOAD-EXPECTED-CREDENTIAL
           PERFORM VERIFY-PASSWORD

      *>   Username and password both have to match. Username is
      *>   compared after trimming spaces on both sides because PIC
      *>   X fields are space-padded.
           IF FUNCTION TRIM(WS-SUBMITTED-USER)
                  NOT = FUNCTION TRIM(WS-AUTH-USER)
                  OR WS-AUTH-OK NOT = "Y"
               PERFORM RENDER-LOGIN-FAILED
               EXIT PARAGRAPH
           END-IF

      *>   Credentials OK: open a session.
           PERFORM GENERATE-TOKEN
           PERFORM COMPUTE-EXPIRY
           PERFORM PERSIST-SESSION
           PERFORM EMIT-LOGIN-SUCCESS
           .

      *> PULL-CREDENTIALS
      *>
      *> Copy the submitted "username" and "password" form fields
      *> into the WS-SUBMITTED-USER / WS-SUBMITTED-PASS buffers.
      *> Fields absent from the form leave the buffer at SPACES,
      *> which can never match a non-blank expected credential.
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

      *> LOAD-EXPECTED-CREDENTIAL
      *>
      *> Decide whether we are running in HASH or PLAIN mode.
      *>
      *> HASH mode: COBILL_AUTH_HASH must be set and start with "$"
      *> (sha512crypt hashes look like "$6$salt$hash"). This is the
      *> production path.
      *>
      *> PLAIN mode: COBILL_AUTH_PASS read as plaintext. If it is
      *> absent, fall back to the demo password "cobill". Intended
      *> for dev and the smoke test only.
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

      *> VERIFY-PASSWORD
      *>
      *> Sets WS-AUTH-OK to "Y" if the submitted password matches
      *> the expected credential, "N" otherwise.
      *>
      *> PLAIN mode: trim both sides and string-compare. Trivial.
      *>
      *> HASH mode: copy the submitted password and the stored
      *> hash into null-terminated buffers (libc strings end at
      *> the first NUL byte), call libc crypt(3) with the password
      *> and the stored hash. crypt(3) reuses the salt from the
      *> stored hash and returns a freshly computed hash. If the
      *> two hashes match byte-for-byte (up to the terminating
      *> NUL), the password is correct.
      *>
      *> The Makefile builds with -fstatic-call so GnuCOBOL emits
      *> a direct C call to the crypt symbol; without that flag,
      *> COBOL would try to dlopen a module named "crypt" and fail
      *> at runtime.
       VERIFY-PASSWORD.
           MOVE "N" TO WS-AUTH-OK

      *>   Plaintext path (dev / smoke-test only).
           IF WS-AUTH-MODE = "PLAIN"
               IF FUNCTION TRIM(WS-SUBMITTED-PASS)
                      = FUNCTION TRIM(WS-EXPECTED-PASS)
                   MOVE "Y" TO WS-AUTH-OK
               END-IF
               EXIT PARAGRAPH
           END-IF

      *>   Empty password never matches a hash. Bail out before
      *>   the FFI call to avoid calling crypt(3) with garbage.
           IF FUNCTION TRIM(WS-SUBMITTED-PASS) = SPACES
               EXIT PARAGRAPH
           END-IF

      *>   Build the null-terminated password C string by writing
      *>   the trimmed password followed by X"00" into a buffer
      *>   pre-filled with LOW-VALUES (so anything after the NUL is
      *>   already zero).
           MOVE LOW-VALUES TO WS-PASS-CSTR
           STRING FUNCTION TRIM(WS-SUBMITTED-PASS) DELIMITED BY SIZE
                  X"00"                            DELIMITED BY SIZE
               INTO WS-PASS-CSTR
           END-STRING

      *>   Same dance for the expected hash. crypt(3) reads the
      *>   "$id$salt$" prefix from this buffer to pick the algo
      *>   and the salt; everything past the second "$" is the
      *>   actual hash.
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

      *>   Library refused to compute a hash (unknown algo, malformed
      *>   salt, ...): treat as auth failure.
           IF WS-CRYPT-RC = NULL
               EXIT PARAGRAPH
           END-IF

      *>   Point WS-RESULT-VIEW at the static buffer crypt(3)
      *>   returned, then compare byte-by-byte against the stored
      *>   hash until both strings null-terminate. Any mismatch
      *>   before the NUL drops WS-AUTH-OK back to "N".
      *>   Note: a constant-time compare would be slightly stronger
      *>   against timing attacks, but the auth endpoint is rate-
      *>   limited at the network layer (single user, no public
      *>   sign-up).
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

      *> GENERATE-TOKEN
      *>
      *> Build a session token of the form
      *>   YYYYMMDDhhmmss-AAAAAAAAAA-BBBBBBBBBB
      *> where the date part guarantees uniqueness across calendar
      *> seconds and the two 10-digit random parts give 10^20
      *> possibilities per second. The whole thing gets truncated
      *> to 32 characters by the PIC X(32) destination.
      *>
      *> FUNCTION RANDOM is seeded with SECONDS-PAST-MIDNIGHT on
      *> the first call so it is non-deterministic between requests.
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

      *> COMPUTE-EXPIRY
      *>
      *> Build WS-NOW-FMT     = "YYYY-MM-DD hh:mm:ss"  (issued at)
      *>       WS-EXPIRES-FMT = "YYYY-MM-DD 00:00:00"  (next day,
      *>                                                midnight)
      *>
      *> The expiry uses INTEGER-OF-DATE / DATE-OF-INTEGER to add
      *> one day cleanly across month and year boundaries. Strings
      *> are kept in ISO format because that lets us compare them
      *> lexicographically (see AUTH-CHECK-EXPIRY in auth-check).
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

      *>   Expiry = today + 1 day, midnight. INTEGER-OF-DATE
      *>   converts YYYYMMDD into a day count since 1601, we add
      *>   one, then convert back.
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

      *> PERSIST-SESSION
      *>
      *> Write the freshly built session record into
      *> data/sessions.dat. The first time auth.cob runs on a
      *> brand-new install the file does not exist yet, so file
      *> status "35" comes back from OPEN I-O; in that case we
      *> recover by opening in OUTPUT mode (which creates the
      *> file) and re-opening I-O.
       PERSIST-SESSION.
           OPEN I-O SESSION-FILE
           IF WS-SES-STATUS = "35"
      *>       File does not exist yet: create it.
               OPEN OUTPUT SESSION-FILE
               CLOSE SESSION-FILE
               OPEN I-O SESSION-FILE
           END-IF

           MOVE WS-NEW-TOKEN  TO SES-TOKEN
           MOVE WS-AUTH-USER  TO SES-USER
           MOVE WS-NOW-FMT    TO SES-CREATED
           MOVE WS-EXPIRES-FMT TO SES-EXPIRES
           MOVE "Y"           TO SES-ACTIVE

      *>   INVALID KEY would mean a token collision; impossible in
      *>   practice given the random component, so we just CONTINUE.
           WRITE SESSION-RECORD
               INVALID KEY
                   CONTINUE
               NOT INVALID KEY
                   CONTINUE
           END-WRITE

           CLOSE SESSION-FILE
           .

      *> EMIT-LOGIN-SUCCESS
      *>
      *> Reply with a 302 redirect to /app.html along with the
      *> Set-Cookie header. Cookie flags:
      *>   HttpOnly       -> JS on the page cannot read it
      *>   Max-Age=86400  -> 24 hours
      *>   SameSite=Lax   -> not sent on cross-site requests
      *>                    except top-level navigations
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

      *> ACTION-LOGOUT
      *>
      *> Mark the matching session row inactive (soft revocation
      *> rather than DELETE: we keep the row for audit), then
      *> clear the cookie and redirect to /login.html.
      *>
      *> If no COBILL_SID cookie reaches us, we still emit the
      *> redirect; the user gets logged out client-side anyway.
       ACTION-LOGOUT.
           MOVE SPACES TO WS-COOKIE-TOKEN
           PERFORM EXTRACT-COOKIE-TOKEN

           IF FUNCTION TRIM(WS-COOKIE-TOKEN) NOT = SPACES
               OPEN I-O SESSION-FILE
               IF WS-SES-STATUS = "00"
                   MOVE WS-COOKIE-TOKEN TO SES-TOKEN
                   READ SESSION-FILE
                       INVALID KEY
      *>                   Unknown token: nothing to revoke.
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

      *> EXTRACT-COOKIE-TOKEN
      *>
      *> Same algorithm as AUTH-PARSE-COOKIE in auth-check, but
      *> writes into WS-COOKIE-TOKEN (auth.cob's own variable)
      *> instead of WS-AUTH-TOKEN. Kept separate so the auth gate
      *> remains a drop-in copybook that does not collide with
      *> the host program's namespace.
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

      *> EMIT-LOGOUT
      *>
      *> Clears the cookie (Max-Age=0 tells the browser to drop it
      *> immediately) and sends the user to /login.html.
      *>
      *> HTMX requests cannot follow a regular 302 cleanly (the
      *> swap target would receive the login page markup as a
      *> fragment), so when HX-Request: true is set, we reply with
      *> the HTMX-specific HX-Redirect header instead. Plain
      *> browser navigations get a normal 302.
       EMIT-LOGOUT.
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

      *> Renderers for the failure paths.

      *> Triggered by an action other than login/logout (or no
      *> action at all). Sends the user to the login page.
       RENDER-LOGIN-NEEDED.
           DISPLAY "Status: 302 Found"
           DISPLAY "Location: /login.html"
           DISPLAY "Content-Type: text/html; charset=utf-8"
           DISPLAY X"0A"
           DISPLAY "<a href='/login.html'>Login</a>"
           .

      *> Triggered when the username or password did not match.
      *> Replies 401 with a small panel that HTMX swaps into the
      *> login form's error slot. No information disclosure: the
      *> message does not say whether it was the user or the pass
      *> that was wrong.
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

      *> Shared CGI helpers (READ-CGI-INPUT, PARSE-CGI-INPUT,
      *> URL-DECODE, HTML-ESCAPE, FIND-FIELD, EMIT-HTML-HEADERS).
       COPY "cgi-utils-procs.cpy".

       END PROGRAM AUTH.
