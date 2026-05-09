      *> Auth-check working storage.
       01  WS-AUTH-FS-STATUS  PIC XX.
       01  WS-AUTH-OK         PIC X     VALUE "N".
       01  WS-AUTH-TOKEN      PIC X(32) VALUE SPACES.
       01  WS-AUTH-IDX        PIC 9(5)  VALUE 0.
       01  WS-AUTH-IDX2       PIC 9(2)  VALUE 0.
       01  WS-AUTH-HX         PIC X(8)  VALUE SPACES.
       01  WS-AUTH-TODAY      PIC X(10).
