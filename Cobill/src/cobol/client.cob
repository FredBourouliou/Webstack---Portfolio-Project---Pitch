      *> client.cob
      *>
      *> Client CRUD endpoint. List, create, edit and soft-delete
      *> client records stored in data/clients.dat.
      *>
      *> Endpoint:   /cgi-bin/client
      *> Auth gate:  yes (auth-check.cpy)
      *> Methods:    GET for list/new/get, POST for create/update/
      *>             delete (HTMX form submissions).
      *>
      *> Recognized actions (via the "action" form field):
      *>   list    -> HTML table of all non-deleted clients
      *>   new     -> empty creation form
      *>   create  -> auto-assign id, persist, return refreshed list
      *>   get     -> load one client by id, render edit form
      *>   update  -> REWRITE the existing record, return list
      *>   delete  -> soft delete (CLI-DELETED = "Y"), return list
      *>
      *> Soft delete (rather than physical DELETE) preserves the
      *> foreign-key referential integrity of historical invoices
      *> that link back to a now-removed client.
       IDENTIFICATION DIVISION.
       PROGRAM-ID. CLIENT.

       ENVIRONMENT DIVISION.
       CONFIGURATION SECTION.
       COPY "special-names.cpy".

       INPUT-OUTPUT SECTION.
       FILE-CONTROL.
      *>     Client store. Indexed on CLI-ID (system-generated
      *>     primary key) with an alternate key on CLI-NAME for
      *>     name-based lookups. Duplicates on CLI-NAME are
      *>     allowed because two clients can share a trade name.
           SELECT CLIENT-FILE
               ASSIGN TO "data/clients.dat"
               ORGANIZATION IS INDEXED
               ACCESS MODE IS DYNAMIC
               RECORD KEY IS CLI-ID
               ALTERNATE RECORD KEY IS CLI-NAME
                   WITH DUPLICATES
               FILE STATUS IS WS-FILE-STATUS.

      *>     Session file, opened by the auth gate.
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

      *> ISAM file status. "00" = success, "35" = file not found,
      *> "23" = INVALID KEY on READ/WRITE.
       01  WS-FILE-STATUS          PIC XX.

      *> Action requested by the client. Defaults to "list" so a
      *> bare GET /cgi-bin/client shows the table.
       01  WS-ACTION               PIC X(10) VALUE "list".

      *> Loop control + row count for the listing.
       01  WS-EOF                  PIC X     VALUE "N".
       01  WS-ROW-COUNT            PIC 9(4)  VALUE 0.

      *> Working storage for the auto-numbered id generator.
      *> WS-NEXT-ID is the next free slot (1-based). WS-CUR-ID is
      *> the numeric suffix of the row currently being scanned.
      *> WS-FORMATTED-ID is the final "CLI-NNNNNN" string written
      *> into CLI-ID.
       01  WS-NEXT-ID              PIC 9(6)  VALUE 0.
       01  WS-CUR-ID               PIC 9(6)  VALUE 0.
       01  WS-FORMATTED-ID         PIC X(10).

      *> Client id pulled out of the form (for get, update, delete).
       01  WS-LOOKUP-ID            PIC X(10).

       PROCEDURE DIVISION.
       MAIN-LOGIC.
      *>   Standard CGI prologue: read request, parse form data,
      *>   enforce auth, emit content-type header.
           PERFORM READ-CGI-INPUT
           PERFORM PARSE-CGI-INPUT
           COPY "auth-check.cpy".
           PERFORM EMIT-HTML-HEADERS

      *>   Dispatch table on the "action" form field.
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

      *> ACTION-LIST
      *>
      *> Sequential walk through the whole client file, filtering
      *> out soft-deleted rows (CLI-DELETED = "Y"), and rendering
      *> each surviving record as a table row with HTMX-driven
      *> [EDIT] / [DELETE] buttons.
      *>
      *> Empty file (status "35") is rendered as a friendly
      *> "No clients yet" rather than an error.
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

      *> RENDER-CLIENT-ROW
      *>
      *> Emit one <tr> for the currently-loaded CLIENT-RECORD.
      *> Every user-controlled cell (id, name, siret, city) goes
      *> through HTML-ESCAPE so an attacker who managed to inject
      *> markup into a client name cannot break out of the cell.
      *>
      *> The action buttons use HTMX to trigger their own CGI calls
      *> when clicked, swapping the response into #content. The
      *> [DELETE] button asks for confirmation through hx-confirm.
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

      *> ACTION-NEW
      *>
      *> Render an empty client creation form. INITIALIZE blanks
      *> every field (per its PIC type), then CLI-ID is forced to
      *> SPACES so the form does not show a placeholder id.
       ACTION-NEW.
           INITIALIZE CLIENT-RECORD
           MOVE SPACES TO CLI-ID
           PERFORM RENDER-FORM-NEW
           .

      *> ACTION-GET
      *>
      *> Read one client by primary key and render the edit form.
      *> Missing or unknown id falls through to a friendly "not
      *> found" panel rather than throwing.
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

      *> ACTION-CREATE
      *>
      *> Allocate the next free CLI-NNNNNN id, populate the record
      *> from the form fields, set the creation date, write to the
      *> file, then return the refreshed list as the response. If
      *> the write fails (e.g. duplicate id, which should never
      *> happen because ASSIGN-NEXT-ID just picked an unused one),
      *> render a write-error panel.
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

      *> ACTION-UPDATE
      *>
      *> Read the client by id, overwrite every field with the
      *> matching form value, then REWRITE the record. Created
      *> date and deletion flag are preserved (POPULATE-FROM-FORM
      *> does not touch them).
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

      *> ACTION-DELETE
      *>
      *> Flip CLI-DELETED to "Y" and REWRITE. The row stays on
      *> disk so the FK from invoices.dat keeps pointing at a real
      *> record. ACTION-LIST filters out deleted rows on display.
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

      *> ----- Helpers -----

      *> LOAD-LOOKUP-ID
      *>
      *> Pull the "id" form field into WS-LOOKUP-ID. Missing field
      *> leaves WS-LOOKUP-ID at SPACES, which the callers check
      *> with FUNCTION TRIM.
       LOAD-LOOKUP-ID.
           MOVE SPACES TO WS-LOOKUP-ID
           MOVE "id" TO CGI-L-KEY
           PERFORM FIND-FIELD
           IF CGI-L-FOUND = "Y"
               MOVE FUNCTION TRIM(CGI-L-VALUE) TO WS-LOOKUP-ID
           END-IF
           .

      *> POPULATE-FROM-FORM
      *>
      *> Copy every form field into the CLIENT-RECORD. The id is
      *> set by the caller (ACTION-CREATE auto-generates it,
      *> ACTION-UPDATE keeps the existing one), so we never
      *> overwrite CLI-ID here. The created date and deletion
      *> flag are similarly preserved.
       POPULATE-FROM-FORM.
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

      *> OPEN-CLIENT-FILE-IO
      *>
      *> Open the client file for read-write. On a brand-new
      *> install the file does not exist (status "35"); recover
      *> by opening in OUTPUT mode to create it, then reopening
      *> in I-O.
       OPEN-CLIENT-FILE-IO.
           OPEN I-O CLIENT-FILE
           IF WS-FILE-STATUS = "35"
               OPEN OUTPUT CLIENT-FILE
               CLOSE CLIENT-FILE
               OPEN I-O CLIENT-FILE
           END-IF
           .

      *> ASSIGN-NEXT-ID
      *>
      *> Walk the whole file once and keep the largest numeric
      *> suffix found in any CLI-NNNNNN id, then add 1. Result
      *> goes to WS-FORMATTED-ID in the canonical "CLI-NNNNNN"
      *> form.
      *>
      *> O(n) but n stays well below 1000 for solo use, and the
      *> alternative (a dedicated counter file) would add a state
      *> we would need to keep in sync. Empty / missing file
      *> defaults to id 1.
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

      *> FORMAT-NEXT-ID
      *>
      *> Render WS-NEXT-ID (a 6-digit numeric) into WS-FORMATTED-ID
      *> as "CLI-NNNNNN". STRING ... DELIMITED BY SIZE copies the
      *> full source field, so leading zeros are preserved.
       FORMAT-NEXT-ID.
           MOVE SPACES TO WS-FORMATTED-ID
           STRING "CLI-"        DELIMITED BY SIZE
                  WS-NEXT-ID    DELIMITED BY SIZE
               INTO WS-FORMATTED-ID
           .

      *> ----- Form rendering -----
      *>
      *> The create and edit paths share the same markup; the only
      *> differences are the title, the action attribute, and a
      *> hidden id field for update. RENDER-FORM-NEW and
      *> RENDER-FORM-EDIT just set WS-ACTION and delegate.

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

      *> EMIT-FIELD-SIRET
      *>
      *> SIRET input plus the [INSEE] button. The button triggers
      *> a GET /cgi-bin/sirene with hx-include='#f-siret' so the
      *> currently typed value is sent along. The response is
      *> a small hint span (success or error) that swaps into
      *> #sirene-hint, plus four hx-swap-oob inputs that update
      *> the matching #f-name, #f-addr, #f-zip, #f-city fields
      *> in this same form (see sirene.cob).
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

      *> ----- Error renderers -----
      *> Each returns a small HTML fragment that HTMX swaps into
      *> #content. No 4xx status code is used (HTMX would not
      *> swap the response body), so the message itself signals
      *> the failure.

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

      *> Auth gate paragraphs and shared CGI helpers.
       COPY "auth-check-procs.cpy".
       COPY "cgi-utils-procs.cpy".

       END PROGRAM CLIENT.
