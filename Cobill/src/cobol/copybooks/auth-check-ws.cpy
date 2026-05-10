      *> Auth-check working storage.
      *>
      *> COPY this block in the WORKING-STORAGE SECTION of every
      *> program that includes the auth gate (auth-check.cpy).

      *> ISAM file status code returned by OPEN/READ/CLOSE on the
      *> session file. "00" means success, anything else is an error.
       01  WS-AUTH-FS-STATUS  PIC XX.

      *> Result of the auth check: "Y" if the session is valid and
      *> still active, "N" otherwise. Tested by auth-check.cpy.
       01  WS-AUTH-OK         PIC X     VALUE "N".

      *> Session token extracted from the COBILL_SID cookie. 32 hex
      *> digits.
       01  WS-AUTH-TOKEN      PIC X(32) VALUE SPACES.

      *> Loop counters used while parsing the cookie string.
       01  WS-AUTH-IDX        PIC 9(5)  VALUE 0.
       01  WS-AUTH-IDX2       PIC 9(2)  VALUE 0.

      *> HX-Request header value. "true" when the request is issued
      *> by HTMX, in which case we reply with HX-Redirect instead of
      *> a plain 302.
       01  WS-AUTH-HX         PIC X(8)  VALUE SPACES.

      *> Today's date in ISO format (YYYY-MM-DD), used to compare
      *> against the session expiry.
       01  WS-AUTH-TODAY      PIC X(10).
