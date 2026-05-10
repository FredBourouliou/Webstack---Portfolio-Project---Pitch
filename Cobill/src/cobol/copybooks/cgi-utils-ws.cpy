      *> Working-storage shared by every CGI program. Holds the
      *> raw request (env vars + body), the parsed key/value pairs,
      *> the helper buffers used by URL-DECODE / HTML-ESCAPE, and
      *> the FIND-FIELD lookup slot.
      *>
      *> The parsing procedures themselves live in
      *> cgi-utils-procs.cpy.

      *> Request snapshot.
       01  CGI-VARS.
      *>     "GET" or "POST". Read from REQUEST_METHOD.
           05  CGI-METHOD          PIC X(8).
      *>     Body length declared by Apache. Used to size the
      *>     stdin read in READ-CGI-INPUT.
           05  CGI-CONTENT-LENGTH  PIC 9(6).
      *>     Raw query string (the part after "?" in the URL).
           05  CGI-QUERY-STRING    PIC X(2048).
      *>     Raw Cookie header. Parsed by AUTH-PARSE-COOKIE to
      *>     extract COBILL_SID.
           05  CGI-COOKIE          PIC X(512).
      *>     Concatenation of QUERY_STRING and POST body. This is
      *>     what PARSE-CGI-INPUT works on, so a GET parameter and
      *>     a POST field are addressable through the same lookup.
           05  CGI-RAW-INPUT       PIC X(8192).
      *>     Useful length inside CGI-RAW-INPUT.
           05  CGI-RAW-LEN         PIC 9(6).
      *>     Verbatim POST body as read from stdin.
           05  CGI-POST-BODY       PIC X(8192).

      *>     How many key/value pairs were parsed.
           05  CGI-PAIR-COUNT      PIC 99 VALUE 0.
      *>     Parsed pairs. Capped at 30, which is enough for the
      *>     widest form in the app (an invoice creation form with
      *>     10 line items times three fields per line).
           05  CGI-PAIRS OCCURS 30 TIMES.
               10  CGI-KEY         PIC X(40).
               10  CGI-VALUE       PIC X(500).

      *> Scratch area used by the URL-decoder, the HTML-escaper and
      *> the field-lookup helper. Not safe to use across calls of
      *> different procedures.
       01  CGI-WORK.
           05  CGI-W-CH            PIC X.
           05  CGI-W-IDX           PIC 9(5).
           05  CGI-W-IDX2          PIC 9(5).
           05  CGI-W-LEN           PIC 9(5).
      *>     Separate index used inside URL-DECODE so callers can
      *>     keep CGI-W-IDX across calls without it being clobbered.
           05  CGI-W-DEC-IDX       PIC 9(5).
      *>     Two hex digits captured after a "%" escape.
           05  CGI-W-HEX           PIC XX.
      *>     Decoded numeric value of CGI-W-HEX (0..255).
           05  CGI-W-HEX-NUM       PIC 999.
      *>     URL-decoded result and its length.
           05  CGI-W-OUT           PIC X(500).
           05  CGI-W-OUT-LEN       PIC 9(5).
      *>     URL-decoder input.
           05  CGI-W-IN            PIC X(500).
           05  CGI-W-FOUND         PIC X.
           05  CGI-W-PAIR-RAW      PIC X(540).
           05  CGI-W-EQ-POS        PIC 9(5).
           05  CGI-W-AMP-POS       PIC 9(5).

      *> FIND-FIELD lookup slot. Callers fill CGI-L-KEY, PERFORM
      *> FIND-FIELD, then read CGI-L-VALUE/CGI-L-FOUND.
       01  CGI-LOOKUP.
           05  CGI-L-KEY           PIC X(40).
           05  CGI-L-VALUE         PIC X(500).
           05  CGI-L-FOUND         PIC X.

      *> HTML-ESCAPE work area. Anyone emitting user-controlled
      *> text inside an HTML document MOVEs the value into
      *> HTML-IN, PERFORMs HTML-ESCAPE, then reads HTML-OUT for
      *> the first HTML-OUT-LEN characters.
       01  HTML-ESCAPE-WORK.
           05  HTML-IN             PIC X(500).
           05  HTML-IN-LEN         PIC 9(5).
           05  HTML-OUT            PIC X(2000).
           05  HTML-OUT-LEN        PIC 9(5).
           05  HTML-IDX            PIC 9(5).
           05  HTML-CH             PIC X.
