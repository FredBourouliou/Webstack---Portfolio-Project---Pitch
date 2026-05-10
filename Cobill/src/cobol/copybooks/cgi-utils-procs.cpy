      *> CGI parsing procedures. COPY this block in the PROCEDURE
      *> DIVISION of every CGI program.
      *>
      *> Standard call sequence at the start of MAIN-LOGIC:
      *>   PERFORM READ-CGI-INPUT     -- read env vars + POST body
      *>   PERFORM PARSE-CGI-INPUT    -- split into key/value pairs
      *>   (optional)
      *>   COPY "auth-check.cpy"      -- gate non-public endpoints
      *>
      *> Then to read a form field:
      *>   MOVE "client_id" TO CGI-L-KEY
      *>   PERFORM FIND-FIELD
      *>   IF CGI-L-FOUND = "Y" ... CGI-L-VALUE has the URL-decoded
      *>                            value, trimmed implicitly.
      *>
      *> To emit user-controlled text inside HTML safely:
      *>   MOVE some-value TO HTML-IN
      *>   PERFORM HTML-ESCAPE
      *>   DISPLAY HTML-OUT(1:HTML-OUT-LEN)

      *> READ-CGI-INPUT
      *>
      *> Pull REQUEST_METHOD, QUERY_STRING and HTTP_COOKIE from the
      *> environment, then for POST requests, read CONTENT_LENGTH
      *> bytes from stdin and append them to the query string so a
      *> single buffer (CGI-RAW-INPUT) holds both GET and POST data.
      *> Form fields are looked up in that combined buffer.
       READ-CGI-INPUT.
           MOVE SPACES TO CGI-METHOD
           MOVE SPACES TO CGI-QUERY-STRING
           MOVE SPACES TO CGI-COOKIE
           MOVE SPACES TO CGI-RAW-INPUT
           MOVE 0      TO CGI-CONTENT-LENGTH
           MOVE 0      TO CGI-RAW-LEN
           MOVE 0      TO CGI-W-LEN

      *>   ACCEPT ... FROM ENVIRONMENT pulls a CGI environment
      *>   variable as set by Apache mod_cgi.
           ACCEPT CGI-METHOD       FROM ENVIRONMENT "REQUEST_METHOD"
           ACCEPT CGI-QUERY-STRING FROM ENVIRONMENT "QUERY_STRING"
           ACCEPT CGI-COOKIE       FROM ENVIRONMENT "HTTP_COOKIE"

      *>   INSPECT ... TALLYING gives us the length of the query
      *>   string by counting characters up to the first space (the
      *>   space-padded tail of the PIC X buffer).
           INSPECT CGI-QUERY-STRING TALLYING CGI-W-LEN
               FOR CHARACTERS BEFORE INITIAL SPACE

      *>   Seed CGI-RAW-INPUT with the query string so that a POST
      *>   request with parameters in its URL (e.g. POST
      *>   /cgi-bin/foo?action=create) still exposes "action" via
      *>   FIND-FIELD.
           IF CGI-W-LEN > 0
               MOVE CGI-QUERY-STRING(1:CGI-W-LEN)
                   TO CGI-RAW-INPUT
               MOVE CGI-W-LEN TO CGI-RAW-LEN
           END-IF

      *>   For POST, read CONTENT_LENGTH bytes from stdin and
      *>   append them after the existing query string, separated
      *>   by an "&" so they parse as additional key=value pairs.
           IF CGI-METHOD = "POST"
               ACCEPT CGI-CONTENT-LENGTH
                  FROM ENVIRONMENT "CONTENT_LENGTH"
                  ON EXCEPTION
                      MOVE 0 TO CGI-CONTENT-LENGTH
               END-ACCEPT
               IF CGI-CONTENT-LENGTH > 0
                   IF CGI-RAW-LEN > 0
                       MOVE "&" TO CGI-RAW-INPUT(CGI-RAW-LEN + 1:1)
                       ADD 1 TO CGI-RAW-LEN
                   END-IF
                   MOVE SPACES TO CGI-POST-BODY
                   ACCEPT CGI-POST-BODY FROM STDIN
                   MOVE CGI-POST-BODY(1:CGI-CONTENT-LENGTH)
                       TO CGI-RAW-INPUT(CGI-RAW-LEN + 1:
                                        CGI-CONTENT-LENGTH)
                   ADD CGI-CONTENT-LENGTH TO CGI-RAW-LEN
               END-IF
           END-IF
           .

      *> PARSE-CGI-INPUT
      *>
      *> Walk CGI-RAW-INPUT and split it into up to 30 key/value
      *> pairs on the "&" separator. Each pair is then handed to
      *> SPLIT-AND-DECODE-PAIR for the "=" split and URL-decoding.
       PARSE-CGI-INPUT.
           MOVE 0 TO CGI-PAIR-COUNT
           IF CGI-RAW-LEN = 0
               EXIT PARAGRAPH
           END-IF
           MOVE 1 TO CGI-W-IDX
           MOVE 1 TO CGI-W-IDX2
           PERFORM UNTIL CGI-W-IDX > CGI-RAW-LEN
                      OR CGI-PAIR-COUNT >= 30
      *>       Reset the per-pair buffer, then copy characters
      *>       until "&" or end of input.
               MOVE SPACES TO CGI-W-PAIR-RAW
               MOVE 1 TO CGI-W-IDX2
               PERFORM UNTIL CGI-W-IDX > CGI-RAW-LEN
                          OR CGI-RAW-INPUT(CGI-W-IDX:1) = "&"
                   MOVE CGI-RAW-INPUT(CGI-W-IDX:1)
                       TO CGI-W-PAIR-RAW(CGI-W-IDX2:1)
                   ADD 1 TO CGI-W-IDX
                   ADD 1 TO CGI-W-IDX2
               END-PERFORM
      *>       Skip the "&" itself.
               IF CGI-W-IDX <= CGI-RAW-LEN
                   ADD 1 TO CGI-W-IDX
               END-IF
      *>       Empty pair? Skip it. Otherwise commit a slot.
               IF CGI-W-IDX2 > 1
                   ADD 1 TO CGI-PAIR-COUNT
                   PERFORM SPLIT-AND-DECODE-PAIR
               END-IF
           END-PERFORM
           .

      *> SPLIT-AND-DECODE-PAIR
      *>
      *> Given a "key=value" pair captured in CGI-W-PAIR-RAW,
      *> locate the "=" sign, store the key untouched (form field
      *> names never need URL-decoding in practice) and run
      *> URL-DECODE on the value before storing it.
       SPLIT-AND-DECODE-PAIR.
           MOVE 0 TO CGI-W-EQ-POS
           PERFORM VARYING CGI-W-LEN FROM 1 BY 1
                   UNTIL CGI-W-LEN > 540
                      OR CGI-W-PAIR-RAW(CGI-W-LEN:1) = "="
                      OR CGI-W-PAIR-RAW(CGI-W-LEN:1) = SPACE
               CONTINUE
           END-PERFORM
           IF CGI-W-PAIR-RAW(CGI-W-LEN:1) = "="
               MOVE CGI-W-LEN TO CGI-W-EQ-POS
           END-IF

      *>   No "=" found: store the whole pair as key, value blank.
      *>   This is how a bare flag like "?debug" comes in.
           IF CGI-W-EQ-POS = 0
               MOVE CGI-W-PAIR-RAW(1:40)
                   TO CGI-KEY(CGI-PAIR-COUNT)
               MOVE SPACES TO CGI-VALUE(CGI-PAIR-COUNT)
           ELSE
               MOVE CGI-W-PAIR-RAW(1:CGI-W-EQ-POS - 1)
                   TO CGI-KEY(CGI-PAIR-COUNT)
               MOVE SPACES TO CGI-W-IN
               MOVE CGI-W-PAIR-RAW(CGI-W-EQ-POS + 1:500)
                   TO CGI-W-IN
               PERFORM URL-DECODE
               MOVE CGI-W-OUT TO CGI-VALUE(CGI-PAIR-COUNT)
           END-IF
           .

      *> URL-DECODE
      *>
      *> Decode CGI-W-IN into CGI-W-OUT. Handles "+" -> space,
      *> "%XX" -> the byte with hex value XX, and copies anything
      *> else through unchanged. Stops on the first SPACE, which
      *> marks the end of the URL-encoded value (PIC X strings are
      *> space-padded).
      *>
      *> Uses CGI-W-DEC-IDX as a private cursor so callers can
      *> safely keep CGI-W-IDX across calls.
       URL-DECODE.
           MOVE SPACES TO CGI-W-OUT
           MOVE 1 TO CGI-W-DEC-IDX
           MOVE 1 TO CGI-W-OUT-LEN
           PERFORM UNTIL CGI-W-DEC-IDX > 500
               MOVE CGI-W-IN(CGI-W-DEC-IDX:1) TO CGI-W-CH
               EVALUATE CGI-W-CH
                   WHEN SPACE
      *>               End of value: jump past the loop bound.
                       MOVE 501 TO CGI-W-DEC-IDX
                   WHEN "+"
      *>               "+" is the legacy URL encoding for SPACE.
                       MOVE " " TO CGI-W-OUT(CGI-W-OUT-LEN:1)
                       ADD 1 TO CGI-W-OUT-LEN
                       ADD 1 TO CGI-W-DEC-IDX
                   WHEN "%"
      *>               Percent escape: next two characters are
      *>               hex digits forming a byte (0..255).
                       IF CGI-W-DEC-IDX + 2 <= 500
                           MOVE CGI-W-IN(CGI-W-DEC-IDX + 1:2)
                               TO CGI-W-HEX
                           PERFORM HEX-TO-CHAR
      *>                   CHAR(n) returns the character whose
      *>                   ordinal is n. COBOL ordinals are 1-based,
      *>                   so byte 0x41 ('A', ASCII 65) is CHAR(66).
                           MOVE FUNCTION CHAR(CGI-W-HEX-NUM + 1)
                               TO CGI-W-OUT(CGI-W-OUT-LEN:1)
                           ADD 1 TO CGI-W-OUT-LEN
                           ADD 3 TO CGI-W-DEC-IDX
                       ELSE
                           ADD 1 TO CGI-W-DEC-IDX
                       END-IF
                   WHEN OTHER
      *>               Plain character: copy through.
                       MOVE CGI-W-CH TO CGI-W-OUT(CGI-W-OUT-LEN:1)
                       ADD 1 TO CGI-W-OUT-LEN
                       ADD 1 TO CGI-W-DEC-IDX
               END-EVALUATE
      *>       Output buffer full: stop here to avoid overflow.
               IF CGI-W-OUT-LEN > 500
                   MOVE 501 TO CGI-W-DEC-IDX
               END-IF
           END-PERFORM
      *>   CGI-W-OUT-LEN was post-incremented after the last write,
      *>   so subtract 1 to get the actual length.
           SUBTRACT 1 FROM CGI-W-OUT-LEN
           .

      *> HEX-TO-CHAR
      *>
      *> Convert the two hex digits in CGI-W-HEX into the integer
      *> CGI-W-HEX-NUM. Lookup tables (HEX-DIGIT-1 / HEX-DIGIT-2)
      *> rather than arithmetic on ASCII codes, because COBOL does
      *> not give us a clean way to subtract char codes.
       HEX-TO-CHAR.
           MOVE 0 TO CGI-W-HEX-NUM
           PERFORM HEX-DIGIT-1
           MULTIPLY 16 BY CGI-W-HEX-NUM
           PERFORM HEX-DIGIT-2
           .

      *> HEX-DIGIT-1
      *>
      *> Set CGI-W-HEX-NUM to the numeric value of the first hex
      *> digit (CGI-W-HEX(1:1)). Both upper- and lower-case letters
      *> are accepted (e.g. %2F and %2f decode the same). Anything
      *> else is treated as 0.
       HEX-DIGIT-1.
           EVALUATE CGI-W-HEX(1:1)
               WHEN "0" MOVE  0 TO CGI-W-HEX-NUM
               WHEN "1" MOVE  1 TO CGI-W-HEX-NUM
               WHEN "2" MOVE  2 TO CGI-W-HEX-NUM
               WHEN "3" MOVE  3 TO CGI-W-HEX-NUM
               WHEN "4" MOVE  4 TO CGI-W-HEX-NUM
               WHEN "5" MOVE  5 TO CGI-W-HEX-NUM
               WHEN "6" MOVE  6 TO CGI-W-HEX-NUM
               WHEN "7" MOVE  7 TO CGI-W-HEX-NUM
               WHEN "8" MOVE  8 TO CGI-W-HEX-NUM
               WHEN "9" MOVE  9 TO CGI-W-HEX-NUM
               WHEN "A" MOVE 10 TO CGI-W-HEX-NUM
               WHEN "B" MOVE 11 TO CGI-W-HEX-NUM
               WHEN "C" MOVE 12 TO CGI-W-HEX-NUM
               WHEN "D" MOVE 13 TO CGI-W-HEX-NUM
               WHEN "E" MOVE 14 TO CGI-W-HEX-NUM
               WHEN "F" MOVE 15 TO CGI-W-HEX-NUM
               WHEN "a" MOVE 10 TO CGI-W-HEX-NUM
               WHEN "b" MOVE 11 TO CGI-W-HEX-NUM
               WHEN "c" MOVE 12 TO CGI-W-HEX-NUM
               WHEN "d" MOVE 13 TO CGI-W-HEX-NUM
               WHEN "e" MOVE 14 TO CGI-W-HEX-NUM
               WHEN "f" MOVE 15 TO CGI-W-HEX-NUM
               WHEN OTHER MOVE 0 TO CGI-W-HEX-NUM
           END-EVALUATE
           .

      *> HEX-DIGIT-2
      *>
      *> Add the numeric value of the second hex digit
      *> (CGI-W-HEX(2:1)) to CGI-W-HEX-NUM. Called after
      *> HEX-DIGIT-1 has already multiplied the first digit by 16,
      *> so the sum is the final byte value.
       HEX-DIGIT-2.
           EVALUATE CGI-W-HEX(2:1)
               WHEN "0" ADD  0 TO CGI-W-HEX-NUM
               WHEN "1" ADD  1 TO CGI-W-HEX-NUM
               WHEN "2" ADD  2 TO CGI-W-HEX-NUM
               WHEN "3" ADD  3 TO CGI-W-HEX-NUM
               WHEN "4" ADD  4 TO CGI-W-HEX-NUM
               WHEN "5" ADD  5 TO CGI-W-HEX-NUM
               WHEN "6" ADD  6 TO CGI-W-HEX-NUM
               WHEN "7" ADD  7 TO CGI-W-HEX-NUM
               WHEN "8" ADD  8 TO CGI-W-HEX-NUM
               WHEN "9" ADD  9 TO CGI-W-HEX-NUM
               WHEN "A" ADD 10 TO CGI-W-HEX-NUM
               WHEN "B" ADD 11 TO CGI-W-HEX-NUM
               WHEN "C" ADD 12 TO CGI-W-HEX-NUM
               WHEN "D" ADD 13 TO CGI-W-HEX-NUM
               WHEN "E" ADD 14 TO CGI-W-HEX-NUM
               WHEN "F" ADD 15 TO CGI-W-HEX-NUM
               WHEN "a" ADD 10 TO CGI-W-HEX-NUM
               WHEN "b" ADD 11 TO CGI-W-HEX-NUM
               WHEN "c" ADD 12 TO CGI-W-HEX-NUM
               WHEN "d" ADD 13 TO CGI-W-HEX-NUM
               WHEN "e" ADD 14 TO CGI-W-HEX-NUM
               WHEN "f" ADD 15 TO CGI-W-HEX-NUM
               WHEN OTHER ADD 0 TO CGI-W-HEX-NUM
           END-EVALUATE
           .

      *> FIND-FIELD
      *>
      *> Linear scan through the parsed CGI-PAIRS table looking
      *> for the key currently in CGI-L-KEY. On match, sets
      *> CGI-L-VALUE and CGI-L-FOUND = "Y". If no pair matches,
      *> CGI-L-VALUE is blank and CGI-L-FOUND = "N".
      *>
      *> The list is small (capped at 30) so a linear scan beats
      *> the overhead of building an index.
       FIND-FIELD.
           MOVE "N"    TO CGI-L-FOUND
           MOVE SPACES TO CGI-L-VALUE
           PERFORM VARYING CGI-W-IDX FROM 1 BY 1
                   UNTIL CGI-W-IDX > CGI-PAIR-COUNT
                      OR CGI-L-FOUND = "Y"
               IF FUNCTION TRIM(CGI-KEY(CGI-W-IDX))
                  = FUNCTION TRIM(CGI-L-KEY)
                   MOVE CGI-VALUE(CGI-W-IDX) TO CGI-L-VALUE
                   MOVE "Y" TO CGI-L-FOUND
               END-IF
           END-PERFORM
           .

      *> HTML-ESCAPE
      *>
      *> Escape the five characters that have special meaning in
      *> HTML text content: &, <, >, ". The single quote is left
      *> alone because we always emit user-controlled text inside
      *> double-quoted attributes or in element content, never
      *> inside single-quoted attributes.
      *>
      *> Trims trailing spaces/low-values to find the real input
      *> length before walking the string.
      *>
      *> This procedure is the only line of defense against
      *> reflected XSS: every CGI-L-VALUE that ends up in HTML
      *> must go through it.
       HTML-ESCAPE.
           MOVE SPACES TO HTML-OUT
           MOVE 1 TO HTML-OUT-LEN
      *>   Trim trailing spaces/low-values to find input length.
           MOVE 500 TO HTML-IN-LEN
           PERFORM UNTIL HTML-IN-LEN = 0
                   OR (HTML-IN(HTML-IN-LEN:1) NOT = SPACE
                  AND HTML-IN(HTML-IN-LEN:1) NOT = LOW-VALUE)
               SUBTRACT 1 FROM HTML-IN-LEN
           END-PERFORM
           PERFORM VARYING HTML-IDX FROM 1 BY 1
                   UNTIL HTML-IDX > HTML-IN-LEN
               MOVE HTML-IN(HTML-IDX:1) TO HTML-CH
               EVALUATE HTML-CH
                   WHEN "&"
                       MOVE "&amp;"
                           TO HTML-OUT(HTML-OUT-LEN:5)
                       ADD 5 TO HTML-OUT-LEN
                   WHEN "<"
                       MOVE "&lt;"
                           TO HTML-OUT(HTML-OUT-LEN:4)
                       ADD 4 TO HTML-OUT-LEN
                   WHEN ">"
                       MOVE "&gt;"
                           TO HTML-OUT(HTML-OUT-LEN:4)
                       ADD 4 TO HTML-OUT-LEN
                   WHEN '"'
                       MOVE "&quot;"
                           TO HTML-OUT(HTML-OUT-LEN:6)
                       ADD 6 TO HTML-OUT-LEN
                   WHEN OTHER
                       MOVE HTML-CH
                           TO HTML-OUT(HTML-OUT-LEN:1)
                       ADD 1 TO HTML-OUT-LEN
               END-EVALUATE
           END-PERFORM
           SUBTRACT 1 FROM HTML-OUT-LEN
           .

      *> EMIT-HTML-HEADERS
      *>
      *> Emit the minimal CGI response headers for an HTML reply
      *> followed by the mandatory blank line separator. The blank
      *> line is produced as X"0A" (LF) because DISPLAY adds its
      *> own newline, and Apache is happy with LF endings.
       EMIT-HTML-HEADERS.
           DISPLAY "Content-Type: text/html; charset=utf-8"
           DISPLAY X"0A"
           .
