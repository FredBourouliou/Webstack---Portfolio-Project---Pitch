      *> Auth-check paragraphs. COPY this block in the PROCEDURE
      *> DIVISION of every program that includes the auth gate.
      *>
      *> Public entry points:
      *>   AUTH-CHECK            sets WS-AUTH-OK based on the cookie
      *>   AUTH-REDIRECT-LOGIN   emits a redirect to /login.html
      *>
      *> Internal helpers:
      *>   AUTH-PARSE-COOKIE     extracts COBILL_SID from CGI-COOKIE
      *>   AUTH-CHECK-EXPIRY    confirms today <= SES-EXPIRES

      *> AUTH-CHECK
      *>
      *> Parse the cookie header, look the token up in
      *> data/sessions.dat, check that the session is still active
      *> and not expired. Sets WS-AUTH-OK to "Y" on success.
      *> Any failure (no cookie, missing row, inactive, expired,
      *> file open error) leaves WS-AUTH-OK = "N".
       AUTH-CHECK.
           MOVE "N" TO WS-AUTH-OK
           MOVE SPACES TO WS-AUTH-TOKEN

           PERFORM AUTH-PARSE-COOKIE
      *>   No COBILL_SID in the Cookie header: nothing to look up.
           IF WS-AUTH-TOKEN = SPACES
               EXIT PARAGRAPH
           END-IF

           OPEN INPUT SESSION-FILE
      *>   ISAM file missing or unreadable: fail closed.
           IF WS-AUTH-FS-STATUS NOT = "00"
               EXIT PARAGRAPH
           END-IF

      *>   Indexed read by primary key.
           MOVE WS-AUTH-TOKEN TO SES-TOKEN
           READ SESSION-FILE
               INVALID KEY
      *>             Unknown token: stay "N", keep WS-AUTH-OK
      *>             untouched.
                   CONTINUE
               NOT INVALID KEY
                   IF SES-ACTIVE = "Y"
                       PERFORM AUTH-CHECK-EXPIRY
                   END-IF
           END-READ
           CLOSE SESSION-FILE
           .

      *> AUTH-CHECK-EXPIRY
      *>
      *> Build today's date as YYYY-MM-DD and compare it to the
      *> stored expiry (string compare works because both sides use
      *> the same ISO format). WS-AUTH-OK gets set to "Y" only when
      *> the session is still within its 24-hour window.
       AUTH-CHECK-EXPIRY.
           STRING FUNCTION CURRENT-DATE(1:4)  DELIMITED BY SIZE
                  "-"                         DELIMITED BY SIZE
                  FUNCTION CURRENT-DATE(5:2)  DELIMITED BY SIZE
                  "-"                         DELIMITED BY SIZE
                  FUNCTION CURRENT-DATE(7:2)  DELIMITED BY SIZE
               INTO WS-AUTH-TODAY
           IF SES-EXPIRES(1:10) >= WS-AUTH-TODAY
               MOVE "Y" TO WS-AUTH-OK
           END-IF
           .

      *> AUTH-PARSE-COOKIE
      *>
      *> Find "COBILL_SID=" inside the raw Cookie header and copy
      *> the 32 characters that follow into WS-AUTH-TOKEN. Stops at
      *> ";" or whitespace, which is how cookies are separated in a
      *> multi-cookie header.
       AUTH-PARSE-COOKIE.
      *>   INSPECT ... TALLYING ... BEFORE INITIAL counts characters
      *>   before the first occurrence of the pattern, giving us the
      *>   start offset of the cookie name.
           MOVE 0 TO WS-AUTH-IDX
           INSPECT CGI-COOKIE TALLYING WS-AUTH-IDX
               FOR CHARACTERS BEFORE INITIAL "COBILL_SID="
      *>   No match: TALLYING returns the full length, which is past
      *>   the buffer end. Bail out.
           IF WS-AUTH-IDX >= 511
               EXIT PARAGRAPH
           END-IF

      *>   Skip past "COBILL_SID=" (11 chars) plus the 1-based offset.
           ADD 12 TO WS-AUTH-IDX
           MOVE 1 TO WS-AUTH-IDX2
           PERFORM UNTIL WS-AUTH-IDX > 512
                      OR WS-AUTH-IDX2 > 32
                      OR CGI-COOKIE(WS-AUTH-IDX:1) = ";"
                      OR CGI-COOKIE(WS-AUTH-IDX:1) = SPACE
               MOVE CGI-COOKIE(WS-AUTH-IDX:1)
                   TO WS-AUTH-TOKEN(WS-AUTH-IDX2:1)
               ADD 1 TO WS-AUTH-IDX
               ADD 1 TO WS-AUTH-IDX2
           END-PERFORM
           .

      *> AUTH-REDIRECT-LOGIN
      *>
      *> Emit a redirect to the login page. HTMX cannot follow a
      *> plain 302 because the response would replace the swap
      *> target with the login page markup; instead, when the
      *> request comes from HTMX (HX-Request: true header), we
      *> reply with an HX-Redirect header that the HTMX client
      *> interprets as "do a full navigation". Non-HTMX requests
      *> get a regular 302.
       AUTH-REDIRECT-LOGIN.
           MOVE SPACES TO WS-AUTH-HX
           ACCEPT WS-AUTH-HX FROM ENVIRONMENT "HTTP_HX_REQUEST"
               ON EXCEPTION
                   MOVE SPACES TO WS-AUTH-HX
           END-ACCEPT
           IF FUNCTION TRIM(WS-AUTH-HX) = "true"
               DISPLAY "HX-Redirect: /login.html"
               DISPLAY "Content-Type: text/html; charset=utf-8"
               DISPLAY X"0A"
               DISPLAY "redirect"
           ELSE
               DISPLAY "Status: 302 Found"
               DISPLAY "Location: /login.html"
               DISPLAY "Content-Type: text/html; charset=utf-8"
               DISPLAY X"0A"
               DISPLAY "<a href='/login.html'>Login required</a>"
           END-IF
           .
