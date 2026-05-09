      *> User config (single-row file, key = "MAIN").
       01  CONFIG-RECORD.
           05  CFG-KEY           PIC X(8).
           05  CFG-USER-NAME     PIC X(50).
           05  CFG-ADDRESS       PIC X(80).
           05  CFG-ZIP           PIC X(10).
           05  CFG-CITY          PIC X(40).
           05  CFG-COUNTRY       PIC X(30).
           05  CFG-SIRET         PIC X(17).
           05  CFG-IBAN          PIC X(34).
           05  CFG-BIC           PIC X(11).
           05  CFG-EMAIL         PIC X(60).
           05  CFG-ACTIVITY      PIC X(20).
      *>                          BNC / BIC-VENTE / BIC-SERV / CIPAV.
           05  CFG-URSSAF-RATE   PIC V9999.
           05  CFG-VAT-THRESH    PIC 9(7)V99.
           05  CFG-DEFAULT-TVA   PIC V9999.
           05  CFG-PAY-DAYS      PIC 999.
