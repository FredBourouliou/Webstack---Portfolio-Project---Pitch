      *> Session record. Stored in data/sessions.dat (key = token).
       01  SESSION-RECORD.
           05  SES-TOKEN         PIC X(32).
           05  SES-USER          PIC X(30).
           05  SES-CREATED       PIC X(19).
           05  SES-EXPIRES       PIC X(19).
           05  SES-ACTIVE        PIC X.
