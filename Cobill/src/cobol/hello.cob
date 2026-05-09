       IDENTIFICATION DIVISION.
       PROGRAM-ID. HELLO.

       ENVIRONMENT DIVISION.
       CONFIGURATION SECTION.
       COPY "special-names.cpy".

       DATA DIVISION.
       WORKING-STORAGE SECTION.
       COPY "cgi-utils-ws.cpy".

       PROCEDURE DIVISION.
       MAIN-LOGIC.
           PERFORM READ-CGI-INPUT
           PERFORM PARSE-CGI-INPUT

           PERFORM EMIT-HTML-HEADERS
           DISPLAY "<div class='echo'>"
           DISPLAY "  <h2>HELLO FROM COBOL</h2>"
           DISPLAY "  <dl>"
           DISPLAY "    <dt>Method</dt>"
           DISPLAY "    <dd>" FUNCTION TRIM(CGI-METHOD) "</dd>"
           DISPLAY "    <dt>Fields parsed</dt>"
           DISPLAY "    <dd>" CGI-PAIR-COUNT "</dd>"

           MOVE "name"  TO CGI-L-KEY
           PERFORM FIND-FIELD
           IF CGI-L-FOUND = "Y"
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

       COPY "cgi-utils-procs.cpy".

       END PROGRAM HELLO.
