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
use Time::HiRes qw( time );

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
my $skipConvert = 0;
my $debug = 0;
my $dbname = "test.sqlite";
my $overwrite = 0;
my $dryRun = 0;
GetOptions (
            "dry-run"   => \$dryRun,
            "overwrite" => \$overwrite,
            "no-convert" =>  \$skipConvert, # do not convert nodes with lang="ar"
            "verbose" => \$verbose,
            "debug" => \$debug,
            "commit=i" => \$commitCount, # db.commit after write count
            "xml=s" => \$xmlFile,        # file to parse
            "dir=s" => \$parseDir, # directory with xml files to be parsed
            "initdb" => \$initdb,  # delete existing records
            "sql=s"  => \$sqlSource, # SQL used to init db
            "db=s" => \$dbname
           )
  or die("Error in command line arguments\n");


#
# control totals
#
my $formWithAttributes = 0;
my $entryFreeWithoutKey = 0;
my $entryFreeWithoutId = 0;
my $orthPromotion=0;
my $orthDrop = 0;
my $itypePromotion=0;
my $skipRootCount = 0;
my $xrefDbCount = 0;
my $entryDbCount = 0;
my $rootDbCount = 0;
my $genWarning = 0;
my $elapsedTime = 0;
#
#
my $dbh = 0;
my $writeCount = 0;
my $dbupdate = 1;        # set to 0 to prevent db writes
my $dbErrorCount = 0;
my $xrefsth;
my $entrysth;
#

my $currentNodeId;
my $currentRoot;
my $currentWord;
my $currentItype;
my @currentForms;
my @currentStatus;
################################################################
#
#
################################################################
sub writelog {
  my $h = shift;
  my $t = shift;

  chomp $t;
  print $h "$t\n";

}
################################################################
#  buckwalter conversion
################################################################
sub convertString {
  my $t = shift;
  my $s = $t;

  return $t unless ! $skipConvert;
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
################################################################
#
#
################################################################
sub processForm {
  my $formNode = shift;
  my $name;


  my $attrs = $formNode->getAttributes;
  if ($attrs->getLength > 0) {
    if ($debug) {
      print STDERR "Node $currentNodeId, <form> with attibutes:\n";
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
#            print STDERR "Checking orth/itype ---->[$currentWord][$currentItype][$t]\n";
            if ($t) {
              # this seems to be where key is the same as the numeric itype value
              if (
                   (! $currentWord || ($currentWord =~ /^\s*\d+\s*$/)) &&
                      ($currentItype =~ /^\d+$/))
                {
                $currentWord = $t;
                $debug && print STDERR ">>> node $currentNodeId: first <orth> promoted to <itype> currentWord : $t\n";
                $itypePromotion++;
                $currentStatus[3] = "i";
              }
              elsif (! $currentWord ) {
                $currentWord = $t;
                $debug && print STDERR ">>> node $currentNodeId: first <orth> promoted to currentWord : $t\n";
                $orthPromotion++;
                $currentStatus[4] = "o";
              }
              elsif ($t =~ /^\d+$/) {
                $orthDrop++;
                $currentStatus[6] = "d";
              }
              elsif (($t ne "*") &&
                  ( $t ne $currentRoot ) &&
                  ( $t ne $currentWord )) {
                push @currentForms, $t;
              }
            }
          }
        } else {
          print STDERR "Parse warning 1: <orth> without child nodes\n";
          $genWarning++;
        }
      }
    }
    $child = $child->getNextSibling;
  }
  return;
}
################################################################
#
#
################################################################

