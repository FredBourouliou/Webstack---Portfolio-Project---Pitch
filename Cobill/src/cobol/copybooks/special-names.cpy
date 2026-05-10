      *> SPECIAL-NAMES paragraph shared by every CGI program.
      *>
      *> CGI feeds the POST request body to the program through stdin.
      *> COBOL's default mnemonic for standard input is SYSIN, so we
      *> remap SYSIN to STDIN here. Without this line, the ACCEPT
      *> FROM STDIN statements used to read POST bodies will not
      *> compile.
       SPECIAL-NAMES.
           SYSIN IS STDIN.
