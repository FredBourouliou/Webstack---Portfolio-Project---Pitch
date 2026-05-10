      *> hello.cob
      *>
      *> Diagnostic CGI binary. Reads the request, parses the form
      *> data, and echoes a small HTML fragment showing the request
      *> method, the number of fields received, and the value of
      *> the "name" field if present.
      *>
      *> Endpoint:   /cgi-bin/hello
      *> Auth gate:  none (this is the only public CGI binary)
      *> Used by:    smoke tests, manual diagnostic during setup.
      *>
      *> This program is the simplest possible exercise of the
      *> read -> parse -> render pipeline shared with every other
      *> binary. If it works, the CGI plumbing (Apache mod_cgi +
      *> env vars + stdin) is healthy.
       IDENTIFICATION DIVISION.
       PROGRAM-ID. HELLO.

       ENVIRONMENT DIVISION.
       CONFIGURATION SECTION.
       COPY "special-names.cpy".

       DATA DIVISION.
       WORKING-STORAGE SECTION.
      *> Working-storage block shared with every CGI program (CGI
      *> request snapshot, parsed pairs, scratch buffers, HTML
      *> escape area). Defined in copybooks/cgi-utils-ws.cpy.
       COPY "cgi-utils-ws.cpy".

       PROCEDURE DIVISION.
       MAIN-LOGIC.
      *>   Pull the CGI request (env vars + stdin body) and split
      *>   it into key/value pairs.
           PERFORM READ-CGI-INPUT
           PERFORM PARSE-CGI-INPUT

      *>   Emit "Content-Type: text/html; charset=utf-8" + blank
      *>   line. After this, anything we DISPLAY becomes the body.
           PERFORM EMIT-HTML-HEADERS
           DISPLAY "<div class='echo'>"
           DISPLAY "  <h2>HELLO FROM COBOL</h2>"
           DISPLAY "  <dl>"
           DISPLAY "    <dt>Method</dt>"
           DISPLAY "    <dd>" FUNCTION TRIM(CGI-METHOD) "</dd>"
           DISPLAY "    <dt>Fields parsed</dt>"
           DISPLAY "    <dd>" CGI-PAIR-COUNT "</dd>"

      *>   Look up the "name" field if any. FIND-FIELD scans the
      *>   parsed pairs table; CGI-L-FOUND is "Y" on match.
           MOVE "name"  TO CGI-L-KEY
           PERFORM FIND-FIELD
           IF CGI-L-FOUND = "Y"
      *>       Always HTML-escape user-controlled values before
      *>       emitting them into HTML. This is the only XSS
      *>       defense we have.
               MOVE CGI-L-VALUE TO HTML-IN
               PERFORM HTML-ESCAPE
               DISPLAY "    <dt>name</dt>"
               DISPLAY "    <dd>"
                       HTML-OUT(1:HTML-OUT-LEN)
                       "</dd>"
           ELSE
               DISPLAY "    <dt>name</dt>"
               DISPLAY "    <dd><em>(no name field)</em></dd>"
           END-IF

           DISPLAY "  </dl>"
           DISPLAY "</div>"
           STOP RUN.

      *> CGI procedure block (READ-CGI-INPUT, PARSE-CGI-INPUT,
      *> URL-DECODE, HTML-ESCAPE, FIND-FIELD, EMIT-HTML-HEADERS).
      *> Defined in copybooks/cgi-utils-procs.cpy.
       COPY "cgi-utils-procs.cpy".

       END PROGRAM HELLO.
