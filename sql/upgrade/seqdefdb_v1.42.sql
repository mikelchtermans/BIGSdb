CREATE TABLE peptide_mutations (
id int NOT NULL UNIQUE,
name text NOT NULL,
locus text NOT NULL,
position int NOT NULL,
wild_type_aa char(1) NOT NULL,
variant_aa text NOT NULL,
curator integer NOT NULL,
datestamp date NOT NULL,
PRIMARY KEY (id),
CONSTRAINT pm_curator FOREIGN KEY (curator) REFERENCES users
ON DELETE NO ACTION
ON UPDATE CASCADE
);

GRANT SELECT,UPDATE,INSERT,DELETE ON peptide_mutations TO apache;

CREATE TABLE sequences_peptide_mutations (
locus text NOT NULL,
allele_id text NOT NULL,
mutation_id int NOT NULL,
amino_acid char(1) NOT NULL,
is_wild_type boolean NOT NULL,
is_mutation boolean NOT NULL,
curator integer NOT NULL,
datestamp date NOT NULL,
PRIMARY KEY(locus, allele_id, mutation_id),
CONSTRAINT spm_sequences FOREIGN KEY (locus,allele_id) REFERENCES sequences
ON DELETE CASCADE
ON UPDATE CASCADE,
CONSTRAINT spm_mutation_id FOREIGN KEY (mutation_id) REFERENCES peptide_mutations
ON DELETE CASCADE
ON UPDATE CASCADE,
CONSTRAINT spm_curator FOREIGN KEY (curator) REFERENCES users
ON DELETE NO ACTION
ON UPDATE CASCADE
);

GRANT SELECT,UPDATE,INSERT,DELETE ON sequences_peptide_mutations TO apache;

CREATE TABLE dna_mutations (
id int NOT NULL UNIQUE,
name text NOT NULL,
locus text NOT NULL,
position int NOT NULL,
wt_nuc char(1) NOT NULL,
variant_nuc text NOT NULL,
curator integer NOT NULL,
datestamp date NOT NULL,
PRIMARY KEY (id),
CONSTRAINT dm_curator FOREIGN KEY (curator) REFERENCES users
ON DELETE NO ACTION
ON UPDATE CASCADE
);

GRANT SELECT,UPDATE,INSERT,DELETE ON dna_mutations TO apache;
