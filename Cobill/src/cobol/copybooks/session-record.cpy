      *> Session record layout. Stored in data/sessions.dat, an
      *> ISAM file keyed on SES-TOKEN.
      *>
      *> A session row is created at login (auth.cob ACTION-LOGIN)
      *> and looked up on every authenticated request through the
      *> auth gate (auth-check.cpy). Logout flips SES-ACTIVE to "N";
      *> the row is kept for audit instead of being deleted.
       01  SESSION-RECORD.

      *>     32 hex digits. Random token sent to the browser as the
      *>     COBILL_SID cookie. Primary key of the file.
           05  SES-TOKEN         PIC X(32).

      *>     The authenticated username. Always "admin" in v1 (single
      *>     user). Reserved for the multi-user roadmap.
           05  SES-USER          PIC X(30).

      *>     ISO timestamp YYYY-MM-DD HH:MM:SS. Set at login.
           05  SES-CREATED       PIC X(19).

      *>     ISO timestamp marking when the session stops being
      *>     accepted. Currently login + 24 hours.
           05  SES-EXPIRES       PIC X(19).

      *>     "Y" while the session is usable, "N" after logout or
      *>     after auth.cob revokes it.
           05  SES-ACTIVE        PIC X.
