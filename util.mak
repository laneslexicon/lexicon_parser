.PHONY:	test1
.PHONY:	split
.PHONY:	splitall
.PHONY: testentry
.PHONY: test
.PHONY: onefile
.PHONY: build
XMLFILES := $(wildcard ./tmp/*.xml)
DBDATE := $(shell date +"%y%m%d")
DBNAME := "$(DBDATE).sqlite"
#
# these are for testing various XLST
#
tei:
	@java -jar /workvol/saxonhe/saxon9he.jar \
              -t -xsl:./xslt/tei.xsl \
              -s:$${S} \
              -o:$${O}.tmp ;
	@cat ./tmp/header.html $${O}.tmp ./tmp/footer.html > $${O}
split:

	@java -jar /workvol/saxonhe/saxon9he.jar \
              -t -xsl:./splitter.xsl \
              -s:${S} \
              -o:./tmp/test.html
splitall:
	 for XML in $(wildcard ./xml_originals/*.xml); do \
	 	echo "$${XML}"; \
		java -jar /workvol/saxonhe/saxon9he.jar \
		-t -xsl:./splitter.xsl \
		-s:$${XML} ;\
		done;
testentry:
	@java -jar /workvol/saxonhe/saxon9he.jar \
              -t -xsl:./xslt/tei.xsl \
              -s:/tmp/lane/entry_n$${N}.xml \
              -o:/tmp/test$${N}.html

test:
	echo $(DBNAME)
# in the test directory, copy test_skel.xml as <name>.xml and insert the root entry at the place indicated
# then run this:
# make -f util.mak xml=<name> test
# and it will look for <name>.xml and output <name>.sqlite
testroot:
	./version.sh
	perl lane.pl --db ${xml}.sqlite --initdb --overwrite --xml ./test/${xml}.xml --no-context --sql ./lexicon_schema.sql
#
# use this test a single Perseus file
# make -f util.mak xml=s0 onefile
# without specify --log-dir, logfile will be written to the system temporary directory
#
onefile:
	./version.sh
	perl lane.pl --db ${xml}.sqlite --initdb --overwrite --xml ../xml/${xml}.xml --no-context --verbose --sql ./lexicon_schema.sql --with-perseus --do-all
lexicon:
	./version.sh
	perl lane.pl --db lexicon.sqlite --initdb --overwrite --dir .../xml --no-context --verbose --logbase lexicon --sql ./lexicon_schema.sql
#
# DO THIS ONE this one does everything, using the -do-all option instead of 
# doing it step by step (like in 'full' below)
#
#
build:
	./version.sh
	perl lane.pl --db lexicon.sqlite --initdb --overwrite -dir ../xml --no-context --verbose --log-dir ../logs --sql ./lexicon_schema.sql --do-all --show-progress --with-perseus
	perl links.pl --db lexicon.sqlite --log-dir ../logs --heads
	perl orths.pl --db lexicon.sqlite --log-dir ../logs --verbose
	perl links.pl --db lexicon.sqlite --log-dir ../logs --links
	perl reports.pl --db lexicon.sqlite --log-dir ../logs --dbid `cat LASTRUNID` --dir ../xml 
	perl reports.pl --dbid `cat LASTRUNID` --headwords --unmatched --log-dir ../logs
# without single word links and link processing
devbuild:
	./version.sh
	perl lane.pl --db $(DBNAME) --initdb --overwrite -dir ../xml --no-context --verbose --log-dir ../logs --sql ./lexicon_schema.sql --do-all --show-progress --with-perseus
	perl links.pl --db $(DBNAME) --log-dir ../logs --heads
#
#
#      run this to get a complete database
#
#
full:
	./version.sh
	perl lane.pl --db lexicon.sqlite --initdb --overwrite --dir ../xml --no-context --verbose --logbase lexicon --log-dir ../logs --sql ./lexicon_schema.sql
	cp lexicon.sqlite /tmp
	perl lane.pl --db lexicon.sqlite --xrefs
	perl lane.pl --db lexicon.sqlite --diacritics
	perl links.pl --db lexicon.sqlite --log-dir ../logs --links
	perl reports.pl --db lexicon.sqlite --log-dir ../logs --dbid `cat LASTRUNID` --dir ../xml 
buck:
	perl lane.pl --db buck.sqlite --initdb --overwrite --no-convert --no-context  --dir ./xml_originals --verbose --logbase buck
	cp buck.sqlite /tmp
	perl lane.pl --db buck.sqlite --set-links
xmltojson:
	java -jar /workvol/saxonhe/saxon9he.jar \
		-t -xsl:/workspace/xsltjson/conf/xml-to-json.xsl \
	       	-s:/home/andrewsg/Arabic/Lane/opensource/${XML}

diacritics:
	perl lane.pl --db lexicon.sqlite --diacritics

