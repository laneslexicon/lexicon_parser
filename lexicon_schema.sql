CREATE TABLE root (id integer primary key,datasource integer,word text,bword text,letter text,bletter text,xml text,supplement integer,quasi integer,alternates integer,page integer);
CREATE TABLE alternate (id integer primary key,datasource integer,word text,bword text,letter text,bletter text,xml text,supplement integer,quasi integer,alternate integer);
CREATE TABLE itype (id integer primary key,datasource integer,itype integer,root text,broot text,nodeid text,word text,xml text, bareword text);
CREATE TABLE entry (id integer primary key,datasource integer,root text,broot text,word text,bword text,itype text,nodeid text,xml text,supplement integer,file text,page integer,nodenum real, bareword text,perseusxml text,headword text, type int default 0);
CREATE TABLE links (id integer primary key, linkid integer,datasource integer,root text,word text,fromnode text,tonode text,link text,matchtype integer,matchedword text,orthfixtype integer default -1,orthpattern text,orthindex integer,status integer default -1,note text);
CREATE INDEX 'fromnode_link' on links (fromnode asc);
CREATE INDEX 'status_index' on links (status asc);
CREATE INDEX 'linkid_index' on links (linkid asc);

CREATE INDEX 'word_index' on entry (word asc);
CREATE INDEX 'headword_index' on entry (headword asc);
CREATE INDEX 'broot_index' on entry (broot asc);
CREATE INDEX 'root_index' on entry (root asc);
CREATE TABLE xref (id INTEGER primary key,datasource integer,word TEXT,bword text,node TEXT,type INTEGER,page integer, bentry text, entry text, broot text, root text, bareword text,nodenum real);
CREATE TABLE pos (id INTEGER primary key,datasource integer,root text,headword text,bareword text,word text,nodeid text,pos text);
CREATE INDEX 'letter_index' on root (letter asc);
CREATE INDEX 'nodenum_index' on entry (nodenum asc);
CREATE INDEX 'nodenum_index_desc' on entry (nodenum desc);
CREATE INDEX 'supp_letter_index' on root (supplement asc,letter asc);
CREATE INDEX 'supp_word_index' on root (supplement asc,word asc);
CREATE INDEX 'node_index' on entry (nodeid asc);
CREATE INDEX 'xref_bword' on xref (bword asc);
CREATE INDEX 'xref_word' on xref (word asc);
CREATE INDEX 'xref_nodenum' on xref (nodenum asc);
CREATE INDEX 'bareword_index' on entry (bareword asc);
CREATE INDEX page_index on entry (page asc);

CREATE TABLE lexicon (id integer primary key, sourceid integer,description text,createversion text,createdate text,updateversion text,updatedate text,xmlversion text,dbid text);
