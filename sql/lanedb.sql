PRAGMA foreign_keys=OFF;
BEGIN TRANSACTION;
CREATE TABLE words (
id INTEGER primary key,
letter TEXT,
root TEXT,
word TEXT,
node TEXT,
sourcefile TEXT,
xml TEXT,
html TEXT,
node_num INTEGER,
type INTEGER,
notes TEXT);
CREATE INDEX ix_root on words (root ASC);
CREATE INDEX ix_word on words (word ASC);
CREATE INDEX ix_letter on words (letter ASC);
CREATE INDEX ix_node on words (node ASC);
CREATE INDEX ix_node_num on words (node_num ASC);

CREATE TABLE root {
id integer primary key,
word text;
nodeId text
};
create TABLE itype {
id integer primary key,
itype integer,
word text,
rootId integer,
xml text,
nodeId text
};
create TABLE entry {
id integer primary key,
word text,
rootId integer,
xml text,
nodeId text
};

CREATE TABLE xref (
id INTEGER primary key,
word TEXT,
node TEXT,
type INTEGER
);
CREATE INDEX ix_xref on xref (word ASC);
CREATE TABLE buck (
id INTEGER primary key,
win TEXT,
wout TEXT,
type INTEGER
);
CREATE INDEX ix_buck_win on buck (win ASC);
CREATE INDEX ix_buck_wout on buck (wout ASC);
CREATE TABLE nodenotes (
id INTEGER primary key,
nid INTEGER,
nodes TEXT,
type INTEGER
);
CREATE INDEX ix_node_id on nodenotes (nid ASC);
COMMIT;