sub processNode {
  my $node = shift;
  my $nodeName;

  $nodeName =  $node->getNodeName;
  if ($nodeName eq "form") {
    processForm($node);
  }

}
################################################################
#
#
################################################################

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
################################################################
#
#
################################################################
sub writeXref {
  my $word = shift;
  my $bword = shift;
  my $node = shift;

  $debug && print STDERR "XREF write: [$word][$bword][$node]\n";

  if ($dryRun) {
    $xrefDbCount++;
    return;
  }
  $xrefsth->bind_param(1,$word);
  $xrefsth->bind_param(2,$bword);
  $xrefsth->bind_param(3,$node);
  if ($xrefsth->execute()) {
    $xrefDbCount++;
    $writeCount++;
  }
  else {
    $dbErrorCount++;
  }
  if ($writeCount > $commitCount) {
    $dbh->commit();
  }
}
################################################################
# these two subroutines traverse the node converting all text
# nodes whose parent has lang="ar"
#
################################################################
sub convertNode {
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
        my $str = convertString($text);
        $textNode->setNodeValue($str);
        #
        # write xref record using: $currentWord,$currentNodeId,$text,$str
        #
        writeXref($str,$text,$currentNodeId);
      }
    } else {
      print STDERR "Parse warning 2: node <$nodeName> has lang=ar but no text\n";
      $genWarning++;
    }
  }
}
################################################################
#
#
################################################################
sub traverseAndConvertNode {
  my $node = shift;

  while ($node) {
    if ($node->getNodeType == ELEMENT_NODE) {
      convertNode($node);
    }
    if ($node->hasChildNodes) {
      traverseAndConvertNode($node->getFirstChild);
    }
    $node = $node->getNextSibling;
  }
}
################################################################
#
#
################################################################
sub processRoot {
  my $node = shift;
  my $entries = $node->getElementsByTagName("entryFree");
  my $entryCount = $entries->getLength;
  my $idAttr;
  my $keyAttr;
  my $key;
  my $skipRoot;
  print STDERR sprintf "[Root=%s][Entries=%d]\n",$currentRoot,$entryCount;

  #
  # write root record ?
  #
  if ($entryCount > 0) {
    $rootDbCount++;
  }
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
    $#currentStatus = -1;
    for(my $j=0;$j < 7;$j++) {
      push @currentStatus,"-";
    }
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
        $currentStatus[0] = "m";
      }
      $keyAttr = $entry->getAttributeNode("key");
      if ($keyAttr) {
        $key = $keyAttr->getValue();
        if (! $key ) {
          $verbose && print STDERR "Node has no key:" . $entry->toString . "\n";
          $entryFreeWithoutKey++;
          $currentStatus[1] = "k";
        } else {
          $currentWord = $key;
        }
      }
      if ($id ) {
        $currentNodeId = $id;
        traverseNode($entry->getFirstChild);
        my $numeric = " ";
        if ($currentWord =~ /3/) {
          my $t = $currentWord;
          $currentWord =~ tr/3/h/;
          $currentStatus[2] = "s";
          $verbose && print STDERR "At node $currentNodeId: change $t -> $currentWord\n";
        } elsif ($currentWord =~ /\d/) {
          $numeric = "n";
          $currentStatus[5] = "n";
        }
        $entry->setAttribute("key",$currentWord);
        my $status = join "",@currentStatus; #$numeric,
        print STDERR sprintf "[%03d][%s]>>> %5s%7s %-30s%-5s %s\n",
          $i,
          $status,
          $currentRoot,
          $currentNodeId,
          $currentWord,
          $currentItype,
          join ",", @currentForms;
        if ($currentNodeId && $currentWord) {
          #
          #  We can now update the database but first convert any buckwalter transliteration
          #
          #  not efficient as we have already traversed the node but want to separate
          #  out the buckwalter conversion by cloning the node so that we can write out the
          #  XML that has been 'fixed' and use it to generate any diff's from the original.
          #
          my $xml;
          if (! $skipConvert ) {
            my $clone = $entry->cloneNode(1);
            if ($clone->getNodeType == ELEMENT_NODE) {
              traverseAndConvertNode($clone);
              $clone->setAttribute("key",convertString($currentWord));
              $xml =  $clone->toString;
            }
            else {
              print STDERR "Error cloning node for transliteration:$currentNodeId,$currentWord";
            }
            if (! $xml ) {
              $xml = $entry->toString;
            }
          }
          $entryDbCount++;
          #
          # update db
          #
        }
        else {
          print STDERR "Parse warning 3: No node or word\n";
          $genWarning++;
        }
      }
      else {
        print STDERR "Parse warning 4: No ID field\n";
        $genWarning++;
      }
    }
  }
}
################################################################
#
#
################################################################
sub parseFile {
  my $fileName = shift;
  my $start = time();
  print STDERR "Parsing file: $fileName\n";
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
  my $end = time();
  $elapsedTime = $end - $start;
  print STDERR sprintf "Skip root count         : %d\n",$skipRootCount;
  print STDERR sprintf "<entryFree> without key : %d\n",$entryFreeWithoutKey;
  print STDERR sprintf "<entryFree> without id  : %d\n",$entryFreeWithoutId;
  print STDERR sprintf "Itype promotion         : %d\n",$itypePromotion;
  print STDERR sprintf "Orth promotion          : %d\n",$orthPromotion;
  print STDERR sprintf "Orth drop               : %d\n",$orthDrop;
  print STDERR sprintf "General warning         : %d\n",$genWarning;
  print STDERR sprintf "Xref count              : %d\n",$xrefDbCount;
  print STDERR sprintf "Root count              : %d\n",$rootDbCount;
  print STDERR sprintf "Entry count             : %d\n",$entryDbCount;
  print STDERR sprintf "Elapse time             : %.2f\n", $elapsedTime;

  if ( ! $dryRun ) {
    $dbh->commit();
  }
}
################################################################
#
#
################################################################
sub parseDirectory {
  my $d = shift;

  if (! -d $d ) {
    print STDERR "No such directory:[$d]\n";
    return;

  }
  my @totals;

  eval {
    my @arr;
    find sub { if ((-f $_) && ($File::Find::name =~ /xml$/))  {  push @arr,$File::Find::name; } }, $d;
    foreach my $file (@arr) {
      $formWithAttributes = 0;
      $entryFreeWithoutKey = 0;
      $entryFreeWithoutId = 0;
      $orthPromotion=0;
      $orthDrop = 0;
      $itypePromotion=0;
      $skipRootCount = 0;
      $xrefDbCount = 0;
      $entryDbCount = 0;
      $rootDbCount = 0;
      $genWarning = 0;

      parseFile($file);

      push @totals, {
                     "File" => $file,
                     "Skip root count" => $skipRootCount,
                     "<entryFree> without key" => $entryFreeWithoutKey,
                     "<entryFree> without id" => $entryFreeWithoutId,
                     "Itype promotion" => $itypePromotion,
                     "Orth promotion" => $orthPromotion,
                     "Orth drop" => $orthDrop,
                     "General warning" => $genWarning,
                     "Xref count" => $xrefDbCount,
                     "Root count" => $rootDbCount,
                     "Entry count" => $entryDbCount,
                     "Elapse time" => $elapsedTime
                    }
    }

  };

  if ($@) {
    print STDERR "File::Find error opening directory:[$d]\n";
  }
}
################################################################
#
#
################################################################
sub getSQL {
  return <<EOF;
PRAGMA foreign_keys=OFF;
BEGIN TRANSACTION;
CREATE TABLE root (
id integer primary key,
word text,
letter text,
xml text
);
create TABLE itype (
id integer primary key,
itype integer,
root text,
rootId integer,
nodeId text,
word text,
xml text
);
create TABLE entry (
id integer primary key,
root text,
rootId integer,
nodeId text,
word text,
bword text,
xml text
);

CREATE TABLE xref (
id INTEGER primary key,
word TEXT,
bword text,
node TEXT,
type INTEGER
);
COMMIT;
EOF
}
################################################################
#
#
################################################################
sub openDb {
  my $db = shift;

  my $sth;
  ### Attributes to pass to DBI->connect(  )
  my %attr = (
              PrintError => 1,
              RaiseError => 0
             );

  eval {
    $dbh = DBI->connect("dbi:SQLite:$db","","",\%attr) or die "couldn’t connect to db" . DBI->errstr;
  };
  if ($@) {
    print STDERR "Error opening db:$@\n";
    exit 1;
  }
  else {
    $verbose && print STDERR "Opened db $db\n";
  }
  $dbh->{AutoCommit} => 1;
  $dbh->begin_work;
}
################################################################
#
#
################################################################
sub initialiseDb {
  my $db = shift;
  my $sql = shift;

  my $sth;
  ### Attributes to pass to DBI->connect(  )
  my %attr = (
              PrintError => 1,
              RaiseError => 0
             );

  eval {
    $dbh = DBI->connect("dbi:SQLite:$db","","",\%attr) or die "couldn’t connect to db" . DBI->errstr;
  };
  if ($@) {
    print STDERR "Error initialising db:$@\n";
    exit 1;
  }
  my @c = split ";" , $sql;
  my $ok = 1;
  foreach my $line (@c) {
    $sth = $dbh->prepare($line);
    if (! $sth ) {
      print STDERR "Error prepare init SQL: $line" . $dbh->errstr();
      $ok = 0;
    }
    if (! $sth->execute()) {
      print STDERR "Error executing init SQL:$line" . $dbh->errstr();
      $ok = 0;
  }
}
 if ($ok) {
   print STDOUT "DB initialised OK\n";
 }
  $dbh->disconnect;
}
#############################################################
#
#
############################################################
open($blog,">:encoding(UTF8)","x.log");
if ($initdb) {
  my $sql;
  if ($sqlSource) {
    # get SQL source from file
  }
  else {
    $sql = getSQL();
  }
  if ( -e $dbname ) {
    if (! $overwrite )  {
      print STDERR "DB $dbname exists, remove or run with --overwrite\n";
      exit 1;
    }
    else {
      unlink $dbname;
    }
  }
  if ( ! $sql ) {
      print STDERR "No SQL source for inititialisation\n";
      exit 1;
  }
  initialiseDb($dbname,$sql);

}
if (! $dryRun ) {
   openDb($dbname);
   $xrefsth = $dbh->prepare("insert into xref (word,bword,node) values (?,?,?)");
}
if ($xmlFile) {
  if ( ! -e $xmlFile) {
    print STDERR "No such file: $xmlFile";
    exit 1;
  }
  parseFile($xmlFile);
}
elsif ($parseDir ) {
  if ( ! -d $parseDir ) {
    print STDERR "No such directory: $parseDir\n";
    exit 1;
  }
  parseDirectory($parseDir);
}
else {
  parseFile("./test/test_j0.xml");
}
#convertString("ja Oxdr sthwmn");

#open $blog,">x.log";

#parseFile("./xml/j0.xml");

#parseDirectory("./xml");
