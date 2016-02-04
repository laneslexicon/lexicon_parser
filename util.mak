.PHONY: build
XMLFILES := $(wildcard ./tmp/*.xml)
DBDATE := $(shell date +"%y%m%d")
DBNAME := "$(DBDATE).sqlite"
#
build:
	./version.sh
	perl lane.pl --db lexicon.sqlite --initdb --overwrite -dir ../xml --no-context --verbose --log-dir ../logs --sql ./lexicon_schema.sql --do-all --show-progress --with-perseus
	perl links.pl --db lexicon.sqlite --log-dir ../logs --heads
	perl orths.pl --db lexicon.sqlite --log-dir ../logs --verbose
	perl links.pl --db lexicon.sqlite --log-dir ../logs --links
	perl reports.pl --db lexicon.sqlite --log-dir ../logs --dbid `cat LASTRUNID` --dir ../xml 
	perl reports.pl --dbid `cat LASTRUNID` --headwords --unmatched --log-dir ../logs

