      *> Invoice record. Stored in data/invoices.dat. Max 10 line items.
       01  INVOICE-RECORD.
           05  INV-NUMBER          PIC X(9).
      *>                            Format YYYY-NNNN.
           05  INV-CLIENT-ID       PIC X(10).
           05  INV-CLIENT-NAME     PIC X(50).
           05  INV-DATE            PIC X(10).
           05  INV-DUE-DATE        PIC X(10).
           05  INV-TVA-RATE        PIC V9999.
           05  INV-LINE-COUNT      PIC 99.
           05  INV-LINES OCCURS 10 TIMES.
               10  INV-DESC        PIC X(50).
               10  INV-QTY         PIC 9(4)V99.
               10  INV-UNIT-RATE   PIC 9(5)V99.
               10  INV-LINE-TOTAL  PIC 9(7)V99.
           05  INV-AMOUNT-HT       PIC 9(7)V99.
           05  INV-AMOUNT-TVA      PIC 9(7)V99.
           05  INV-AMOUNT-TTC      PIC 9(7)V99.
           05  INV-URSSAF-RATE     PIC V9999.
           05  INV-URSSAF-AMOUNT   PIC 9(7)V99.
           05  INV-NET-REVENUE     PIC 9(7)V99.
           05  INV-STATUS          PIC X(8).
      *>                            DRAFT / SENT / PAID / OVERDUE.
           05  INV-PAID-DATE       PIC X(10).
           05  INV-CREATED         PIC X(10).
