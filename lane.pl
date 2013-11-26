#!/usr/bin/perl -w
use strict;
use XML::DOM;
use XML::Parser;
use Encode;
use utf8;
use DBI;
use File::Find;

my $missingIdCount = 0;
binmode STDERR, ":utf8";
binmode STDOUT, ":utf8";
my $blog;                       # buckwalter conversion log handle

sub writelog {
  my $h = shift;
  my $t = shift;

  chomp $t;
  print $h "$t\n";

}
#
#  buckwalter conversion
#
sub convertString {
  my $t = shift;
  my $s = $t;

  my $c = 0;
  $c += ($t =~ tr/'|OWI}A/\x{621}\x{622}\x{623}\x{624}\x{625}\x{626}\x{627}/);
  $c += ($t =~ tr/bptvjHx/\x{628}\x{629}\x{62a}\x{62b}\x{62c}\x{62d}\x{62e}/);
  $c += ($t =~ tr/d*rzs$S/\x{62f}\x{630}\x{631}\x{632}\x{633}\x{634}\x{635}/);
  $c += ($t =~ tr/DTZEg\-f/\x{636}\x{637}\x{638}\x{639}\x{63a}\x{640}\x{641}/);
  $c += ($t =~ tr/qklmnhw/\x{642}\x{643}\x{644}\x{645}\x{646}\x{657}\x{648}/);
  $c += ($t =~ tr/YyFNKau/\x{649}\x{64a}\x{64b}\x{64c}\x{64d}\x{64e}\x{64f}/);
  $c += ($t =~ tr/i~o`{/\x{650}\x{651}\x{652}\x{670}\x{671}/);

  # ^ as hamza above
  # = alef with madda above (in buckwalter docs is |)
  # _ tatweel , also - above
  $c += ($t =~ tr/^=_/\x{654}\x{622}\x{640}/);

  # count the spaces etc
  my $r = $t;
  my $spaces = ($r =~ s/ / /g);

  if (($c + $spaces) != length $t) {
    writelog($blog,"conversion error [$s]->[$t]");
  }
  return $t;
}
#
# all id values are n\d+ so we call ours m\d+
#
sub createId {
  return "m$missingIdCount";
}
sub processRoot {
  my $node = shift;
  my $entries = $node->getElementsByTagName("entryFree");
  my $entryCount = $entries->getLength;
  my $idAttr;
  my $keyAttr;


  for (my $i=0;$i < $entryCount;$i++) {
    my $entry = $entries->item($i);
    my $id;
    my $key;
    my $ar_key;

    $idAttr = $entry->getAttributeNode("id");
    if ($idAttr) {
      $id = $idAttr->getValue();
    } else {
      print STDERR "Node has no ID:" . $entry->toString . "\n";
      $missingIdCount++;
    }
    $keyAttr = $entry->getAttributeNode("key");
    if ($keyAttr) {
      $key = $keyAttr->getValue();
      $ar_key = convertString($key);
    }

    if ($id && $key) {
      print "\t$id\t\t$key\t$ar_key\n";
      $entry->setAttribute("key",$ar_key);
    }
  }

}
sub parseFile {

  my $fileName = shift;

  my $parser = new XML::DOM::Parser;
  my $doc = $parser->parsefile ($fileName);

  # print all HREF attributes of all CODEBASE elements
  my $nodes = $doc->getElementsByTagName ("div1");
  my $n = $nodes->getLength;

  for (my $i = 0; $i < $n; $i++) {

    my $div1Node = $nodes->item($i);
    my $roots = $div1Node->getElementsByTagName("div2");
    my $rootCount = $roots->getLength;
    for (my $j=0;$j < $rootCount;$j++) {
      my $div2Node = $roots->item($j);
      if ($div2Node->getAttributeNode("type")->getValue() eq "root") {
        print $div2Node->getAttributeNode("n")->getValue() . "\n";
        processRoot($div2Node);

      }
    }
  }
  print "Missing ID count:$missingIdCount\n";


  # Print doc file
  # $doc->printToFile ("out.xml");

  # Print to string
  #print $doc->toString;

  # Avoid memory leaks - cleanup circular references for garbage collection
  my $str =  $doc->toString;

  open(OUT,">:encoding(UTF8)","/tmp/test.xml");
#  binmode OUT, ":utf8";
  print OUT $str;

  close OUT;
  $doc->dispose;
}
sub parseDirectory {
  my $d = shift;

  if (! -d $d ) {
    print STDERR "No such directory:$d\n";
    return;

  }
  eval {
    my @arr;
    find sub { if ((-f $_) && ($File::Find::name =~ /xml$/))
                 {
                   push @arr,$File::Find::name;
                 }
             }, $d;
    foreach my $file (@arr) {
      print "$file\n";
    }

  };
  if ($@) {
    print STDERR "Error opening directory $d\n";

  }
}
#convertString("ja Oxdr sthwmn");
open $blog,">x.log";

#parseFile("./xml/j0.xml");
parseFile("./test/test_j0.xml");
#parseDirectory("./xml");
