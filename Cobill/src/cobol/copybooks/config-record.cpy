      *> Configuration record layout. Stored in data/config.dat as a
      *> singleton ISAM file: there is always exactly one row, keyed
      *> on the literal string "MAIN".
      *>
      *> The config holds the auto-entrepreneur's own identity that
      *> appears at the top of every invoice: name, address, SIRET,
      *> IBAN, etc. It also stores the URSSAF rate, the VAT
      *> exemption threshold, the default VAT rate, and the default
      *> payment terms applied when an invoice is created.
      *>
      *> Multi-user support (planned v1.2) will replace this layout
      *> with one row per user, keyed on the user id instead of the
      *> fixed "MAIN" literal.
       01  CONFIG-RECORD.

      *>     Primary key. Always the literal "MAIN".
           05  CFG-KEY           PIC X(8).

      *>     Auto-entrepreneur's full legal name. Printed in the
      *>     "From" block of every PDF invoice.
           05  CFG-USER-NAME     PIC X(50).

      *>     Postal address printed on invoices.
           05  CFG-ADDRESS       PIC X(80).
           05  CFG-ZIP           PIC X(10).
           05  CFG-CITY          PIC X(40).
           05  CFG-COUNTRY       PIC X(30).

      *>     French SIRET (14 digits with spaces). Mandatory on
      *>     French invoices (Code de Commerce L441-9).
           05  CFG-SIRET         PIC X(17).

      *>     IBAN in standard format (up to 34 chars). Printed in
      *>     the payment block of the PDF.
           05  CFG-IBAN          PIC X(34).

      *>     Bank Identifier Code. Optional with SEPA but still
      *>     printed for compatibility.
           05  CFG-BIC           PIC X(11).

           05  CFG-EMAIL         PIC X(60).

      *>     Activity category. Drives the default URSSAF rate.
      *>       BNC      = liberal professions, BNC services
      *>       BIC-VENTE= commercial sales
      *>       BIC-SERV = commercial services
      *>       CIPAV    = liberal professions affiliated to CIPAV
           05  CFG-ACTIVITY      PIC X(20).

      *>     URSSAF rate as a decimal fraction (PIC V9999 = four
      *>     decimal places, no integer part). Example: 0.2200 for
      *>     22 %. Applied to INV-AMOUNT-HT to compute the URSSAF
      *>     contribution per invoice.
           05  CFG-URSSAF-RATE   PIC V9999.

      *>     VAT exemption threshold (franchise en base de TVA).
      *>     Below this yearly revenue, the auto-entrepreneur is
      *>     not VAT-liable. Default: 36 800 € for services, 91 900 €
      *>     for sales.
           05  CFG-VAT-THRESH    PIC 9(7)V99.

      *>     Default VAT rate suggested when creating a new invoice.
      *>     Same encoding as CFG-URSSAF-RATE (e.g. 0.2000 for 20 %).
           05  CFG-DEFAULT-TVA   PIC V9999.

      *>     Default payment terms in days. 30 means due date is set
      *>     to invoice date + 30.
           05  CFG-PAY-DAYS      PIC 999.
