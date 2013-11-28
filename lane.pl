#!/usr/bin/perl -w
use strict;
use XML::DOM;
use XML::Parser;
use Encode;
use utf8;
use DBI;
use File::Find;
use Data::Dumper;
use Getopt::Long;

my $onceOnly = 0;
my $missingIdCount = 0;

binmode STDERR, ":utf8";
binmode STDOUT, ":utf8";
my $blog;                       # buckwalter conversion log handle

#
# cmd line args
#
my $verbose = 0;
my $initdb  = 0;
my $xmlFile = "";
my $parseDir = "";
my $dbName = "";
my $commitCount = 1000;
my $sqlSource = "";
my $skipConvertBuckwalter = 0;
my $debug = 0;
GetOptions (
            "no-convert" =>  \$skipConvertBuckwalter, # do not convert nodes with lang="ar"
            "verbose" => \$verbose,
            "debug" => \$debug,
            "commit=i" => \$commitCount, # db.commit after write count
            "xml=s" => \$xmlFile,        # file to parse
            "dir=s" => \$parseDir, # directory with xml files to be parsed
            "initdb" => \$initdb,  # delete existing records
            "sql=s"  => \$sqlSource # SQL used to init db
           )
  or die("Error in command line arguments\n");


#
# control totals
#
my $formWithAttributes = 0;
my $entryFreeWithoutKey = 0;
my $entryFreeWithoutId = 0;
my $orthPromotion=0;
my $itypePromotion=0;
my $skipRootCount = 0;
#
#
my $writeCount = 0;


my $currentNodeId;
my $currentRoot;
my $currentWord;
my $currentItype;
my @currentForms;
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

  return $t unless ! $skipConvertBuckwalter;
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
  $entryFreeWithoutId++;
  return sprintf "m%04d",$entryFreeWithoutId;
}
sub processForm {
  my $formNode = shift;
  my $name;


  my $attrs = $formNode->getAttributes;
  if ($attrs->getLength > 0) {
    if ($debug) {
      print STDERR "Warning node $currentNodeId, <form> with attibutes:\n";
      print STDERR ">>>\n" . $formNode->toString . "\n<<<\n";
    }
    $formWithAttributes++;
    my $n = $attrs->getNamedItem("n");
    if ($n) {
      my $v = $n->getNodeValue;
      if ($v eq "infl") {
        # do something with it?
      } elsif ( $v ) {
        $debug && print STDERR "<form> with non-infl type: $v\n";
      }
    }
  }
  my $child = $formNode->getFirstChild;
  while ($child) {
    #    print "\t\t" . $child->getNodeName . "\n";
    if ($child->getNodeType == ELEMENT_NODE) {
      $name = $child->getNodeName;
      if ($name eq "itype") {
        my $textNode = $child->getFirstChild;
        if ($textNode->getNodeType == TEXT_NODE) {
          my $t = $textNode->getNodeValue;
          if ($t) {
            $currentItype = $t;
          }
        }
      } elsif ($name eq "orth") {
        if ($child->hasChildNodes) {
          my $textNode = $child->getFirstChild;
          if ($textNode->getNodeType == TEXT_NODE) {
            my $t = $textNode->getNodeValue;
            if ($t) {
              if (! $currentWord && $currentItype && $currentItype =~ /\d+/) {
                $currentWord = $t;
                $debug && print STDERR ">>> node $currentNodeId: first <orth> promoted to <itype> currentWord : $t\n";
                $itypePromotion++;
              }
              if (! $currentWord ) {
                $currentWord = $t;
                $debug && print STDERR ">>> node $currentNodeId: first <orth> promoted to currentWord : $t\n";
                $orthPromotion++;
              }
              if (($t ne "*") &&
                  ( $t ne $currentRoot ) &&
                  ( $t ne $currentWord )) {
                push @currentForms, $t;
              }
            }
          }
        } else {
          print STDERR "Warning <orth> without child nodes\n";
        }
      }
    }
    $child = $child->getNextSibling;
  }
  return;
}
sub processNode {
  my $node = shift;
  my $nodeName;

  $nodeName =  $node->getNodeName;
  #  print "$nodeName\n";
  my $attr = $node->getAttributeNode("lang");
  if ($attr && ($attr->getValue eq "ar")) {
    if ($node->hasChildNodes) {
      my $textNode = $node->getFirstChild;
      if ($textNode->getNodeType == TEXT_NODE) {
        my $text = $textNode->getNodeValue;
        $textNode->setNodeValue(convertString($text));
      }
    } else {
      print STDERR "Warning node <$nodeName> has lang=ar but no text\n";
    }
  }
  if ($nodeName eq "form") {
    processForm($node);
  }

}

