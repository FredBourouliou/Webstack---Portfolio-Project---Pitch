      *> Auth-check paragraphs. COPY in PROCEDURE DIVISION.

       AUTH-CHECK.
           MOVE "N" TO WS-AUTH-OK
           MOVE SPACES TO WS-AUTH-TOKEN

           PERFORM AUTH-PARSE-COOKIE
           IF WS-AUTH-TOKEN = SPACES
               EXIT PARAGRAPH
           END-IF

           OPEN INPUT SESSION-FILE
           IF WS-AUTH-FS-STATUS NOT = "00"
               EXIT PARAGRAPH
           END-IF

           MOVE WS-AUTH-TOKEN TO SES-TOKEN
           READ SESSION-FILE
               INVALID KEY
                   CONTINUE
               NOT INVALID KEY
                   IF SES-ACTIVE = "Y"
                       PERFORM AUTH-CHECK-EXPIRY
                   END-IF
           END-READ
           CLOSE SESSION-FILE
           .

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

       AUTH-PARSE-COOKIE.
           MOVE 0 TO WS-AUTH-IDX
           INSPECT CGI-COOKIE TALLYING WS-AUTH-IDX
               FOR CHARACTERS BEFORE INITIAL "COBILL_SID="
           IF WS-AUTH-IDX >= 511
               EXIT PARAGRAPH
           END-IF

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
