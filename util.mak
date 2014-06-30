.PHONY:	test1
.PHONY:	split
.PHONY:	splitall
.PHONY: testentry
XMLFILES := $(wildcard ./tmp/*.xml)
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
small:
	./version.sh
	perl lane.pl --db test.sqlite --initdb --overwrite --xml ./test/test_itype.xml --no-context --logbase test --sql ./lexicon_schema.sql
jeem:
	./version.sh
	perl lane.pl --db jeem.sqlite --initdb --overwrite --xml ../xml/j0.xml --no-context --verbose --logbase jeem --sql ./lexicon_schema.sql
#	cp jeem.sqlite /tmp
#	perl lane.pl --db jeem.sqlite --set-links
lexicon:
	./version.sh
	perl lane.pl --db lexicon.sqlite --initdb --overwrite --dir .../xml --no-context --verbose --logbase lexicon --sql ./lexicon_schema.sql
#
#
#      run this to get a complete database
#
#
full:
	./version.sh
	perl lane.pl --db lexicon.sqlite --initdb --overwrite --dir ../xml --no-context --verbose --logbase lexicon --sql ./lexicon_schema.sql
	cp lexicon.sqlite /tmp
	perl lane.pl --db lexicon.sqlite --xrefs
	perl lane.pl --db lexicon.sqlite --diacritics
	perl lane.pl --db lexicon.sqlite --set-links
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
