-- Schéma SQL équivalent du modèle ISAM (documentaire, non exécuté).
-- Stockage réel : data/{clients,invoices,sessions,config}.dat (ISAM COBOL).
-- Cible : PostgreSQL 14+ ou SQLite 3.35+.

CREATE TABLE clients (
    cli_id        CHAR(10)     PRIMARY KEY,
    cli_name      VARCHAR(50)  NOT NULL,
    cli_address   VARCHAR(80),
    cli_zip       VARCHAR(10),
    cli_city      VARCHAR(40),
    cli_country   VARCHAR(30),
    cli_siret     CHAR(17),
    cli_email     VARCHAR(60),
    cli_phone     VARCHAR(20),
    cli_created   CHAR(10)     NOT NULL,
    cli_deleted   CHAR(1)      NOT NULL DEFAULT 'N'
                  CHECK (cli_deleted IN ('Y', 'N'))
);

CREATE INDEX idx_clients_name ON clients (cli_name);


CREATE TABLE invoices (
    inv_number         CHAR(9)       PRIMARY KEY,
    inv_client_id      CHAR(10)      NOT NULL
                       REFERENCES clients (cli_id),
    inv_client_name    VARCHAR(50)   NOT NULL,
    inv_date           CHAR(10)      NOT NULL,
    inv_due_date       CHAR(10)      NOT NULL,
    inv_tva_rate       DECIMAL(5,4)  NOT NULL,
    inv_line_count     SMALLINT      NOT NULL
                       CHECK (inv_line_count BETWEEN 1 AND 10),
    inv_amount_ht      DECIMAL(9,2)  NOT NULL,
    inv_amount_tva     DECIMAL(9,2)  NOT NULL,
    inv_amount_ttc     DECIMAL(9,2)  NOT NULL,
    inv_urssaf_rate    DECIMAL(5,4)  NOT NULL,
    inv_urssaf_amount  DECIMAL(9,2)  NOT NULL,
    inv_net_revenue    DECIMAL(9,2)  NOT NULL,
    inv_status         VARCHAR(8)    NOT NULL
                       CHECK (inv_status IN ('DRAFT','SENT','PAID')),
    inv_paid_date      CHAR(10),
    inv_created        CHAR(10)      NOT NULL
);

CREATE INDEX idx_invoices_client ON invoices (inv_client_id);
CREATE INDEX idx_invoices_date   ON invoices (inv_date);
CREATE INDEX idx_invoices_status ON invoices (inv_status);


-- En ISAM, les lignes sont stockées en ligne (OCCURS 10 TIMES dans le
-- record invoice). Cette table SQL est l'équivalent normalisé.
CREATE TABLE invoice_lines (
    inv_number      CHAR(9)       NOT NULL
                    REFERENCES invoices (inv_number) ON DELETE CASCADE,
    line_num        SMALLINT      NOT NULL
                    CHECK (line_num BETWEEN 1 AND 10),
    inv_desc        VARCHAR(50)   NOT NULL,
    inv_qty         DECIMAL(6,2)  NOT NULL,
    inv_unit_rate   DECIMAL(7,2)  NOT NULL,
    inv_line_total  DECIMAL(9,2)  NOT NULL,
    PRIMARY KEY (inv_number, line_num)
);


CREATE TABLE sessions (
    ses_token    CHAR(32)     PRIMARY KEY,
    ses_user     VARCHAR(30)  NOT NULL,
    ses_created  CHAR(19)     NOT NULL,
    ses_expires  CHAR(19)     NOT NULL,
    ses_active   CHAR(1)      NOT NULL DEFAULT 'Y'
                 CHECK (ses_active IN ('Y','N'))
);


CREATE TABLE config (
    cfg_key          CHAR(8)       PRIMARY KEY DEFAULT 'MAIN'
                     CHECK (cfg_key = 'MAIN'),
    cfg_user_name    VARCHAR(50)   NOT NULL,
    cfg_address      VARCHAR(80),
    cfg_zip          VARCHAR(10),
    cfg_city         VARCHAR(40),
    cfg_country      VARCHAR(30),
    cfg_siret        CHAR(17),
    cfg_iban         VARCHAR(34),
    cfg_bic          VARCHAR(11),
    cfg_email        VARCHAR(60),
    cfg_activity     VARCHAR(20)
                     CHECK (cfg_activity IN
                            ('BNC','BIC-VENTE','BIC-SERV','CIPAV')),
    cfg_urssaf_rate  DECIMAL(5,4),
    cfg_vat_thresh   DECIMAL(9,2),
    cfg_default_tva  DECIMAL(5,4),
    cfg_pay_days     SMALLINT
);
