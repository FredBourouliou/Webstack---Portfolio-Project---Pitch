      *> Inline auth gate. COPY in MAIN-LOGIC after PARSE-CGI-INPUT.

           PERFORM AUTH-CHECK
           IF WS-AUTH-OK NOT = "Y"
               PERFORM AUTH-REDIRECT-LOGIN
               STOP RUN
           END-IF
