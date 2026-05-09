      *> Working storage for CGI parsing.
       01  CGI-VARS.
           05  CGI-METHOD          PIC X(8).
           05  CGI-CONTENT-LENGTH  PIC 9(6).
           05  CGI-QUERY-STRING    PIC X(2048).
           05  CGI-COOKIE          PIC X(512).
           05  CGI-RAW-INPUT       PIC X(8192).
           05  CGI-RAW-LEN         PIC 9(6).
           05  CGI-POST-BODY       PIC X(8192).
           05  CGI-PAIR-COUNT      PIC 99 VALUE 0.
           05  CGI-PAIRS OCCURS 30 TIMES.
               10  CGI-KEY         PIC X(40).
               10  CGI-VALUE       PIC X(500).

       01  CGI-WORK.
           05  CGI-W-CH            PIC X.
           05  CGI-W-IDX           PIC 9(5).
           05  CGI-W-IDX2          PIC 9(5).
           05  CGI-W-LEN           PIC 9(5).
           05  CGI-W-DEC-IDX       PIC 9(5).
           05  CGI-W-HEX           PIC XX.
           05  CGI-W-HEX-NUM       PIC 999.
           05  CGI-W-OUT           PIC X(500).
           05  CGI-W-OUT-LEN       PIC 9(5).
           05  CGI-W-IN            PIC X(500).
           05  CGI-W-FOUND         PIC X.
           05  CGI-W-PAIR-RAW      PIC X(540).
           05  CGI-W-EQ-POS        PIC 9(5).
           05  CGI-W-AMP-POS       PIC 9(5).

       01  CGI-LOOKUP.
           05  CGI-L-KEY           PIC X(40).
           05  CGI-L-VALUE         PIC X(500).
           05  CGI-L-FOUND         PIC X.

      *> HTML escape work area
       01  HTML-ESCAPE-WORK.
           05  HTML-IN             PIC X(500).
           05  HTML-IN-LEN         PIC 9(5).
           05  HTML-OUT            PIC X(2000).
           05  HTML-OUT-LEN        PIC 9(5).
           05  HTML-IDX            PIC 9(5).
           05  HTML-CH             PIC X.
