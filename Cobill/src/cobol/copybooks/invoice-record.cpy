      *> Invoice record layout. Stored in data/invoices.dat, an
      *> ISAM file with INV-NUMBER as the primary key and
      *> INV-CLIENT-ID as a duplicate-allowed alternate key (so we
      *> can iterate the invoices of a given client cheaply).
      *>
      *> Up to 10 line items are stored inline in the header record
      *> via the OCCURS clause. This violates 1NF but lets us read a
      *> full invoice in a single ISAM read, with atomic write
      *> semantics and no join. The trade-off is documented in
      *> docs/15-database-design.md.
      *>
      *> Money fields are PIC 9(7)V99 (seven digits before the
      *> decimal, two after, no float). That is COBOL's native
      *> fixed-point representation, the same kind of arithmetic
      *> bank systems have used since 1959. It rules out the silent
      *> rounding errors that IEEE 754 floats produce on amounts.
       01  INVOICE-RECORD.

      *>     Human-readable invoice number, format YYYY-NNNN
      *>     (year + 4-digit sequence, no gap). Primary key of the
      *>     file. Generated server-side in invoice.cob.
           05  INV-NUMBER          PIC X(9).

      *>     Logical foreign key to clients.dat. Alternate key here.
           05  INV-CLIENT-ID       PIC X(10).

      *>     Snapshot of the client's trade name at the moment of
      *>     issuance. Stored alongside the FK so the invoice keeps
      *>     showing the original name even if the client changes
      *>     it later (legal requirement: an issued invoice is
      *>     immutable).
           05  INV-CLIENT-NAME     PIC X(50).

      *>     Invoice issue date (ISO YYYY-MM-DD).
           05  INV-DATE            PIC X(10).

      *>     Payment due date. Computed as INV-DATE + CFG-PAY-DAYS
      *>     when the invoice is created.
           05  INV-DUE-DATE        PIC X(10).

      *>     VAT rate applied to all lines, as a decimal fraction.
      *>     0.2000 = 20 %, 0.1000 = 10 %, 0.0550 = 5.5 %, 0.0000
      *>     for art. 293 B (VAT exemption).
           05  INV-TVA-RATE        PIC V9999.

      *>     How many INV-LINES slots are actually populated (1..10).
           05  INV-LINE-COUNT      PIC 99.

      *>     Line items table. Inline (OCCURS) instead of a separate
      *>     ISAM file: simpler reads, atomic writes, capped at 10
      *>     items by design.
           05  INV-LINES OCCURS 10 TIMES.
               10  INV-DESC        PIC X(50).
      *>             Quantity, two decimal places (e.g. 1.50 hours).
               10  INV-QTY         PIC 9(4)V99.
      *>             Unit price excluding VAT.
               10  INV-UNIT-RATE   PIC 9(5)V99.
      *>             Line subtotal = INV-QTY * INV-UNIT-RATE, rounded.
               10  INV-LINE-TOTAL  PIC 9(7)V99.

      *>     Sum of all INV-LINE-TOTAL, excluding VAT.
           05  INV-AMOUNT-HT       PIC 9(7)V99.

      *>     VAT amount = INV-AMOUNT-HT * INV-TVA-RATE, ROUNDED.
           05  INV-AMOUNT-TVA      PIC 9(7)V99.

      *>     Total invoice amount = INV-AMOUNT-HT + INV-AMOUNT-TVA.
           05  INV-AMOUNT-TTC      PIC 9(7)V99.

      *>     URSSAF rate snapshotted from CFG-URSSAF-RATE at the
      *>     time of issuance (so historical invoices keep showing
      *>     the rate that applied when they were emitted).
           05  INV-URSSAF-RATE     PIC V9999.

      *>     URSSAF contribution owed for this invoice =
      *>     INV-AMOUNT-HT * INV-URSSAF-RATE.
           05  INV-URSSAF-AMOUNT   PIC 9(7)V99.

      *>     What the freelancer actually keeps =
      *>     INV-AMOUNT-HT - INV-URSSAF-AMOUNT.
           05  INV-NET-REVENUE     PIC 9(7)V99.

      *>     Workflow status. Allowed transitions:
      *>       DRAFT -> SENT -> PAID
      *>     OVERDUE is derived at render time when SENT and
      *>     INV-DUE-DATE < today; it is never written to disk.
           05  INV-STATUS          PIC X(8).

      *>     Date the invoice was marked PAID (ISO format).
      *>     Blank while still DRAFT or SENT.
           05  INV-PAID-DATE       PIC X(10).

      *>     Creation date in ISO format.
           05  INV-CREATED         PIC X(10).
