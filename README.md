parser
======
Various scripts to parse, analyze the XML and load the database

perl reports.pl --questionmarks --db lexicon.sqlite --dir ../xml

orths.pl

 To test in isolation, first generate the XML:
 >perl orths.pl --show --verbose --fix --dry-run --node n1126 --with-word --out n1126.xml

 Then test XLST from the shownode directory:
 >perl ./shownode.pl --xsl cref.xslt --xmlin ../mansur/parser/n1126.xml

 To generate a report, not doing any updates,fixes etc

 perl orths.pl --db 151119.sqlite --dry-run

 (add --verbose to see the orth related text

 To import a 'raw' perseus entry, process the xml and fix the orth entries:
 (Note: this will only work with a 'regular' <entryFree> chunk. None of the exceptions
 that are handled by the horribly messy lane.pl routines

  It creates a backup fle n1128.xml.back which can be reloaded into the database.

 perl orths.pl --db 151119.sqlite --perseus n1128.xml
