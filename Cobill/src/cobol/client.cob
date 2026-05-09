       IDENTIFICATION DIVISION.
       PROGRAM-ID. CLIENT.

       ENVIRONMENT DIVISION.
       CONFIGURATION SECTION.
       COPY "special-names.cpy".

       INPUT-OUTPUT SECTION.
       FILE-CONTROL.
           SELECT CLIENT-FILE
               ASSIGN TO "data/clients.dat"
               ORGANIZATION IS INDEXED
               ACCESS MODE IS DYNAMIC
               RECORD KEY IS CLI-ID
               ALTERNATE RECORD KEY IS CLI-NAME
                   WITH DUPLICATES
               FILE STATUS IS WS-FILE-STATUS.

           SELECT SESSION-FILE
               ASSIGN TO "data/sessions.dat"
               ORGANIZATION IS INDEXED
               ACCESS MODE IS DYNAMIC
               RECORD KEY IS SES-TOKEN
               FILE STATUS IS WS-AUTH-FS-STATUS.

       DATA DIVISION.
       FILE SECTION.
       FD CLIENT-FILE.
       COPY "client-record.cpy".

       FD SESSION-FILE.
       COPY "session-record.cpy".

       WORKING-STORAGE SECTION.
       COPY "cgi-utils-ws.cpy".
       COPY "auth-check-ws.cpy".

       01  WS-FILE-STATUS          PIC XX.
       01  WS-ACTION               PIC X(10) VALUE "list".
       01  WS-EOF                  PIC X     VALUE "N".
       01  WS-ROW-COUNT            PIC 9(4)  VALUE 0.

       01  WS-NEXT-ID              PIC 9(6)  VALUE 0.
       01  WS-CUR-ID               PIC 9(6)  VALUE 0.
       01  WS-FORMATTED-ID         PIC X(10).

       01  WS-LOOKUP-ID            PIC X(10).

       PROCEDURE DIVISION.
       MAIN-LOGIC.
           PERFORM READ-CGI-INPUT
           PERFORM PARSE-CGI-INPUT
           COPY "auth-check.cpy".
           PERFORM EMIT-HTML-HEADERS

           MOVE "action" TO CGI-L-KEY
           PERFORM FIND-FIELD
           IF CGI-L-FOUND = "Y"
               MOVE FUNCTION TRIM(CGI-L-VALUE) TO WS-ACTION
           END-IF

           EVALUATE FUNCTION TRIM(WS-ACTION)
               WHEN "list"
                   PERFORM ACTION-LIST
               WHEN "new"
                   PERFORM ACTION-NEW
               WHEN "create"
                   PERFORM ACTION-CREATE
               WHEN "get"
                   PERFORM ACTION-GET
               WHEN "update"
                   PERFORM ACTION-UPDATE
               WHEN "delete"
                   PERFORM ACTION-DELETE
               WHEN OTHER
                   PERFORM RENDER-UNKNOWN-ACTION
           END-EVALUATE

           STOP RUN.

      *> ACTION-LIST — sequential read of all (non-deleted) clients,
      *> rendered as an HTML table with HTMX action buttons per row.
       ACTION-LIST.
           OPEN INPUT CLIENT-FILE

           DISPLAY "<section class='panel' id='clients-panel'>"
           DISPLAY "  <header class='panel-head'>"
           DISPLAY "    <h2>CLIENTS</h2>"
           DISPLAY "    <button class='btn-primary'"
           DISPLAY "            hx-get='/cgi-bin/client"
                   "?action=new'"
           DISPLAY "            hx-target='#content'"
           DISPLAY "            hx-swap='innerHTML'>"
           DISPLAY "      [+ NEW CLIENT]"
           DISPLAY "    </button>"
           DISPLAY "  </header>"

           IF WS-FILE-STATUS = "35"
               DISPLAY "  <p><em>No clients yet.</em></p>"
               DISPLAY "</section>"
               EXIT PARAGRAPH
           END-IF

           IF WS-FILE-STATUS NOT = "00"
               DISPLAY "  <p>File error: " WS-FILE-STATUS "</p>"
               DISPLAY "</section>"
               EXIT PARAGRAPH
           END-IF

           DISPLAY "  <table>"
           DISPLAY "    <thead><tr>"
           DISPLAY "      <th>ID</th>"
           DISPLAY "      <th>NAME</th>"
           DISPLAY "      <th>SIRET</th>"
           DISPLAY "      <th>CITY</th>"
           DISPLAY "      <th>ACTIONS</th>"
           DISPLAY "    </tr></thead>"
           DISPLAY "    <tbody>"

           MOVE "N" TO WS-EOF
           MOVE 0   TO WS-ROW-COUNT
           PERFORM UNTIL WS-EOF = "Y"
               READ CLIENT-FILE NEXT RECORD
                   AT END
                       MOVE "Y" TO WS-EOF
                   NOT AT END
                       IF CLI-DELETED NOT = "Y"
                           PERFORM RENDER-CLIENT-ROW
                           ADD 1 TO WS-ROW-COUNT
                       END-IF
               END-READ
           END-PERFORM

           CLOSE CLIENT-FILE

           DISPLAY "    </tbody>"
           DISPLAY "  </table>"
           DISPLAY "  <p class='count'>" WS-ROW-COUNT
                   " client(s)</p>"
           DISPLAY "</section>"
           .

       RENDER-CLIENT-ROW.
           DISPLAY "      <tr>"

           MOVE CLI-ID TO HTML-IN
           PERFORM HTML-ESCAPE
           DISPLAY "        <td>"
                   HTML-OUT(1:HTML-OUT-LEN) "</td>"

           MOVE CLI-NAME TO HTML-IN
           PERFORM HTML-ESCAPE
           DISPLAY "        <td>"
                   HTML-OUT(1:HTML-OUT-LEN) "</td>"

           MOVE CLI-SIRET TO HTML-IN
           PERFORM HTML-ESCAPE
           DISPLAY "        <td>"
                   HTML-OUT(1:HTML-OUT-LEN) "</td>"

           MOVE CLI-CITY TO HTML-IN
           PERFORM HTML-ESCAPE
           DISPLAY "        <td>"
                   HTML-OUT(1:HTML-OUT-LEN) "</td>"

           DISPLAY "        <td class='row-actions'>"
           DISPLAY "          <button class='btn'"
           DISPLAY "                  hx-get='/cgi-bin/client"
                   "?action=get&id=" FUNCTION TRIM(CLI-ID) "'"
           DISPLAY "                  hx-target='#content'"
           DISPLAY "                  hx-swap='innerHTML'>"
           DISPLAY "            [EDIT]"
           DISPLAY "          </button>"
           DISPLAY "          <button class='btn btn-danger'"
           DISPLAY "                  hx-post='/cgi-bin/client"
                   "?action=delete&id=" FUNCTION TRIM(CLI-ID) "'"
           DISPLAY "                  hx-target='#content'"
           DISPLAY "                  hx-swap='innerHTML'"
           DISPLAY "                  hx-confirm='Delete "
                   FUNCTION TRIM(CLI-NAME) " ?'>"
           DISPLAY "            [DELETE]"
           DISPLAY "          </button>"
           DISPLAY "        </td>"

           DISPLAY "      </tr>"
           .

      *> ACTION-NEW — render an empty creation form.
       ACTION-NEW.
           INITIALIZE CLIENT-RECORD
           MOVE SPACES TO CLI-ID
           PERFORM RENDER-FORM-NEW
           .

      *> ACTION-GET — read one client by id, render edit form.
       ACTION-GET.
           PERFORM LOAD-LOOKUP-ID
           IF FUNCTION TRIM(WS-LOOKUP-ID) = SPACES
               PERFORM RENDER-MISSING-ID
               EXIT PARAGRAPH
           END-IF

           OPEN INPUT CLIENT-FILE
           IF WS-FILE-STATUS NOT = "00"
               PERFORM RENDER-NOT-FOUND
               EXIT PARAGRAPH
           END-IF

           MOVE WS-LOOKUP-ID TO CLI-ID
           READ CLIENT-FILE
               INVALID KEY
                   CLOSE CLIENT-FILE
                   PERFORM RENDER-NOT-FOUND
                   EXIT PARAGRAPH
               NOT INVALID KEY
                   CLOSE CLIENT-FILE
                   PERFORM RENDER-FORM-EDIT
           END-READ
           .

      *> create — auto-assign id, write, return refreshed list.
       ACTION-CREATE.
           PERFORM ASSIGN-NEXT-ID

           PERFORM OPEN-CLIENT-FILE-IO
           IF WS-FILE-STATUS NOT = "00"
               PERFORM RENDER-WRITE-ERROR
               EXIT PARAGRAPH
           END-IF

           INITIALIZE CLIENT-RECORD
           MOVE WS-FORMATTED-ID TO CLI-ID
           PERFORM POPULATE-FROM-FORM
      *>   FUNCTION CURRENT-DATE returns YYYYMMDDhhmmsshh+TTMM ;
      *>   the first 8 chars are the date, formatted to YYYY-MM-DD.
           STRING FUNCTION CURRENT-DATE(1:4) DELIMITED BY SIZE
                  "-"                        DELIMITED BY SIZE
                  FUNCTION CURRENT-DATE(5:2) DELIMITED BY SIZE
                  "-"                        DELIMITED BY SIZE
                  FUNCTION CURRENT-DATE(7:2) DELIMITED BY SIZE
               INTO CLI-CREATED
           MOVE "N" TO CLI-DELETED

           WRITE CLIENT-RECORD
               INVALID KEY
                   CLOSE CLIENT-FILE
                   PERFORM RENDER-WRITE-ERROR
                   EXIT PARAGRAPH
               NOT INVALID KEY
                   CONTINUE
           END-WRITE

           CLOSE CLIENT-FILE
           PERFORM ACTION-LIST
           .

      *> ACTION-UPDATE — REWRITE existing record. id comes from form.
       ACTION-UPDATE.
           PERFORM LOAD-LOOKUP-ID
           IF FUNCTION TRIM(WS-LOOKUP-ID) = SPACES
               PERFORM RENDER-MISSING-ID
               EXIT PARAGRAPH
           END-IF

           OPEN I-O CLIENT-FILE
           IF WS-FILE-STATUS NOT = "00"
               PERFORM RENDER-NOT-FOUND
               EXIT PARAGRAPH
           END-IF

           MOVE WS-LOOKUP-ID TO CLI-ID
           READ CLIENT-FILE
               INVALID KEY
                   CLOSE CLIENT-FILE
                   PERFORM RENDER-NOT-FOUND
                   EXIT PARAGRAPH
               NOT INVALID KEY
                   PERFORM POPULATE-FROM-FORM
                   REWRITE CLIENT-RECORD
                       INVALID KEY
                           CLOSE CLIENT-FILE
                           PERFORM RENDER-WRITE-ERROR
                           EXIT PARAGRAPH
                       NOT INVALID KEY
                           CONTINUE
                   END-REWRITE
           END-READ

           CLOSE CLIENT-FILE
           PERFORM ACTION-LIST
           .

      *> ACTION-DELETE — soft delete (CLI-DELETED='Y'), then list.
       ACTION-DELETE.
           PERFORM LOAD-LOOKUP-ID
           IF FUNCTION TRIM(WS-LOOKUP-ID) = SPACES
               PERFORM RENDER-MISSING-ID
               EXIT PARAGRAPH
           END-IF

           OPEN I-O CLIENT-FILE
           IF WS-FILE-STATUS NOT = "00"
               PERFORM RENDER-NOT-FOUND
               EXIT PARAGRAPH
           END-IF

           MOVE WS-LOOKUP-ID TO CLI-ID
           READ CLIENT-FILE
               INVALID KEY
                   CLOSE CLIENT-FILE
                   PERFORM RENDER-NOT-FOUND
                   EXIT PARAGRAPH
               NOT INVALID KEY
                   MOVE "Y" TO CLI-DELETED
                   REWRITE CLIENT-RECORD
                       INVALID KEY
                           CONTINUE
                       NOT INVALID KEY
                           CONTINUE
                   END-REWRITE
           END-READ

           CLOSE CLIENT-FILE
           PERFORM ACTION-LIST
           .

      *> Helpers.
       LOAD-LOOKUP-ID.
           MOVE SPACES TO WS-LOOKUP-ID
           MOVE "id" TO CGI-L-KEY
           PERFORM FIND-FIELD
           IF CGI-L-FOUND = "Y"
               MOVE FUNCTION TRIM(CGI-L-VALUE) TO WS-LOOKUP-ID
           END-IF
           .

       POPULATE-FROM-FORM.
      *>   id stays from the caller (auto-assigned for create,
      *>   read from key for update).
           MOVE "name" TO CGI-L-KEY
           PERFORM FIND-FIELD
           MOVE CGI-L-VALUE TO CLI-NAME

           MOVE "address" TO CGI-L-KEY
           PERFORM FIND-FIELD
           MOVE CGI-L-VALUE TO CLI-ADDRESS

           MOVE "zip" TO CGI-L-KEY
           PERFORM FIND-FIELD
           MOVE CGI-L-VALUE TO CLI-ZIP

           MOVE "city" TO CGI-L-KEY
           PERFORM FIND-FIELD
           MOVE CGI-L-VALUE TO CLI-CITY

           MOVE "country" TO CGI-L-KEY
           PERFORM FIND-FIELD
           MOVE CGI-L-VALUE TO CLI-COUNTRY

           MOVE "siret" TO CGI-L-KEY
           PERFORM FIND-FIELD
           MOVE CGI-L-VALUE TO CLI-SIRET

           MOVE "email" TO CGI-L-KEY
           PERFORM FIND-FIELD
           MOVE CGI-L-VALUE TO CLI-EMAIL

           MOVE "phone" TO CGI-L-KEY
           PERFORM FIND-FIELD
           MOVE CGI-L-VALUE TO CLI-PHONE
           .

       OPEN-CLIENT-FILE-IO.
           OPEN I-O CLIENT-FILE
           IF WS-FILE-STATUS = "35"
               OPEN OUTPUT CLIENT-FILE
               CLOSE CLIENT-FILE
               OPEN I-O CLIENT-FILE
           END-IF
           .

      *> Scan the file once, find the largest numeric suffix in
      *> CLI-NNNNNN, return the next id in WS-FORMATTED-ID.
       ASSIGN-NEXT-ID.
           MOVE 0 TO WS-NEXT-ID
           OPEN INPUT CLIENT-FILE
           IF WS-FILE-STATUS = "35"
      *>       File doesn't exist — start at 1.
               MOVE 1 TO WS-NEXT-ID
               PERFORM FORMAT-NEXT-ID
               EXIT PARAGRAPH
           END-IF
           IF WS-FILE-STATUS NOT = "00"
               MOVE 1 TO WS-NEXT-ID
               PERFORM FORMAT-NEXT-ID
               EXIT PARAGRAPH
           END-IF

           MOVE "N" TO WS-EOF
           PERFORM UNTIL WS-EOF = "Y"
               READ CLIENT-FILE NEXT RECORD
                   AT END
                       MOVE "Y" TO WS-EOF
                   NOT AT END
                       IF CLI-ID(1:4) = "CLI-"
                           MOVE 0 TO WS-CUR-ID
                           COMPUTE WS-CUR-ID =
                               FUNCTION NUMVAL(CLI-ID(5:6))
                           IF WS-CUR-ID > WS-NEXT-ID
                               MOVE WS-CUR-ID TO WS-NEXT-ID
                           END-IF
                       END-IF
               END-READ
           END-PERFORM

           CLOSE CLIENT-FILE
           ADD 1 TO WS-NEXT-ID
           PERFORM FORMAT-NEXT-ID
           .

       FORMAT-NEXT-ID.
           MOVE SPACES TO WS-FORMATTED-ID
           STRING "CLI-"        DELIMITED BY SIZE
                  WS-NEXT-ID    DELIMITED BY SIZE
               INTO WS-FORMATTED-ID
           .

      *> Form rendering (new + edit share most markup).
       RENDER-FORM-NEW.
           MOVE "create" TO WS-ACTION
           PERFORM RENDER-FORM
           .

       RENDER-FORM-EDIT.
           MOVE "update" TO WS-ACTION
           PERFORM RENDER-FORM
           .

       RENDER-FORM.
           DISPLAY "<section class='panel'>"
           IF FUNCTION TRIM(WS-ACTION) = "create"
               DISPLAY "  <h2>NEW CLIENT</h2>"
           ELSE
               DISPLAY "  <h2>EDIT CLIENT &mdash; "
                       FUNCTION TRIM(CLI-ID) "</h2>"
           END-IF

           DISPLAY "  <form hx-post='/cgi-bin/client?action="
                   FUNCTION TRIM(WS-ACTION) "'"
           DISPLAY "        hx-target='#content'"
           DISPLAY "        hx-swap='innerHTML'>"

           IF FUNCTION TRIM(WS-ACTION) = "update"
               DISPLAY "    <input type='hidden' name='id' value='"
                       FUNCTION TRIM(CLI-ID) "'>"
           END-IF

           PERFORM EMIT-FIELD-NAME
           PERFORM EMIT-FIELD-ADDRESS
           PERFORM EMIT-FIELD-ZIP-CITY
           PERFORM EMIT-FIELD-COUNTRY
           PERFORM EMIT-FIELD-SIRET
           PERFORM EMIT-FIELD-EMAIL
           PERFORM EMIT-FIELD-PHONE

           DISPLAY "    <div class='form-actions'>"
           DISPLAY "      <button type='submit' "
                   "class='btn-primary'>[SAVE]</button>"
           DISPLAY "      <button type='button' class='btn'"
           DISPLAY "              hx-get='/cgi-bin/client"
                   "?action=list'"
           DISPLAY "              hx-target='#content'"
           DISPLAY "              hx-swap='innerHTML'>"
           DISPLAY "        [CANCEL]"
           DISPLAY "      </button>"
           DISPLAY "    </div>"
           DISPLAY "  </form>"
           DISPLAY "</section>"
           .

       EMIT-FIELD-NAME.
           MOVE CLI-NAME TO HTML-IN
           PERFORM HTML-ESCAPE
           DISPLAY "    <div class='form-row'>"
           DISPLAY "      <label for='f-name'>NAME......:</label>"
           DISPLAY "      <input id='f-name' name='name' "
                   "required value='"
                   HTML-OUT(1:HTML-OUT-LEN) "'>"
           DISPLAY "    </div>"
           .

       EMIT-FIELD-ADDRESS.
           MOVE CLI-ADDRESS TO HTML-IN
           PERFORM HTML-ESCAPE
           DISPLAY "    <div class='form-row'>"
           DISPLAY "      <label for='f-addr'>ADDRESS...:</label>"
           DISPLAY "      <input id='f-addr' name='address' value='"
                   HTML-OUT(1:HTML-OUT-LEN) "'>"
           DISPLAY "    </div>"
           .

       EMIT-FIELD-ZIP-CITY.
           MOVE CLI-ZIP TO HTML-IN
           PERFORM HTML-ESCAPE
           DISPLAY "    <div class='form-row form-row-double'>"
           DISPLAY "      <label for='f-zip'>ZIP/CITY..:</label>"
           DISPLAY "      <input id='f-zip' name='zip' "
                   "class='small' value='"
                   HTML-OUT(1:HTML-OUT-LEN) "'>"

           MOVE CLI-CITY TO HTML-IN
           PERFORM HTML-ESCAPE
           DISPLAY "      <input id='f-city' name='city' value='"
                   HTML-OUT(1:HTML-OUT-LEN) "'>"
           DISPLAY "    </div>"
           .

       EMIT-FIELD-COUNTRY.
           MOVE CLI-COUNTRY TO HTML-IN
           PERFORM HTML-ESCAPE
           DISPLAY "    <div class='form-row'>"
           DISPLAY "      <label for='f-cntry'>COUNTRY...:</label>"
           DISPLAY "      <input id='f-cntry' name='country' value='"
                   HTML-OUT(1:HTML-OUT-LEN) "'>"
           DISPLAY "    </div>"
           .

       EMIT-FIELD-SIRET.
           MOVE CLI-SIRET TO HTML-IN
           PERFORM HTML-ESCAPE
           DISPLAY "    <div class='form-row form-row-siret'>"
           DISPLAY "      <label for='f-siret'>SIRET.....:</label>"
           DISPLAY "      <input id='f-siret' name='siret' "
                   "maxlength='17' value='"
                   HTML-OUT(1:HTML-OUT-LEN) "'>"
           DISPLAY "      <button type='button' class='btn btn-sirene'"
           DISPLAY "              hx-get='/cgi-bin/sirene'"
           DISPLAY "              hx-include='#f-siret'"
           DISPLAY "              hx-target='#sirene-hint'"
           DISPLAY "              hx-swap='innerHTML'>"
           DISPLAY "        [INSEE]"
           DISPLAY "      </button>"
           DISPLAY "    </div>"
           DISPLAY "    <div id='sirene-hint' "
                   "class='form-hint sirene-hint'></div>"
           .

       EMIT-FIELD-EMAIL.
           MOVE CLI-EMAIL TO HTML-IN
           PERFORM HTML-ESCAPE
           DISPLAY "    <div class='form-row'>"
           DISPLAY "      <label for='f-email'>EMAIL.....:</label>"
           DISPLAY "      <input id='f-email' name='email' "
                   "type='email' value='"
                   HTML-OUT(1:HTML-OUT-LEN) "'>"
           DISPLAY "    </div>"
           .

       EMIT-FIELD-PHONE.
           MOVE CLI-PHONE TO HTML-IN
           PERFORM HTML-ESCAPE
           DISPLAY "    <div class='form-row'>"
           DISPLAY "      <label for='f-phone'>PHONE.....:</label>"
           DISPLAY "      <input id='f-phone' name='phone' value='"
                   HTML-OUT(1:HTML-OUT-LEN) "'>"
           DISPLAY "    </div>"
           .

      *> Error renderers.
       RENDER-MISSING-ID.
           DISPLAY "<div class='echo'>"
           DISPLAY "  <h2>MISSING ID</h2>"
           DISPLAY "  <p>Field <code>id</code> is required.</p>"
           DISPLAY "</div>"
           .

       RENDER-NOT-FOUND.
           DISPLAY "<div class='echo'>"
           DISPLAY "  <h2>CLIENT NOT FOUND</h2>"
           DISPLAY "  <p>id="
                   FUNCTION TRIM(WS-LOOKUP-ID) "</p>"
           DISPLAY "</div>"
           .

       RENDER-WRITE-ERROR.
           DISPLAY "<div class='echo'>"
           DISPLAY "  <h2>WRITE FAILED</h2>"
           DISPLAY "  <p>FILE STATUS = " WS-FILE-STATUS "</p>"
           DISPLAY "</div>"
           .

       RENDER-UNKNOWN-ACTION.
           DISPLAY "<div class='echo'>"
           DISPLAY "  <h2>UNKNOWN ACTION</h2>"
           DISPLAY "  <p>action="
                   FUNCTION TRIM(WS-ACTION) "</p>"
           DISPLAY "</div>"
           .

       COPY "auth-check-procs.cpy".
       COPY "cgi-utils-procs.cpy".

       END PROGRAM CLIENT.
