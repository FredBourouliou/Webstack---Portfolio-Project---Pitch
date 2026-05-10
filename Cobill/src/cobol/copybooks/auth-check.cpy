      *> Inline auth gate.
      *>
      *> COPY this block in MAIN-LOGIC right after PARSE-CGI-INPUT.
      *> It performs AUTH-CHECK (which inspects the COBILL_SID cookie
      *> and looks the session up in data/sessions.dat). When the
      *> session is missing, expired, or inactive, the program emits
      *> a redirect to /login.html and stops. Otherwise execution
      *> continues normally.
      *>
      *> AUTH-CHECK sets WS-AUTH-OK to "Y" on success, "N" otherwise.
      *> See auth-check-ws.cpy for the working-storage block and
      *> auth-check-procs.cpy for the AUTH-CHECK / AUTH-REDIRECT-LOGIN
      *> implementations.

           PERFORM AUTH-CHECK
           IF WS-AUTH-OK NOT = "Y"
               PERFORM AUTH-REDIRECT-LOGIN
               STOP RUN
           END-IF