sub traverseNode {
  my $node = shift;

  while ($node) {
    if ($node->getNodeType == ELEMENT_NODE) {
      processNode($node);
    }
    if ($node->hasChildNodes) {
      traverseNode($node->getFirstChild);
    }
    $node = $node->getNextSibling;
  }
}

sub processRoot {
  my $node = shift;
  my $entries = $node->getElementsByTagName("entryFree");
  my $entryCount = $entries->getLength;
  my $idAttr;
  my $keyAttr;
  my $key;
  my $skipRoot;
  print STDERR "Root: $currentRoot, entryFree count: $entryCount\n";
  for (my $i=0;$i < $entryCount;$i++) {
    my $entry = $entries->item($i);
    #    print sprintf "Processing entryFree %d [ %s  ]\n",$i,$entry->getNodeName;
    my $id;
    my $key;
    my $ar_key;
    $skipRoot = 0;

    $currentWord = "";
    $currentNodeId = "";
    $currentItype = "";
    $#currentForms = -1;
    my $textNode = $entry->getFirstChild;
    if ($textNode->getNodeType == TEXT_NODE) {
      my $text = $textNode->getNodeValue;
      if (($text =~ /see\s+supplement/i) && ($entryCount == 1)) {
        $skipRoot = 1;
        $skipRootCount++;
        $verbose && print STDERR "Root [$currentRoot] skipped, <see supplement> entry\n";
      }
    }
    if (! $skipRoot ) {
      $idAttr = $entry->getAttributeNode("id");
      if ($idAttr) {
        $id = $idAttr->getValue();
      } else {
        $verbose && print STDERR "Node has no ID:" . $entry->toString . "\n";
        $id = createId();
        $entry->setAttribute("id",$id);
      }
      $keyAttr = $entry->getAttributeNode("key");
      if ($keyAttr) {
        $key = $keyAttr->getValue();
        if (! $key ) {
          $verbose && print STDERR "Node has no key:" . $entry->toString . "\n";
          $entryFreeWithoutKey++;

        } elsif ($key =~ /^\d+$/) {
          print STDERR "Node $id with numeric key";
        } else {
          $currentWord = convertString($key);
        }
      }
      if ($id ) {
        $currentNodeId = $id;
        traverseNode($entry->getFirstChild);
        my $numeric = " ";
        if ($currentWord =~ /3/) {
          my $t = $currentWord;
          $currentWord =~ tr/3/h/;
          $verbose && print STDERR "At node $currentNodeId: change $t -> $currentWord\n";
        } elsif ($currentWord =~ /\d/) {
          $numeric = "n";
        }
        $entry->setAttribute("key",$currentWord);
        print STDERR sprintf "[%03d][%s]>>> %5s%7s %-30s%-5s %s\n",
          $i,
          $numeric,
          $currentRoot,
          $currentNodeId,
          $currentWord,
          $currentItype,
          join ",", @currentForms;
        if ($currentNodeId && $currentWord) {
          # update db
        }
      } else {
        print STDERR sprintf "[%03d]<<< %5s%7s %-30s%-5s %s\n",
          $i,
          $currentRoot,
          $currentNodeId,
          $currentWord,
          $currentItype,
          join ",", @currentForms;
      }
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
        $currentRoot = $div2Node->getAttributeNode("n")->getValue();
        processRoot($div2Node);
      }
    }
  }
  print STDERR "\nControl totals:\n";
  # Print doc file
  # $doc->printToFile ("out.xml");

  # Print to string
  #print $doc->toString;

  # Avoid memory leaks - cleanup circular references for garbage collection
  my $str =  $doc->toString;

  open(OUT,">:encoding(UTF8)","/tmp/test.xml");
  binmode OUT, ":utf8";
  print OUT $str;
  close OUT;

  $doc->dispose;


  print STDERR sprintf "Skip root count         : %d\n",$skipRootCount;
  print STDERR sprintf "<entryFree> without key : %d\n",$entryFreeWithoutKey;
  print STDERR sprintf "<entryFree> without id  : %d\n",$entryFreeWithoutId;
  print STDERR sprintf "Itype promotion         : %d\n",$itypePromotion;
  print STDERR sprintf "Orth promotion          : %d\n",$orthPromotion;

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
open($blog,">:encoding(UTF8)","x.log");
if ($xmlFile) {
  if ( ! -e $xmlFile) {
    print STDERR "No such file: $xmlFile";
    exit 1;
  }
  parseFile($xmlFile);
}
#convertString("ja Oxdr sthwmn");

#open $blog,">x.log";

#parseFile("./xml/j0.xml");
#parseFile("./test/test_j0.xml");
#parseDirectory("./xml");
