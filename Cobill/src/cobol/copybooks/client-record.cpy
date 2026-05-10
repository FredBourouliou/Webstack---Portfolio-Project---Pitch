      *> Client record layout. Stored in data/clients.dat, an ISAM
      *> file with CLI-ID as the primary key and CLI-NAME as a
      *> duplicate-allowed alternate key (for name-based lookup).
      *>
      *> Clients are soft-deleted (CLI-DELETED = "Y") rather than
      *> physically removed so historical invoices keep a valid
      *> reference. Invoices also snapshot the client name at the
      *> time of issuance (see INV-CLIENT-NAME in invoice-record.cpy)
      *> to satisfy the legal requirement that an issued invoice is
      *> immutable.
       01  CLIENT-RECORD.

      *>     System-generated identifier (format CLI-NNNNNN). Never
      *>     built from user input, so it is safe to use in file
      *>     paths.
           05  CLI-ID            PIC X(10).

      *>     Trade name. Indexed (alternate key) to allow lookup by
      *>     name.
           05  CLI-NAME          PIC X(50).

      *>     Street address as a single line.
           05  CLI-ADDRESS       PIC X(80).

      *>     Postal code. PIC X (not 9) so non-French codes still
      *>     fit.
           05  CLI-ZIP           PIC X(10).
           05  CLI-CITY          PIC X(40).
           05  CLI-COUNTRY       PIC X(30).

      *>     French SIRET, 14 digits with spaces (format
      *>     "XXX XXX XXX XXXXX"). Optional: foreign clients have no
      *>     SIRET. May be enriched from the INSEE API by sirene.cob.
           05  CLI-SIRET         PIC X(17).

           05  CLI-EMAIL         PIC X(60).
           05  CLI-PHONE         PIC X(20).

      *>     Creation date in ISO format YYYY-MM-DD.
           05  CLI-CREATED       PIC X(10).

      *>     Soft-delete flag. "Y" hides the client from listings
      *>     but keeps its invoices valid.
           05  CLI-DELETED       PIC X.
