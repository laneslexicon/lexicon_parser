#!/usr/bin/perl -w
use strict;
use POSIX;
use XML::DOM;
use XML::Parser;
use Encode;
use utf8;
use DBI;
use File::Spec;
use File::Basename;
use File::Find;
use Data::Dumper;
use Getopt::Long;
use Time::HiRes qw( time );

my $onceOnly = 0;
my $missingIdCount = 0;

binmode STDERR, ":utf8";
binmode STDOUT, ":utf8";
my $blog;                       # buckwalter conversion log handle
my $plog;   # parse log for diagnostic output;
my $elog;   # error log
my $dlog;
#
# cmd line args
#
my $verbose = 0;
my $initdb  = 0;
my $xmlFile = "";
my $parseDir = "";
my $commitCount = 1000;
my $sqlSource = "";
my $skipConvert = 0;
my $debug = 0;
my $dbname;
my $overwrite = 0;        # overwrite existing db
my $dryRun = 0;           # no db update
my $textMargin = 30;
my $suppressFixups = 0;
my $suppressContext = 0;
my $doTest = "";
my $logDir = "/tmp";
my $linksMode = 0;
GetOptions (
            "set-links" => \$linksMode,
            "logdir=s" => \$logDir,
            "test=s" => \$doTest,
            "no-context"  => \$suppressContext,
            "suppress-fixups" => \$suppressFixups,
            "dry-run"   => \$dryRun,
            "overwrite" => \$overwrite,
            "no-convert" =>  \$skipConvert, # do not convert nodes with lang="ar"
            "verbose" => \$verbose,
            "debug" => \$debug,
            "commit=i" => \$commitCount, # db.commit after write count
            "margin=i" => \$textMargin,   # before & after text length to include in conversion error
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
my $conversionErrors = 0;
my $adjustedConversions = 0;
#
#
my $dbh = 0;
my $writeCount = 0;
my $totalWriteCount = 0;
my $dbupdate = 1;        # set to 0 to prevent db writes
my $dbErrorCount = 0;
my $xrefsth;
my $entrysth;
my $rootsth;
my $lookupsth;    # for 'select id from entry where word = ?
my $dlookupsth;    # for 'select id from entry where word = ? or word = ?
#

my $currentNodeId;
my $currentRoot;
my $currentWord;
my $currentItype;
my $currentLetter;
my @currentForms;
my @currentStatus;
my $currentText;
sub testConvertString {
  my $t = shift;
  my $s = $t;
  my ($start,$end,$ix);


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
  my %h;
  $h{indexes} = [];
  # count the spaces etc
  my $r = $t;
  my $spaces = ($r =~ s/ / /g);
  my $sz = length $t;
  my $errStr = "";

  my @indexes;
  for (my $i=0;$i < $sz;$i++) {
    my $x= substr $t,$i,1;
    if ($x eq (substr $s,$i,1)) {
#     if ($x !~ /\p{IsPunct}|\p{IsSpace}/) {
      if ($x !~ /\p{IsSpace}/) {
        $errStr .= "x";
        push @indexes,$i;
      }
      else {
        $errStr .= "-";
      }
    }
    else {
        $errStr .= "-";
    }
  }
  return {
          count => $#indexes + 1,
          err => $errStr,
          t => $t,
          indexes => \@indexes
         };
}
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
#
#
################################################################
sub fixup {
  my $s = shift;

  my $fixup = 0;
  my $err = "";
  if ($s =~ /^\s*\d+\s*$/) {
    $err = "itype";
    $fixup++;
  }
    my $ix = index $s,"@";
    if ($ix != -1) {
      if ((substr $s,$ix -1,1) eq "A") {
        $err  = "alef wasla";
        $fixup++;
      }
    }
  if ($s =~ /&[amp;]*c/) {
    $err = "Etc";
    $fixup++;
  }
  if ($s =~ /3a/) {
    $err = "3 for h";
    $fixup++;
  }
  if ($s =~ /V/) {
    $err = "Capital letter V";
    $fixup++;
  }
  if ($s =~ /G/) {
    $err = "Capital letter G";
    $fixup++;
  }
  $adjustedConversions =  $adjustedConversions + $fixup;
  return ($fixup,$err);
}
################################################################
#  buckwalter conversion
#
#  to load the errors as table:
#       run with --no-context
#       open log in emacs and M-x org-mode
#       mark whole buffer
#       C-u C-c |
#   (C-u sets delimiter to ,)
#
#
################################################################
sub convertString {
  my $t = shift;
  my $proctype = shift;
  my $s = $t;
  my ($start,$strLen,$ix);

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
  my $sz = length $t;
  for (my $i=0;$i < $sz;$i++) {
    my $x= substr $t,$i,1;
    if ($x eq (substr $s,$i,1)) {
      #     if ($x !~ /\p{IsPunct}|\p{IsSpace}/) {
      if ($x !~ /\p{IsSpace}/) {
        $conversionErrors++;
        my ($fix,$err) = fixup($s);
        if ($fix && $suppressFixups) {
          #
        }
        writelog($blog,sprintf "%d,%d,%s,%s,%s,%s,%s,%d,%s,%s,%s",
                 $fix,
                 $conversionErrors,
                 $currentNodeId,
                 $currentRoot,
                 $currentWord,
                 $proctype,
                 $err,
                 $i,
                 $x,
                 $s,
                 $t);

      }
    }
  }
  if (! $suppressContext &&  $currentText ) {
    $ix = index $currentText , $s;
    if ($ix != -1) {
      $start = $ix - $textMargin;
      if ($start < 0) {
        $start = 0;
      }
      $strLen = (length $s) + $textMargin;
      if (($ix + $strLen) > (length $currentText)) {
        $strLen = length $currentText;
      }
      writelog($blog,sprintf ">>>\n%s\n<<<\n",(substr $currentText,$start, $strLen));
    }
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
      print $dlog "Node $currentNodeId, <form> with attibutes:\n";
      print $dlog ">>>\n" . $formNode->toString . "\n<<<\n";
    }
    $formWithAttributes++;
    my $n = $attrs->getNamedItem("n");
    if ($n) {
      my $v = $n->getNodeValue;
      if ($v eq "infl") {
        # do something with it?
      } elsif ( $v ) {
        $debug && print $dlog "<form> with non-infl type: $v\n";
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
                  ($currentItype =~ /^\d+$/)) {
                $currentWord = $t;
                $debug && print $dlog ">>> node $currentNodeId: first <orth> promoted to <itype> currentWord : $t\n";
                $itypePromotion++;
                $currentStatus[3] = "i";
              } elsif (! $currentWord ) {
                $currentWord = $t;
                $debug && print $dlog ">>> node $currentNodeId: first <orth> promoted to currentWord : $t\n";
                $orthPromotion++;
                $currentStatus[4] = "o";
              } elsif ($t =~ /^\d+$/) {
                $orthDrop++;
                $currentStatus[6] = "d";
              } elsif (($t ne "*") &&
                       ( $t ne $currentRoot ) &&
                       ( $t ne $currentWord )) {
                push @currentForms, $t;
              }
            }
          }
        } else {
          print $elog "Parse warning 1: <orth> without child nodes\n";
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
######################################################################
#
# $dbh->prepare("insert into entry (root,word,itype,nodeId,bword,xml)
#                       values (?,?,?,?,?,?)");
#
#####################################################################
sub writeEntry {
  my $root = shift;
  my $broot = shift;
  my $word = shift;
  my $itype = shift;
  my $node = shift;
  my $bword = shift;
  my $xml  = shift;

  $debug && print $dlog "ENTRY write: [$root][$broot][$word][$itype][$bword][$node]\n";

  if ($dryRun) {
    $entryDbCount++;
    return;
  }
  $entrysth->bind_param(1,$root);
  $entrysth->bind_param(2,$broot);
  $entrysth->bind_param(3,$word);
  $entrysth->bind_param(4,$itype);
  $entrysth->bind_param(5,$node);
  $entrysth->bind_param(6,$bword);
  $entrysth->bind_param(7,$xml);
  if ($entrysth->execute()) {
    $entryDbCount++;
    $writeCount++;
  } else {
    $dbErrorCount++;
  }
  if ($writeCount > $commitCount) {
    $dbh->commit(); # reports 'commit ineffictive with Autocommit enabled
    $dbh->begin_work();
    $totalWriteCount += $writeCount;
    $writeCount = 0;
  }
}
######################################################################
# $dbh->prepare("insert into xref (word,bword,node) values (?,?,?)")
#
#####################################################################
sub writeXref {
  my $word = shift;
  my $bword = shift;
  my $node = shift;

  $debug && print $dlog "XREF write: [$word][$bword][$node]\n";

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
  } else {
    $dbErrorCount++;
  }
  if ($writeCount > $commitCount) {
    $dbh->commit(); # reports 'commit ineffictive with Autocommit enabled
    $dbh->begin_work();
    $totalWriteCount += $writeCount;
    $writeCount = 0;
  }
}
######################################################################
# $dbh->prepare("insert into root (word,bword,letter) values (?,?,?)");
#
#####################################################################
sub writeRoot {
  my $word = shift;
  my $bword = shift;
  my $letter = shift;

  $debug && print $dlog "ROOT write: [$word][$bword][$letter]\n";

  if ($dryRun) {
    $rootDbCount++;
    return;
  }
  $rootsth->bind_param(1,$word);
  $rootsth->bind_param(2,$bword);
  $rootsth->bind_param(3,$letter);
  if ($rootsth->execute()) {
    $rootDbCount++;
    $writeCount++;
  } else {
    $dbErrorCount++;
  }
  if ($writeCount > $commitCount) {
    $dbh->commit(); # reports 'commit ineffictive with Autocommit enabled
    $dbh->begin_work();
    $totalWriteCount += $writeCount;
    $writeCount = 0;
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
        my $str = convertString($text,$nodeName);
        $textNode->setNodeValue($str);
        #
        # write xref record using: $currentWord,$currentNodeId,$text,$str
        #
        writeXref($str,$text,$currentNodeId);
      }
    } else {
      print $plog "Parse warning 2: node <$nodeName> has lang=ar but no text\n";
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
  $currentText = $node->toString;
  print $plog sprintf "[Root=%s][Entries=%d][TextLength=%d]\n",$currentRoot,$entryCount,length $currentText;
  #
  # write root record ?
  #
  if ($entryCount > 0) {
    writeRoot(convertString($currentRoot,"root"),$currentRoot,$currentLetter);
  }
  for (my $i=0;$i < $entryCount;$i++) {
    my $entry = $entries->item($i);
    $currentText = $entry->toString;
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
        $verbose && print $plog "Root [$currentRoot] skipped, <see supplement> entry\n";
      }
    }
    if (! $skipRoot ) {
      $idAttr = $entry->getAttributeNode("id");
      if ($idAttr) {
        $id = $idAttr->getValue();
      } else {
        $verbose && print $plog "Node has no ID:" . $entry->toString . "\n";
        $id = createId();
        $entry->setAttribute("id",$id);
        $currentStatus[0] = "m";
      }
      $keyAttr = $entry->getAttributeNode("key");
      if ($keyAttr) {
        $key = $keyAttr->getValue();
        if (! $key ) {
          $verbose && print $plog "Node has no key:" . $entry->toString . "\n";
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
          $verbose && print $plog "At node $currentNodeId: change $t -> $currentWord\n";
        } elsif ($currentWord =~ /\d/) {
          $numeric = "n";
          $currentStatus[5] = "n";
        }
        $entry->setAttribute("key",$currentWord);
        my $status = join "",@currentStatus; #$numeric,
        print $plog sprintf "[%03d][%06d][%s]>>> %5s%7s %-30s%-5s %s\n",
          $i,
          length $currentText,
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
              $clone->setAttribute("key",convertString($currentWord,"word"));
              $xml =  $clone->toString;
            }
            else {
              print $elog "Error cloning node for transliteration:$currentNodeId,$currentWord";
            }
            if (! $xml ) {
              $xml = $entry->toString;
            }
          }
          #
          # update db
          #
          writeEntry(convertString($currentRoot,"root"),$currentRoot,
                     convertString($currentWord,"word"),
                     $currentItype,$currentNodeId,$currentWord,$xml);
        }
        else {
          print $plog "Parse warning 3: No node or word\n";
          $genWarning++;
        }
      }
      else {
        print $plog "Parse warning 4: No ID field\n";
        $genWarning++;
      }
    }
  }
}
################################################################
#
#
################################################################
sub openLogs {
  my $filename = shift;

  my ($base,$p,$suffix) = fileparse($filename,'\..*');

  if (! $base ) {
    $base = strftime "%F-%T", localtime $^T;
    $base =~ s/:/-/g;
  }
  if ( ! -d $logDir ) {
    $logDir = ".";
  }
  my $errlog = File::Spec->catfile($logDir,$base . "_err.log");
  my $parselog = File::Spec->catfile($logDir,$base . "_parse.log");
  my $convlog = File::Spec->catfile($logDir,$base . "_conv.log");
  my $debuglog = File::Spec->catfile($logDir,$base . "_debug.log");
  open($blog,">:encoding(UTF8)",$convlog);
  print $blog "Fixed,Error no,Node,Root,Word,Type,Err,Pos,Char,In,Out\n";

  open($plog,">:encoding(UTF8)",$parselog);
  open($elog,">:encoding(UTF8)",$errlog);
  $debug &&  open($dlog,">:encoding(UTF8)",$debuglog);

}
################################################################
#
#
################################################################
sub parseFile {
  my $fileName = shift;
  my $start = time();
#  print STDERR "Parsing file: $fileName\n";

  openLogs($fileName);
  my $parser = new XML::DOM::Parser;
  my $doc = $parser->parsefile ($fileName);

  # print all HREF attributes of all CODEBASE elements
  my $nodes = $doc->getElementsByTagName ("div1");
  my $n = $nodes->getLength;

  for (my $i = 0; $i < $n; $i++) {

    my $div1Node = $nodes->item($i);
    $currentText = $div1Node->toString;
    my $attr = $div1Node->getAttributeNode("type");
    if ($attr && ($attr->getValue =~ /alphabetical\s+letter/i)) {
      $attr = $div1Node->getAttributeNode("n");
      if ($attr) {
        $currentLetter = $attr->getValue;
      }
    }
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
  if ( ! $dryRun ) {
    $dbh->commit();
  }

  my $end = time();
  $elapsedTime = $end - $start;
  print $plog "\n";
  print $plog sprintf "Skip root count         : %d\n",$skipRootCount;
  print $plog sprintf "<entryFree> without key : %d\n",$entryFreeWithoutKey;
  print $plog sprintf "<entryFree> without id  : %d\n",$entryFreeWithoutId;
  print $plog sprintf "Itype promotion         : %d\n",$itypePromotion;
  print $plog sprintf "Orth promotion          : %d\n",$orthPromotion;
  print $plog sprintf "Orth drop               : %d\n",$orthDrop;
  print $plog sprintf "General warning         : %d\n",$genWarning;
  print $plog sprintf "Xref count              : %d\n",$xrefDbCount;
  print $plog sprintf "Root count              : %d\n",$rootDbCount;
  print $plog sprintf "Entry count             : %d\n",$entryDbCount;
  print $plog sprintf "Elapse time             : %.2f\n", $elapsedTime;
  if ( ! $dryRun ) {
    print $plog sprintf "DB write count          : %d\n", $totalWriteCount;
  }
  print $plog sprintf "Conversion Errors       : %d\n",$conversionErrors;
  print $plog sprintf "Adjusted conversions    : %d\n",$adjustedConversions;

  close $plog;
  close $elog;
  close $blog;
  $debug && close $dlog;
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
    return;
  }

  foreach my $h (@totals) {
      print STDOUT sprintf "%30s %10d %10d %10d\n",
        $h->{File},
        $h->{"Root count"},
        $h->{"Entry count"},
        $h->{"Xref count"};
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
bword text,
letter text,
xml text
);
create TABLE itype (
id integer primary key,
itype integer,
root text,
broot text,
nodeId text,
word text,
xml text
);
create TABLE entry (
id integer primary key,
root text,
broot text,
word text,
itype text,
nodeId text,
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
  $dbh->{AutoCommit} = 1;
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
   $verbose && print STDERR "DB initialised OK\n";
  }
  $dbh->disconnect;
}
################################################################
# these two subroutines traverse the node converting all text
# nodes whose parent has lang="ar"
#
################################################################
sub setLinksForNode {
  my $node = shift;
  my $nodeName;
  my $parentName;
  my $skip = 0;

  $nodeName =  $node->getNodeName;
  my $parentNode = $node->getParentNode;

  # going to skip entyfree and any child nodes of <form>
  if ($nodeName eq "entryfree") {
    $skip = 1;
  }
  while($parentNode && ! $skip) {
    $parentName = $parentNode->getNodeName;
    if ($parentName eq "form") {
      $skip = 1;
    }
    $parentNode = $parentNode->getParentNode;
  }
  print STDERR sprintf "[%d]<%s><%s>\n",$skip,$parentName,$nodeName;
  return unless ! $skip;
  #  print "$nodeName\n";
  my $attr = $node->getAttributeNode("lang");
  if ($attr && ($attr->getValue eq "ar")) {
    if ($node->hasChildNodes) {
      my $textNode = $node->getFirstChild;
      if ($textNode->getNodeType == TEXT_NODE) {
        my $text = $textNode->getNodeValue;
        ## lookup the word
        $text = convertString($text);
        $lookupsth->bind_param(1,$text);
        my $ret = $lookupsth->execute();
        print STDERR "Lookup:[$text]\n";
        if ($ret) {
          my ($id,$bword,$nodeId) = $lookupsth->fetchrow_array;
          if ($id) {
            print STDERR "Found at [$id][$bword][$nodeId]\n";
            # wrap entry in <a href="#$id">...</text>
            # and update xml
          } else {
            $dlookupsth->bind_param(1,$text);
            $text .= chr(0x64c);
            print STDERR "Lookup:[$text]\n";
            $dlookupsth->bind_param(2,$text);
            if ($dlookupsth->execute()) {
              ($id,$bword,$nodeId) = $dlookupsth->fetchrow_array;
              if ($id) {
                print STDERR "Found at [$id][$bword][$nodeId]\n";
                # wrap entry in <a href="#$id">...</text>
                # and update xml
              }
            }
          }
          #
          #
          #
          if ($id) {
            print STDERR "Insert link to record id=$id\n";
          }
        }
      } else {
        print $plog "Parse warning 2: node <$nodeName> has lang=ar but no text\n";
        $genWarning++;
      }
    }
  }
}
################################################################
#
#
################################################################
sub traverseNodeForLinks {
  my $node = shift;

  while ($node) {
    if ($node->getNodeType == ELEMENT_NODE) {
      setLinksForNode($node);
    }
    if ($node->hasChildNodes) {
      traverseNodeForLinks($node->getFirstChild);
    }
    $node = $node->getNextSibling;
  }
}
#############################################################
#
#
############################################################
sub setLinks {
  my $sth;
  my $parser = new XML::DOM::Parser;

  $writeCount = 0;
  $sth = $dbh->prepare("select * from entry");
  my $entries = $dbh->selectall_arrayref("SELECT id,root,broot,word,bword,nodeId,xml from entry where id < 10");
  foreach my $row (@$entries) {
    my ($id, $root,$broot,$word,$bword,$node,$xml) = @$row;
    print STDERR "$bword\n";
#    print STDERR "$xml";
    my $doc = $parser->parse($xml);
    my $nodes = $doc->getElementsByTagName ("entryFree");
    my $n = $nodes->getLength;
    print STDERR "Nodes : $n\n";
    for (my $i = 0; $i < $n; $i++) {
       my $node = $nodes->item($i);
       traverseNodeForLinks($node);

    }
  }


}
sub testlink {

  my $xml = <<'END';
<entryFree id="n4889" key="juw^o$uw$N" type="main">
   <form>
                     <orth orig="" extent="full" lang="ar">juw^o$uw$N</orth>
                     <orth extent="full" lang="ar">*</orth>
                  </form> The <hi rend="ital" TEIform="hi">breast,</hi> or <hi rend="ital" TEIform="hi">chest;</hi> (S, A, K;) as also ↓
      <orth type="arrow" lang="ar">jaA^o$N</orth> and ↓
      <orth type="arrow" lang="ar">juw^o$N</orth>: (A:) or <hi rend="ital" TEIform="hi">its</hi>
                  <foreign lang="ar" TEIform="foreign">Hayozuwm</foreign>, q. v. (Ibn-'Abbád, K.) ―         -b2-  The <hi rend="ital" TEIform="hi">forepart</hi> (<foreign lang="ar" TEIform="foreign">Sador</foreign>) of the night; accord. to which explanation it is tropical: or <hi rend="ital" TEIform="hi">what is between the beginning and the third</hi> thereof: or <hi rend="ital" TEIform="hi">a while</hi> thereof: (TA:) or <hi rend="ital" TEIform="hi">a portion</hi> thereof; (Lh, K;) and of people. (K.)       -A2-  Also A <hi rend="ital" TEIform="hi">thick,</hi> or <hi rend="ital" TEIform="hi">gross,</hi> or <hi rend="ital" TEIform="hi">coarse,</hi> man. (Ibn- 'Abbád, K.)   </entryFree>
END

  openDb("latest.sqlite");
  #
  # this doesn't catch the errors, so if file exists and tables are not right it will crash
  #
  eval {
    $xrefsth = $dbh->prepare("insert into xref (word,bword,node) values (?,?,?)");
    $entrysth = $dbh->prepare("insert into entry (root,broot,word,itype,nodeId,bword,xml) values (?,?,?,?,?,?,?)");
    $rootsth = $dbh->prepare("insert into root (word,bword,letter) values (?,?,?)");
    $lookupsth = $dbh->prepare("select id,bword,nodeId from entry where word = ?");
    $dlookupsth = $dbh->prepare("select id,bword,nodeId from entry where word = ? or word = ?");
  };
  if ($@) {
    print STDERR "SQL prepare error:$@\n";
    print STDERR "DB updates disabled\n";
    $dryRun = 1;
  }

  my $parser = new XML::DOM::Parser;
  my $doc = $parser->parse($xml);

    my $nodes = $doc->getElementsByTagName ("entryFree");
    my $n = $nodes->getLength;
    print STDERR "Nodes : $n\n";
    for (my $i = 0; $i < $n; $i++) {
       my $node = $nodes->item($i);
       traverseNodeForLinks($node);

    }

}
#############################################################
#
#
############################################################
sub testErrs {
  my @words = qw(jadoYBN jub~aA'N? A_ilaY *aAti raHolK kaA@lomaA=timi Hus~araA 1a2u3a);
  foreach my $word (@words) {
    my $e = testConvertString($word);
    print $word . "\n";
    print $e->{err} . "\n";
    print $e->{count} . "\n";
    print join ",",@{$e->{indexes}};
    print "\n";
  }
}
sub runTest {
  my $fn = shift;

  my %tests = ( errs => \&testErrs,
                xml =>  sub { $dryRun = 1;parseFile("./test/test_j0.xml");},
                logs => sub { openLogs("./xml/j0.xml"); },
                dir  => sub { $dryRun = 1;parseDirectory("./testdir");},
                link => sub { testlink();}
              );

  if (exists $tests{$fn} ) {
    $tests{$fn}->();
  }
  else {
    print STDERR "Unknown test routine: $fn\n";
  }
  exit 0;
}
#############################################################
#
# MAIN
#
############################################################

if ($doTest) {
  runTest($doTest);
}
my $sql;
if ($sqlSource) {
  # get SQL source from file
}
else {
  $sql = getSQL();
}
if ($initdb) {
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
  if ( ! $dbname ) {
    print STDERR "No database name supplied\n";
    exit 1;
  }
  if ( ! -e $dbname ) {
    initialiseDb($dbname,$sql);
  }
  openDb($dbname);
  #
  # this doesn't catch the errors, so if file exists and tables are not right it will crash
  #
  eval {
    $xrefsth = $dbh->prepare("insert into xref (word,bword,node) values (?,?,?)");
    $entrysth = $dbh->prepare("insert into entry (root,broot,word,itype,nodeId,bword,xml) values (?,?,?,?,?,?,?)");
    $rootsth = $dbh->prepare("insert into root (word,bword,letter) values (?,?,?)");
    $lookupsth = $dbh->prepare("select id,bword,nodeId from entry where word = ?");
  };
  if ($@) {
    print STDERR "SQL prepare error:$@\n";
    print STDERR "DB updates disabled\n";
    $dryRun = 1;
  }
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
elsif ($linksMode) {
 setLinks() ;
}
#convertString("ja Oxdr sthwmn");

#open $blog,">x.log";

#parseFile("./xml/j0.xml");

#parseDirectory("./xml");
