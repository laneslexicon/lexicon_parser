#!/usr/bin/perl -w
use strict;
use POSIX;
use XML::LibXML;
#use XML::Parser;
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
my $plog;                       # parse log for diagnostic output;
my $elog;                       # error log
my $dlog;
my $llog;                       # links log
#
# cmd line args
#
my $verbose = 0;
my $initdb  = 0;
my $xmlFile = "";
my $parseDir = "";
my $commitCount = 5000;
my $sqlSource = "";
my $skipConvert = 0;
my $debug = 0;
my $dbname;
my $overwrite = 0;              # overwrite existing db
my $dryRun = 0;                 # no db update
my $textMargin = 30;
my $suppressFixups = 0;
my $suppressContext = 0;
my $doTest = "";
my $logDir = "/tmp";
my $linksMode = 0;
my $convertMode = 0;
my $tagsMode = 0;
my $arrowMode = 0;
my $logbase = "";               # forms part of the log file name
my $linkletter = ""; # just set links for words whose root begins with this letter

my %tags;
#
#   --dbname latest.sqlite --scan-arrows
#          prints <orth type="arrow" lang="ar">...</orth> values
#
GetOptions (
            "logbase=s" => \$logbase,
            "scan-arrows" => \$arrowMode,
            "scan-tags" => \$tagsMode,
            "set-links" => \$linksMode,
            "letter=s" => \$linkletter,
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
            "margin=i" => \$textMargin, # before & after text length to include in conversion error
            "xml=s" => \$xmlFile,       # file to parse
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
my $entryFreeWithoutIdGlobal = 0;
my $orthPromotion=0;
my $orthDrop = 0;
my $itypePromotion=0;
my $skipRootCount = 0;
my $xrefDbCount = 0;
my $entryDbCount = 0;
my $rootDbCount = 0;
my $alternateDbCount = 0;
my $genWarning = 0;
my $elapsedTime = 0;
my $conversionErrors = 0;
my $adjustedConversions = 0;
my $linkCount = 0;
my $arrowsCount = 0;
my $unresolvedArrows = 0;
#
my $dbh = 0;
my $writeCount = 0;
my $totalWriteCount = 0;
my $dbupdate = 1;               # set to 0 to prevent db writes
my $dbErrorCount = 0;
my $xrefsth;
my $entrysth;
my $rootsth;
my $alternatesth;
my $lookupsth;  # for 'select id from entry where word = ?
my $updateNode; # set links uses to check if the node xml needs saving
#

my $currentNodeId;
my $lastNodeId;
my $currentRoot;
my $currentBRoot;
my $currentWord;
my $currentBWord;
my $currentItype;
my $currentLetter;
my @currentForms;
my @currentStatus;
my $currentRecordId;
my $currentText;
my $currentPage = 1;
my $currentRootPage = 1;
my @links;
my $supplement;
my $currentFile;

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
      if ($x !~ /\(|\)|\p{IsSpace}/) {
        $errStr .= "x";
        push @indexes,$i;
      } else {
        $errStr .= "-";
      }
    } else {
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
#  NOTHING GETS FIXED HERE
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
  # if ($s =~ /3a/) {
  #   $err = "3 for h";
  #   $fixup++;
  # }
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



  $t =~ s/^\s+//;
  $t =~ s/\s+$//;
  # so we don't report this type of stuff:
  # <entryFree id="n6619" key="10" type="main">
  #             <form>
  #                <itype>10</itype>
  #                <orth orig="" extent="full" lang="ar">AstjAb</orth>
  #                <orth extent="full" lang="ar">10</orth> and
  # <orth orig="" extent="full" lang="ar">Aisotajowaba</orth>
  #             </form>, inf. n. <fo
  #
  # which should be fixed by the itype promotion routines
  #
  if ($t =~ /^\d+$/) {
    return $t;
  }
  return $t unless ! $skipConvert;
  if ($proctype ne "link") {
    if ($t =~ /\?\?/) {
      writelog($blog,sprintf "2,%s,%s,%s,%d", $currentRoot,$currentWord,$currentNodeId,$currentPage);
      return $t;
    }
    # convert all A@ to L
    if ($t =~ /A@/) {
      writelog($blog,sprintf "4,%s,%s,%s,%s,%s,%d", $proctype,$currentRoot,$currentWord,$currentNodeId,$t,$currentPage);
      $t =~ s/A@/L/g;
    }
    # get rid of the &,
    # this might need fixing properly
    # may when proctype = "word" or "root" we can strip it out
    #

    if ($t =~ /&/) {
      writelog($blog,sprintf "3,%s,%s,%s,%s,%s,%d", $proctype,$currentRoot,$currentWord,$currentNodeId,$t,$currentPage);
      if ($proctype eq "alternateroot") {
        $t =~ s/&c\.*/ /g;
      }
    }
  }
  #  $t =~ s/&amp;c/ /g);
  my $c = 0;
  $c += ($t =~ tr/'|OWI}A/\x{621}\x{622}\x{623}\x{624}\x{625}\x{626}\x{627}/);
  $c += ($t =~ tr/bptvjHx/\x{628}\x{629}\x{62a}\x{62b}\x{62c}\x{62d}\x{62e}/);
  $c += ($t =~ tr/d*rzs$S/\x{62f}\x{630}\x{631}\x{632}\x{633}\x{634}\x{635}/);
  $c += ($t =~ tr/DTZEg\-f/\x{636}\x{637}\x{638}\x{639}\x{63a}\x{640}\x{641}/);
  $c += ($t =~ tr/qklmnhw/\x{642}\x{643}\x{644}\x{645}\x{646}\x{657}\x{648}/);
  $c += ($t =~ tr/YyFNKau/\x{649}\x{64a}\x{64b}\x{64c}\x{64d}\x{64e}\x{64f}/);
  # check ` for alef wasla - is this right
  $c += ($t =~ tr/i~o`{/\x{650}\x{651}\x{652}\x{670}\x{671}/);


  # ^ as hamza above
  # = alef with madda above (in buckwalter docs is |)
  # _ tatweel , also - above
  # L alef wasla
  $c += ($t =~ tr/^=_L/\x{654}\x{622}\x{640}\x{0671}/);

  # count the spaces etc
  my $r = $t;
  my $spaces = ($r =~ s/ / /g);
  my $sz = length $t;
  my $j = 0;


  for (my $i=0;$i < $sz;$i++) {
    my $x= substr $t,$i,1;
    if ( $x eq (substr $s,$i,1)) {
      #     if ($x !~ /\p{IsPunct}|\p{IsSpace}/) {
      if ($x !~ /\p{IsSpace}|;|,|\./) {
        $j++;
        #        my ($fix,$err) = fixup($s);
        #        if ($fix && $suppressFixups) {
        #        }
        my $fix = 0;
        my $err = " ";
        # we have already parsed the node and written an error record
        if (($proctype ne "word") && ($proctype ne "link")) {
          writelog($blog,sprintf "%d,%d,%d,%s,%s,%s,%s,%s,%s,%d,%s,%s,%d",
                   $fix,
                   $conversionErrors,
                   $j,
                   $x,
                   $currentNodeId,
                   $currentRoot,
                   $currentWord,
                   $proctype,
                   $err,
                   $i,
                   $s,
                   $t,
                   $currentPage);

        }
      }
    }
  }
  if ($j > 0) {
    $conversionErrors++;

    my ($start,$end,$strLen,$ix);
    if (! $suppressContext &&  $currentText ) {
      $ix = index $currentText , $s;
      if ($ix != -1) {
        my $context = "";
        my $count = 0;
        for ($start=$ix - 1;($start > 0) && ($count < $textMargin);$start--) {
          if (substr($currentText,$start,1) ne " ") {
            $count++;
          }
        }
        $strLen = length $s;
        my $max = length $currentText;
        $count = 0;
        for ($end=$ix + $strLen + 1;($end < $max) && ($count < $textMargin);$end++) {
          if (substr($currentText,$end,1) ne " ") {
            $count++;
          }
        }

        # $start = $ix - $textMargin;
        # if ($start < 0) {
        #   $start = 0;
        # }
        # $strLen = (length $s) + $textMargin;
        # if (($ix + $strLen) > (length $currentText)) {
        #   $strLen = length $currentText;
        # }
        if (($proctype ne "word") && ($proctype ne "link")) {
          writelog($blog,sprintf ">>>\n%s\n<<<\n",(substr $currentText,$start, $end - $start));
        }
      }
    }
  }
  return $t;
}
#
# all id values are n\d+ so we call ours m\d+
#
sub createId {
  $entryFreeWithoutId++;
  $entryFreeWithoutIdGlobal++;
  return sprintf "m%05d",$entryFreeWithoutIdGlobal;
}
##############################################################
#
# problem here is that we do not add the imperfect prefix
#
# change to use FE77 for fatha on top horizontal line
#               FE70 for damma
#               FE7B for kasra
#
#############################################################
sub convertVowelling {
  my $root = shift;
  my $word = shift;
  my $type = shift;
  my @n;

  # type 0 or 1 means the call is coming from convertNode
  # type 2 it is from processRoot
  # if $type = 1 , the node has orth="Bu" or "Ba" or "Bi"
  #     type = 0   no such attribute
  # failure to convert type 1 should not be a problem as these are embedded in the xml and
  # have "marker" attribute set
  #
  my $ok = 0;
  my $rz = length $root;
  my $wz = length $word;
  for (my $i=0;$i < $wz;$i++) {
    my $x= substr $word,$i,1;
    if ($x =~ /1|2|3/) {
      my $ix = int($x);
      if ($ix > $rz) {
        # doubled roots ?
        if (($ix == 3) && ($rz == 2)) {
          push @n,substr($root,1,1);
        } else {
          $ok = 1;
          push @n,$x;
        }
      } else {
        push @n,substr($root,$ix - 1,1);
      }
    } else {
      push @n,$x;
    }
  }
  $debug && print $dlog sprintf "vowelling: %d,%d,%s,%s ,%s\n",$ok,$type,$root,$word,join "",@n;
  return join "",@n;

}
################################################################
#
#
################################################################
sub processForm {
  my $formNode = shift;
  my $name;


  my @attrs = $formNode->attributes;
  if ($#attrs > 0) {
    if ($debug) {
      print $dlog "Node $currentNodeId, <form> with attibutes:\n";
      print $dlog ">>>\n" . $formNode->toString . "\n<<<\n";
    }
    $formWithAttributes++;
    for (my $i=0;$i < $#attrs;$i++) {
      my $n = $attrs[$i];
      if ($n->nodeName eq "n") {
        my $v = $n->nodeValue;
        if ($v eq "infl") {
          # do something with it?
        } elsif ( $v ) {
          $debug && print $dlog "<form> with non-infl type: $v\n";
        }
      }
    }
  }
  my $child = $formNode->getFirstChild;
  while ($child) {
    #    print "\t\t" . $child->nodeName . "\n";
    if ($child->nodeType == XML_ELEMENT_NODE) {
      $name = $child->nodeName;
      if ($name eq "itype") {
        my $textNode = $child->getFirstChild;
        if ($textNode->nodeType == XML_TEXT_NODE) {
          my $t = $textNode->nodeValue;
          if ($t) {
            $currentItype = $t;
          }
        }
      } elsif ($name eq "orth") {
        if ($child->hasChildNodes) {
          my $textNode = $child->getFirstChild;
          if ($textNode->nodeType == XML_TEXT_NODE) {
            my $t = $textNode->nodeValue;
            #            print STDERR "Checking orth/itype ---->[$currentWord][$currentItype][$t]\n";
            if ($t) {
              # this seems to be where key is the same as the numeric itype value
              if (
                  (! $currentWord || ($currentWord =~ /^\s*\d+\s*$/)) &&
                  ($currentItype =~ /^\d+$/)) {
                $t =~ s/A@/L/g;
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

  $nodeName =  $node->nodeName;
  if ($nodeName eq "form") {
    processForm($node);
  } elsif ($node->nodeName eq "pb") {
    my $pageAttr = $node->getAttributeNode("n");
    if ($pageAttr) {
      $currentPage = $pageAttr->getValue();
    }
  }
  # elsif ($node->nodeName eq "orth") {
  #   my $origAttr = $node->getAttributeNode("orig");
  #   if ($origAttr) {
  #     my $t = $origAttr->getValue();
  #     if ($t =~ /Bu|Ba|Bi/) {
  #       my $textNode = $node->getFirstChild;
  #       if ($textNode->nodeType == XML_TEXT_NODE) {
  #         my $text = $textNode->nodeValue;
  #         if ($text && ($text =~ /\d/)) {
  #           print STDERR "$currentFile : $currentNodeId :$currentRoot : $t : $text\n";
  #         }
  #       }
  #     }
  #   }
  # }

}
################################################################
#
#
################################################################
sub traverseNode {
  my $node = shift;

  while ($node) {
    if ($node->nodeType == XML_ELEMENT_NODE) {
      if ($arrowMode) {
        checkArrow($node);
      } elsif ($tagsMode) {
        analyzeTags($node);
      } elsif ($linksMode) {
        setLinksForNode($node);
      } elsif ($convertMode) {
        convertNode($node);
      } else {
        processNode($node);
      }
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
  $entrysth->bind_param(8,$supplement);
  $entrysth->bind_param(9,$currentFile);
  $entrysth->bind_param(10,$currentPage);

  if ($entrysth->execute()) {
    $entryDbCount++;
    $writeCount++;
  } else {
    $dbErrorCount++;
  }
  if ($writeCount > $commitCount) {
    $dbh->commit(); # reports 'commit ineffictive with Autocommit enabled
    #    $dbh->begin_work();
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
  $xrefsth->bind_param(4,$currentPage);
  if ($xrefsth->execute()) {
    $xrefDbCount++;
    $writeCount++;
  } else {
    $dbErrorCount++;
  }
  if ($writeCount > $commitCount) {
    $dbh->commit(); # reports 'commit ineffictive with Autocommit enabled
    #    $dbh->begin_work();
    $totalWriteCount += $writeCount;
    $writeCount = 0;
  }
}
######################################################################
# $dbh->prepare("insert into root (word,bword,letter,bletter) values (?,?,?)");
#
#####################################################################
sub writeRoot {
  my $word = shift;
  my $bword = shift;
  my $bletter = shift;
  my $quasi = shift;
  my $alternates = shift;
  my $letter = convertString($bletter,"letter");
  $debug && print $dlog "ROOT write: [$word][$bword][$letter][$bletter][$quasi][$alternates][$currentRootPage]\n";

  if ($dryRun) {
    $rootDbCount++;
    return;
  }
  $rootsth->bind_param(1,$word);
  $rootsth->bind_param(2,$bword);
  $rootsth->bind_param(3,$letter);
  $rootsth->bind_param(4,$bletter);
  $rootsth->bind_param(5,$supplement);
  $rootsth->bind_param(6,$quasi);
  $rootsth->bind_param(7,$alternates);
  $rootsth->bind_param(8,$currentRootPage);
  if ($rootsth->execute()) {
    $rootDbCount++;
    $writeCount++;
  } else {
    $dbErrorCount++;
  }
  if ($writeCount > $commitCount) {
    $dbh->commit(); # reports 'commit ineffictive with Autocommit enabled
    #    $dbh->begin_work();
    $totalWriteCount += $writeCount;
    $writeCount = 0;
  }
  # the root may have started on a different page so once we have written the root header
  # we can update the page
  $currentRootPage = $currentPage;
}
######################################################################
# $dbh->prepare("insert into root (word,bword,letter,bletter) values (?,?,?)");
#
#####################################################################
sub writeAlternate {
  my $word = shift;
  my $bword = shift;
  my $bletter = shift;
  my $quasi = shift;
  my $rootId = shift;
  my $letter = convertString($bletter,"letter");
  $debug && print $dlog "ALTERNATE write: [$word][$bword][$letter][$bletter][$quasi][$rootId]\n";

  if ($dryRun) {
    $alternateDbCount++;
    return;
  }
  $alternatesth->bind_param(1,$word);
  $alternatesth->bind_param(2,$bword);
  $alternatesth->bind_param(3,$letter);
  $alternatesth->bind_param(4,$bletter);
  $alternatesth->bind_param(5,$supplement);
  $alternatesth->bind_param(6,$quasi);
  $alternatesth->bind_param(7,$rootId);
  if ($alternatesth->execute()) {
    $alternateDbCount++;
    $writeCount++;
  } else {
    $dbErrorCount++;
  }
  if ($writeCount > $commitCount) {
    $dbh->commit(); # reports 'commit ineffictive with Autocommit enabled
    #    $dbh->begin_work();
    $totalWriteCount += $writeCount;
    $writeCount = 0;
  }
}
################################################################
# these two subroutines traverse the node converting all text
# nodes whose parent has lang="ar"
#
#
# For <orth orig="Bu|Bi|Ba"> which have a 1,2 or 3 in them have an
# attribute added:
#    marker="original text"
#
#  and the vowelling is converted
#
################################################################
sub convertNode {
  my $node = shift;
  my $nodeName;

  my $infl = 0;
  $nodeName =  $node->nodeName;
  #
  # check if this a voweling type node like this:
  #    <form n="infl">
  #                   <orth orig="Bu" lang="ar">matu3a</orth>
  #
  #
  if ($node->nodeName eq "pb") {
    my $pageAttr = $node->getAttributeNode("n");
    if ($pageAttr) {
      $currentPage = $pageAttr->getValue();
    }
  }

  if ($nodeName eq "orth") {
    my $origAttr = $node->getAttributeNode("orig");
    if ($origAttr) {
      my $t = $origAttr->getValue();
      if ($t =~ /Bu|Ba|Bi/) {
        my $textNode = $node->getFirstChild;
        if ($textNode->nodeType == XML_TEXT_NODE) {
          my $text = $textNode->nodeValue;
          if ($text && ($text =~ /\d/)) {
            $debug && print $dlog "$currentFile : $currentNodeId :$currentRoot : $t : $text inflection marker";
            $infl = 1;
          }
        }
      }
    }
  }
  #  print "$nodeName\n";
  my $attr = $node->getAttributeNode("lang");
  if ($attr && ($attr->getValue eq "ar")) {
    if ($node->hasChildNodes) {
      my $textNode = $node->getFirstChild;
      if ($textNode->nodeType == XML_TEXT_NODE) {
        my $text = $textNode->nodeValue;
        # some items with vowelling marked do not have the Bu,Bi,Ba as above
        if ($text =~ /[0456789]/) {
          print $plog sprintf "%s : Error number in text %s : \n>>\n%s\n<<\n",$nodeName,$text,$node->toString;
          #          print STDERR sprintf "%s : Error number in text %s : \n>>\n%s\n<<\n",$nodeName,$text,$node->toString;
        } elsif ($text =~ /1|2|3/) {
          if ($infl) {
            $node->setAttribute("marker",$text);
          } else {
            $node->setAttribute("marker","none");
          }
          $text = convertVowelling($currentRoot,$text,$infl);
        }
        my $str = convertString($text,$nodeName);
        $textNode->setData($str);
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
sub processRoot {
  my $node = shift;
  my $entries = $node->getElementsByTagName("entryFree");
  my $entryCount = $entries->size();
  my $idAttr;
  my $keyAttr;
  my $key;
  my $skipRoot;
  my $quasiRoot = 0;
  my @alternates;
  $currentText = $node->toString;

  if ($currentRoot =~ /^Quasi/i) {
    $quasiRoot = 1;
    $currentRoot =~ s/^Quasi\s*//;

  }
  # d0.xml line 12032 has; (dmw or dmY) , V3 82/916
  if ($currentRoot =~ /^\(.+\)$/) {
    $currentRoot =~ s/^\(//;
    $currentRoot =~ s/\)$//;

  }
  # some of the Quasi entries have : Quasi xxxx:
  $currentRoot =~ s/:/ /g;
  # this is for t0.xml
  #   <div2 n="Quasi tqY: or, accord. to some, tqw" type="root" org="uniform"
  #
  if ($currentRoot =~ /accord\. to some/) {
    $currentRoot =~ "tqY and tqw";
  }
  #
  # do multiword roots which are in these forms
  #     xxxx yyyy zzzz
  #     xxxx and yyyy
  #     xxxx or yyyy
  #
  $currentRoot =~ s/\s+and\s+/ /g;
  $currentRoot =~ s/\s+or\s+/ /g;
  @alternates = split(/ {1,}/, $currentRoot);
  $currentRoot = shift @alternates;
  print $plog sprintf "[Root=%s][Quasi=%d][Entries=%d][Alternates=%d][TextLength=%d]\n",$currentRoot,$quasiRoot,$entryCount,scalar(@alternates),length $currentText;
  #
  # write root record ?
  #
  if ($entryCount > 0) {
    writeRoot(convertString($currentRoot,"root"),$currentRoot,$currentLetter,$quasiRoot,scalar(@alternates));
    if (scalar(@alternates) > 0) {
      my $id = $dbh->func('last_insert_rowid');
      foreach my $word (@alternates) {
        writeAlternate(convertString($word,"alternateroot"),$word,$currentLetter,$quasiRoot,$id);
      }
    }
  }
  for (my $i=0;$i < $entryCount;$i++) {
    my $entry = $entries->item($i);
    $currentText = $entry->toString;
    #    print sprintf "Processing entryFree %d [ %s  ]\n",$i,$entry->nodeName;
    my $id;
    my $key;
    my $ar_key;
    $skipRoot = 0;

    $currentWord = "";
    $currentNodeId = "";
    $currentItype = "";
    $#currentForms = -1;
    $#currentStatus = -1;
    for (my $j=0;$j < 7;$j++) {
      push @currentStatus,"-";
    }
    my $textNode = $entry->getFirstChild;
    if ($textNode->nodeType == XML_TEXT_NODE) {
      my $text = $textNode->nodeValue;
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
        if ( $lastNodeId ) {
          $id = sprintf "%s-%d",$lastNodeId,$i;
        } else {
          $id = createId();
          print STDERR "Created nodeId $id\n";
        }
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
        # alef wasla
        $currentWord =~ s/A@/L/g;
      }
      if ($id ) {
        $currentNodeId = $id;
        $convertMode = 0;
        traverseNode($entry->getFirstChild);
        my $numeric = " ";
        # these indicate vowelling on the root letters
        if ($currentWord =~ /1|2|3/) {
          my $t = $currentWord;
          $currentWord = convertVowelling($currentRoot,$currentWord,2);
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
          #          if (! $skipConvert ) {
          my $clone = $entry->cloneNode(1);
          if ($clone->nodeType == XML_ELEMENT_NODE) {
            $convertMode = 1;
            traverseNode($clone);
            $clone->setAttribute("key",convertString($currentWord,"word"));
            $xml =  $clone->toString;
          } else {
            print $elog "Error cloning node for transliteration:$currentNodeId,$currentWord";
          }
          if (! $xml ) {
            $xml = $entry->toString;
          }
          #          }
          #
          # update db
          #
          writeEntry(convertString($currentRoot,"root"),$currentRoot,
                     convertString($currentWord,"word"),
                     $currentItype,$currentNodeId,$currentWord,$xml);
          $lastNodeId = $currentNodeId;
        } else {
          print $plog "Parse warning 3: No node or word\n";
          $genWarning++;
        }
      } else {
        print $plog "Parse warning 4: No ID field\n";
        $genWarning++;
      }
    }
  }
}
sub getLogBase {
  my $filename = shift;
  my ($base,$p,$suffix) = fileparse($filename,'\..*');

  $currentFile = $base;
  # if (! $base ) {
  #   $base = strftime "%F-%T", localtime $^T;
  #   $base =~ s/:/-/g;
  # }
  if ( ! -d $logDir ) {
    $logDir = ".";
  }
  if (! $logbase ) {
    my $dt = POSIX::strftime "%y%m%d", localtime;
    $base = $dt . "_" . $base;
  } else {
    $base = $logbase . "_" . $base;
  }
  return $base;
}
################################################################
# opens all the log files in format <dir>/yymmdd_x_{err,parse}.log
#
#
################################################################
sub openLogs {
  my $filename = shift;


  my $base = getLogBase($filename);
  my $errlog = File::Spec->catfile($logDir,$base . "_err.log");
  my $parselog = File::Spec->catfile($logDir,$base . "_parse.log");
  my $convlog = File::Spec->catfile($logDir,$base . "_conv.log");
  my $debuglog = File::Spec->catfile($logDir,$base . "_debug.log");
  #  my $itypelog = File::Spec->catfile($logDir,$base . "_itype.log");


  open($blog,">:encoding(UTF8)",$convlog);
  print $blog "Fixed,Error no,Node,Root,Word,Type,Err,Pos,Char,In,Out,Page\n";

  open($plog,">:encoding(UTF8)",$parselog);
  open($elog,">:encoding(UTF8)",$errlog);
  #  open($ilog,">:encoding(UTF8)",$itypelog);

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
  my $parser = XML::LibXML->new;

  if ($fileName =~ /1\.xml/) {
    $supplement = 1;
  } else {
    $supplement = 0;
  }
  # this is written in entry record
  my ($base,$p,$suffix) = fileparse($fileName,'\..*');
  $currentFile = $base;

  openLogs($fileName);
  #  my $parser = new XML::DOM::Parser;
  my $doc = $parser->parse_file ($fileName);

  # print all HREF attributes of all CODEBASE elements
  my $nodes = $doc->getElementsByTagName ("div1");
  my $n = $nodes->size();

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
    my $rootCount = $roots->size();
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

  #  $doc->dispose;
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
bletter text,
xml text,
supplement integer,
quasi integer,
alternates integer,
page integer
);
create TABLE alternate (
id integer primary key,
word text,
bword text,
letter text,
bletter text,
xml text,
supplement integer,
quasi integer,
alternate integer
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
bword text,
itype text,
nodeId text,
xml text,
supplement integer,
file text,
page integer
);
create index 'word_index' on entry (word asc);
create index 'broot_index' on entry (broot asc);
create index 'root_index' on entry (root asc);
CREATE TABLE xref (
id INTEGER primary key,
word TEXT,
bword text,
node TEXT,
type INTEGER,
page integer
);
COMMIT;
EOF
}
################################################################
#
#  we only know page breaks, not page numbers so the first records
#  in root,entry and xref will have page number = 1, so we find the
#  first root with a proper page number and set the entries to that
#  page - 1
#
#  There is no actual page 1
################################################################
sub fixupPages {

  return unless ! $dryRun;

  my $sth = $dbh->prepare("select id,page from root where page != 1 limit 1");
  $sth->execute();
  my ($id,$page) = $sth->fetchrow_array();
  if ($page =~ /\d+/) {
    $page--;
    $sth = $dbh->prepare("update root set page = $page where page = 1");
    $sth->execute();
    $sth = $dbh->prepare("update xref set page = $page where page = 1");
    $sth->execute();
    $sth = $dbh->prepare("update entry set page = $page where page = 1");
    $sth->execute();
    $dbh->commit();
  }
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
  } else {
    $verbose && print STDERR "Opened db $db\n";
  }
  $dbh->{AutoCommit} = 0;
  #  $dbh->begin_work;
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
#
#
################################################################
sub analyzeTags {
  my $node = shift;
  my $nodeName;

  my $k;
  my $v;
  $nodeName =  $node->nodeName;
  if (! exists $tags{$nodeName}) {
    my %attributes;
    $tags{$nodeName} = { count => 0, attr => \%attributes};
  }
  my $ats = $tags{$nodeName}->{attr};
  my @attrs = $node->attributes();

  foreach my $attr (@attrs) {
    #  print $attr . "\n";
    if ($attr =~ /^\s*(\w+)\s*=\s*"([^"]+)"\s*$/) {
      $k = $1;
      $v = $2;
    } elsif ($attr =~ /^\s*(\w+)\s*=\s*""\s*$/) {
      $k = $1;
      $v = "\"\"";
    } elsif ($attr =~ /^"([^"]+)"$/) {
      $k = $1;
      $v = "<none>";
    } else {
      $k = $attr
    }
    if (! exists $ats->{$k}) {
      my %av;
      $ats->{$k} = \%av;
    }
    if ($v) {
      my $x = $ats->{$k};
      $x->{$v} = 1;
      $ats->{$k} = $x;
    }
  }
  $tags{$nodeName}->{count} = $tags{$nodeName}->{count} + 1;
  $tags{$nodeName}->{attr} = $ats;
}
#############################################################
#
# used by scanTags
#
############################################################
sub printStatsCsv {
  foreach my $key (sort keys %tags ) {
    print sprintf "%s,%d,,\n",$key,$tags{$key}->{count};
    my $attr = $tags{$key}->{attr};
    foreach my $key (sort keys %{$attr} ) {
      my $c = scalar (keys %{$attr->{$key}});
      #      if ($key !~ /^(root|n|id|key|linkid|goto|nodeid)$/) {
      if ($c < 5) {
        print sprintf ",,%s,%s\n",$key,join ",",keys %{$attr->{$key}};
      } else {
        print sprintf ",,%s,%d items\n",$key,$c; #scalar (keys %{$attr->{$key}});
      }
    }
  }
}
#############################################################
#
# does the tags analysis parsing xml of all entry records
#
############################################################
sub scanTags {
  my $sth;
  my $parser = XML::LibXML->new;
  #  my $parser = new XML::DOM::Parser;

  $writeCount = 0;
  $sth = $dbh->prepare("select * from entry");
  my $entries = $dbh->selectall_arrayref("SELECT id,root,broot,word,bword,nodeId,xml from entry");

  foreach my $row (@$entries) {
    my ($id, $root,$broot,$word,$bword,$nodeId,$xml) = @$row;
    my $doc = $parser->parse_string($xml);
    my $docroot = $doc->documentElement;
    traverseNode($docroot);
    #    foreach my $child ($docroot->findnodes('entryFree')) {
    #      if ($child->nodeType == XML_ELEMENT_NODE) {
    #        traverseNode($child);
    #      }
    #    }
  }
  printStatsCsv();
}
################################################################
#
#
#
################################################################
sub checkArrow {
  my $node = shift;

  if ($node->nodeType != XML_ELEMENT_NODE) {
    return;
  }
  if ($node->nodeName ne "orth") {
    return;
  }
  my $attr = $node->getAttributeNode("type");
  if (! $attr ) {
    return;
  }
  if ($attr->getValue ne "arrow") {
    return;
  }
  $attr = $node->getAttributeNode("lang");
  if (! $attr || ($attr->getValue ne "ar")) {
    return;
  }
  if ($node->hasChildNodes) {
    my $textNode = $node->getFirstChild;
    if ($textNode->nodeType == XML_TEXT_NODE) {
      my $text = $textNode->nodeValue;

      $lookupsth->bind_param(1,$text);
      $lookupsth->execute();
      my ($id,$bword,$nodeId) = $lookupsth->fetchrow_array;
      my $ok = 0;
      if ($id) {
        $ok = 1;
      } else {
        $nodeId = "";
      }
      print STDOUT sprintf "%d,%s,%s,%s,%s,%s,%s,%s\n",$ok,$currentNodeId,
        decode("utf-8",$currentRoot),$currentBRoot,
        decode("utf-8",$currentWord),$currentBWord,$text,$nodeId;
    }
  }
}
#############################################################
#
#
#
############################################################
sub scanArrow {
  my $sth;
  my $parser = XML::LibXML->new;
  #  my $parser = new XML::DOM::Parser;

  $writeCount = 0;
  my $entries = $dbh->selectall_arrayref("SELECT id,root,broot,word,bword,nodeId,xml from entry order by root");
  print STDOUT "Found,In Node,Root,Buckwalter,Word,Buckwalter word,Arrow target,At NodeId\n";
  foreach my $row (@$entries) {
    my ($id, $root,$broot,$word,$bword,$nodeId,$xml) = @$row;
    my $doc = $parser->parse_string($xml);
    my $docroot = $doc->documentElement;
    $currentNodeId = $nodeId;
    $currentRoot = $root;
    $currentBRoot = $broot;
    $currentWord = $word;
    $currentBWord = $bword;
    traverseNode($docroot);
  }
}
################################################################
#
# takes entries <tagname lang="ar">abcd</tagname> and looks up
# 'abcd' in entry table. If found, it adds attributes to the
# node and adds an entry to @links which is processed by the calling
# routine to decide whether to update the db.
#
# For entries with "type" = "arrow", if it can't find the linked to
# item, it writes out an unresolved link record.
#
################################################################
sub setLinksForNode {
  my $node = shift;
  my $nodeName;
  my $parentName;
  my $skip = 0;
  my $isArrow = 0;
  $nodeName =  $node->nodeName;
  my $parentNode = $node->getParentNode;

  # going to skip entyfree and any child nodes of <form>
  if ($nodeName eq "entryfree") {
    $skip = 1;
  }
  while ($parentNode && ! $skip) {
    $parentName = $parentNode->nodeName;
    if ($parentName eq "form") {
      $skip = 1;
    }
    $parentNode = $parentNode->getParentNode;
  }
  #  print STDERR sprintf "[%d]<%s><%s>\n",$skip,$parentName,$nodeName;
  return unless ! $skip;
  #  print "$nodeName\n";
  my $attr = $node->getAttributeNode("lang");
  if (! $attr || ($attr->getValue ne "ar")) {
    return;
  }
  if ($nodeName eq "orth") {
    my $attr = $node->getAttributeNode("type");
    if ($attr && ($attr->getValue eq "arrow")) {
      $isArrow = 1;
    }
  }
  #
  #  can it have multiple text nodes ?
  #
  if ($node->hasChildNodes) {
    my $textNode = $node->getFirstChild;
    if ($textNode->nodeType == XML_TEXT_NODE) {
      my $text = $textNode->nodeValue;

      ## lookup the word
      #      if ($doTest) {
      #        $text = convertString($text,"link");
      #      }

      $lookupsth->bind_param(1,$text);
      $lookupsth->execute();
      #        print STDERR "Lookup:[$text]\n";
      my ($id,$bword,$nodeId) = $lookupsth->fetchrow_array;
      if (!$id) {
        #
        # some have dammatan forms so check for these
        #
        #        $dlookupsth->bind_param(1,$text);

        if ($text =~ /^[\p{InArabic}\p{IsSpace}\p{IsPunct}]+$/) {
          $lookupsth->bind_param(1,$text . chr(0x64c));
        } else {
          $lookupsth->bind_param(1,$text . "N");
        }
        if ($lookupsth->execute()) {
          ($id,$bword,$nodeId) = $lookupsth->fetchrow_array;
          #          if ($id) {
          #            print STDERR "Found at [$id][$bword][$nodeId]\n";
          #          }
          #        }
        }
      }
      if ($isArrow) {
        $arrowsCount++;
        if (! $id ) {
          $unresolvedArrows++;
          push @links, { type => 1,word => $text , id => $unresolvedArrows};

        } else {

        }
      }
      #
      #  check the record we're linking to is not this one
      #
      if ($id && ($id != $currentRecordId)) {
        if ($nodeId) {
          $linkCount++;
          $node->setAttribute("goto",$id);
          $node->setAttribute("nodeid",$nodeId);
          $node->setAttribute("linkid",$linkCount);
          $updateNode = 1;
          push @links, { type => 0,id => $id,node => $nodeId,bword => $bword,word => $text,linkid => $linkCount};
        } else {
          print STDERR "Record id:$id has no nodeid\n";
        }
      }
    }
  }
}
#############################################################
#
#
############################################################
sub setLinks {
  my $letter = shift;
  my $parser = XML::LibXML->new;
  #  my $parser = new XML::DOM::Parser;


  my @letters;
  my @roots;
  if ($letter) {
    if ($letter =~ /,/) {
    } else {
      push @letters,$letter;
    }
  } else {
    my $x = $dbh->selectall_arrayref("select distinct bletter from root");
    foreach my $y (@$x) {
      push @letters,$y->[0];
    }
  }
  # my $sth = $dbh->prepare("select broot from root where bletter = ?");
  # $sth->bind_param(1,$letter);
  # $sth->execute();
  # while (my @r = $sth->fetchrow_arrow()) {
  #   push @roots, $r[0];
  # }
  my $lettersth = $dbh->prepare("select bword from root where bletter = ?");
  my $entrysth = $dbh->prepare("select id,root,broot,word,bword,nodeId,xml,page from entry where broot = ?");
  my $updatesth = $dbh->prepare('update entry set xml = ? where id = ?');
  foreach $letter (@letters) {
    #    print STDERR "Doing letter [$letter]\n";
    $writeCount = 0;
    $lettersth->bind_param(1,$letter);
    $lettersth->execute();
    # iterate through the roots for this letter
    while (@roots = $lettersth->fetchrow_array()) {
      #      print STDERR "Doing root:" . $roots[0] . "\n";
      $entrysth->bind_param(1,$roots[0]);
      $entrysth->execute();
      # iterate through the entries for this root
      my @entry;
      while (@entry = $entrysth->fetchrow_array()) {
        my ($id, $root,$broot,$word,$bword,$nodeId,$xml,$page) = @entry;
        #        print STDERR "Doing word $bword\n";
        #        if (0) {
        my $doc = $parser->parse_string($xml);
        my $nodes = $doc->getElementsByTagName ("entryFree");
        my $n = $nodes->size();
        $currentRecordId = $id;
        for (my $i = 0; $i < $n; $i++) {
          $#links = -1;         # clear old links
          my $node = $nodes->item($i);
          $updateNode = 0;
          $currentNodeId = $nodeId;
          $currentWord = $word;
          traverseNode($node);
          #  REMOVE THE NEXT LINE WHEN DONE
          #$updateNode = 0;
          if ($updateNode) {
            $xml = $node->toString;
            $updatesth->bind_param(1,$xml);
            $updatesth->bind_param(2,$id);
            $updatesth->execute();
            $writeCount++;
            if ($writeCount > $commitCount) {
              $dbh->commit();
              #           $dbh->begin_work();
              $writeCount = 0;
            }
          }
          if (scalar(@links) > 0) {
            print $llog sprintf "Node:[%d][%s][%s][%s]\n",$id,$nodeId,$word,$bword;
            foreach my $link (@links) {
              if ($link->{type} == 0) {
                print $llog sprintf "[%d]    [%s]  to  [%d][%s] [%s]\n",$link->{linkid},$link->{word},$link->{id},$link->{node},$link->{bword};
              } else {
                my $w = $link->{word}; # this should be arabic unless we have run with --no-convert
                my $aw = "";
                if ($w =~ /^[\p{InArabic}\p{IsSpace}\p{IsPunct}]+$/) {
                  $aw = convertString($w,"link");
                }
                print $llog sprintf "[unresolved arrow %d ] %s, %s  , V%d/%d\n",$link->{id},$w,$aw,getVolForPage($page),$page;
              }
            }
          }
        }                       # end of process entryfree
        #        }                       # end of process entries for root
      }
    }
  }
  if ($writeCount > 0) {
    $dbh->commit();
    #    $dbh->begin_work();
    $writeCount = 0;
  }
  print STDERR "Arrows count $arrowsCount, unresolved : $unresolvedArrows\n";
}
###################################################################
#   | Volume | Last Page |
#   |--------+-----------|
#   | 1      | 367       |
#   | 2      | 837       |
#   | 3      | 1280      |
#   | 4      | 1757      |
#   | 5      | 2219      |
#   | 6      | 2475      |
#   | 7      | 2749      |
#   | 8      | 3064      |
###################################################################
sub getVolForPage {
  my $page = shift;

  if ($page < 368) {
    return 1;
  }
  if ($page < 838) {
    return 2;
  }
  if ($page < 1281) {
    return 3;
  }
  if ($page < 1758) {
    return 4;
  }
  if ($page < 2220) {
    return 5;
  }
  if ($page < 2776) {
    return 6;
  }
  if ($page < 2750) {
    return 7;
  }
  if ($page < 3065) {
    return 8;
  }
  return -1;
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
    $entrysth = $dbh->prepare("insert into entry (root,broot,word,itype,nodeId,bword,xml,supplement,file) values (?,?,?,?,?,?,?,?,?)");
    $rootsth = $dbh->prepare("insert into root (word,bword,letter,bletter,supplement) values (?,?,?,?,?)");
    $lookupsth = $dbh->prepare("select id,bword,nodeId from entry where word = ?");
  };
  if ($@) {
    print STDERR "SQL prepare error:$@\n";
    print STDERR "DB updates disabled\n";
    $dryRun = 1;
  }

  my $parser = XML::LibXML->new;
  #  my $parser = new XML::DOM::Parser;
  my $doc = $parser->parse_string($xml);

  my $nodes = $doc->getElementsByTagName ("entryFree");
  my $n = $nodes->size();
  print STDERR "Nodes : $n\n";
  for (my $i = 0; $i < $n; $i++) {
    my $node = $nodes->item($i);
    $updateNode = 0;
    traverseNode($node);
    if ($updateNode) {
      print $node->toString;
    }
  }

}
#############################################################
#
#
############################################################
sub testEncoding {
  my $entries = $dbh->selectall_arrayref("SELECT id,root,broot,word,bword,nodeId,xml from entry limit 20");

  foreach my $row (@$entries) {
    my ($id, $root,$broot,$word,$bword,$nodeId,$xml) = @$row;
    #    print STDOUT Encode::decode('UTF-8', $root); ## fuck!
    print STDOUT sprintf "%s ===== %s ========== %s\n",$nodeId,decode("utf-8",$root),decode("utf-8",$word);
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
                link => sub { testlink();},
                encoding => sub { testEncoding();}
              );

  if (exists $tests{$fn} ) {
    $tests{$fn}->();
  } else {
    print STDERR "Unknown test routine: $fn\n";
  }
  exit 0;
}
#############################################################
#
# MAIN
#
############################################################

my $sql;
if ($sqlSource) {
  # get SQL source from file
} else {
  $sql = getSQL();
}
if ($initdb) {
  if ( -e $dbname ) {
    if (! $overwrite ) {
      print STDERR "DB $dbname exists, remove or run with --overwrite\n";
      exit 1;
    } else {
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
    $xrefsth = $dbh->prepare("insert into xref (word,bword,node,page) values (?,?,?,?)");
    $entrysth = $dbh->prepare("insert into entry (root,broot,word,itype,nodeId,bword,xml,supplement,file,page) values (?,?,?,?,?,?,?,?,?,?)");
    $rootsth = $dbh->prepare("insert into root (word,bword,letter,bletter,supplement,quasi,alternates,page) values (?,?,?,?,?,?,?,?)");
    $alternatesth = $dbh->prepare("insert into alternate (word,bword,letter,bletter,supplement,quasi,alternate) values (?,?,?,?,?,?,?)");
    # these are for the set-links searches
    $lookupsth = $dbh->prepare("select id,bword,nodeId from entry where word = ?");
  };
  if ($@) {
    print STDERR "SQL prepare error:$@\n";
    print STDERR "DB updates disabled\n";
    $dryRun = 1;
  }
}
if ($doTest) {
  runTest($doTest);
} elsif ($xmlFile) {
  if ( ! -e $xmlFile) {
    print STDERR "No such file: $xmlFile";
    exit 1;
  }
  parseFile($xmlFile);
  fixupPages();
} elsif ($parseDir ) {
  if ( ! -d $parseDir ) {
    print STDERR "No such directory: $parseDir\n";
    exit 1;
  }
  parseDirectory($parseDir);
  fixupPages();
} elsif ($linksMode) {
  my $linklog = File::Spec->catfile($logDir,"link.log");
  open($llog,">:encoding(UTF8)",$linklog);
  setLinks($linkletter) ;
} elsif ($tagsMode) {
  scanTags();
} elsif ($arrowMode) {
  scanArrow();
} else {
  print "Nothing to do here\n";
}
#convertString("ja Oxdr sthwmn");

#open $blog,">x.log";

#parseFile("./xml/j0.xml");

#parseDirectory("./xml");
