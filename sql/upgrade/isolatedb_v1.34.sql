CREATE TABLE lincode_schemes (
scheme_id int NOT NULL,
thresholds text NOT NULL,
max_missing int NOT NULL,
curator int NOT NULL,
datestamp date NOT NULL,
PRIMARY KEY(scheme_id),
CONSTRAINT ls_scheme_id FOREIGN KEY(scheme_id) REFERENCES schemes
ON DELETE CASCADE
ON UPDATE CASCADE,
CONSTRAINT ls_curator FOREIGN KEY (curator) REFERENCES users
ON DELETE NO ACTION
ON UPDATE CASCADE
);

GRANT SELECT,UPDATE,INSERT,DELETE ON lincode_schemes TO apache;
