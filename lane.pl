#!/usr/bin/perl -w
use strict;
use POSIX;
use XML::LibXML;
#use XML::Parser;
use Encode;
use utf8;
use DBI;
#use File::Spec;
use File::Basename;
use File::Find;
use File::Temp qw/tempdir/;
use File::Spec::Functions qw(catfile);
#use Cwd;
use Data::Dumper;
use Getopt::Long;
use Time::HiRes qw( time );
use FileHandle;
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
my $sql;
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
my $logDir;
my $linksMode = 0;
my $convertMode = 0;
my $tagsMode = 0;
my $arrowMode = 0;
my $xrefMode = 0;
my $supplementItypeMode = 0;
my $diacriticsMode = 0;
my $linkletter = ""; # just set links for words whose root begins with this letter
my $rootLineNumber;
my $entryLineNumber;
my $withPerseus = 0;
my $testConversionMode = 0;
my $noLogging = 0;
my $doAll = 1;
my $showProgress = 0;
my %tags;
#
#

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
my $dbId;
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
my $baresth;  #  = $dbh->prepare("select id,word from entry where bareword = ?");
my $lastentrysth;
my $orthsth;
my $updateNode; # set links uses to check if the node xml needs saving
#

my $currentNodeId = "";
my $lastNodeId = "";
my $currentRoot = "";
my $currentBRoot = "";
my $currentWord = "";
my $currentBWord = "";
my $currentItype;
my $currentLetter;
my @currentForms;
my @currentStatus;
my $currentRecordId;
my $currentText;
my $currentPage = -1;
my $currentRootPage = -1;
my $firstPage;
my @links;
my $supplement;
my $currentFile;
my $jumpId = 0;
sub testConvertString {
  my $t = shift;
  my $s = $t;
  my ($start,$end,$ix);


  my $c = 0;
  $c += ($t =~ tr/'|OWI}A/\x{621}\x{622}\x{623}\x{624}\x{625}\x{626}\x{627}/);
  $c += ($t =~ tr/bptvjHx/\x{628}\x{629}\x{62a}\x{62b}\x{62c}\x{62d}\x{62e}/);
  $c += ($t =~ tr/d*rzs$S/\x{62f}\x{630}\x{631}\x{632}\x{633}\x{634}\x{635}/);
  $c += ($t =~ tr/DTZEg\-f/\x{636}\x{637}\x{638}\x{639}\x{63a}\x{640}\x{641}/);
  $c += ($t =~ tr/qklmnhw/\x{642}\x{643}\x{644}\x{645}\x{646}\x{647}\x{648}/);
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

  if ($noLogging) {
    return;
  }

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
#   2:  double question mark
#   3:  ampersand
#   4:  A@ converted to L
#   5:  non Buckwalter character (that is not punctuation or space)
#   6:  A_ converted to I
################################################################
sub convertString {
  my $t = shift;
  my $proctype = shift;
  my $lineno = shift;
  my $s = $t;


  if (! defined $lineno ) {
     $lineno = "";
  }
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
      writelog($blog,sprintf "2,%s,%s,%s,%s,V%d/%d,%s", $currentRoot,$currentWord,$currentNodeId,$t,getVolForPage($currentPage),$currentPage,$lineno);
#      return $t;
    }
    # convert all A@ to { for alef wasl
    if ($t =~ /A@/) {
      writelog($blog,sprintf "4,%s,%s,%s,%s,%s,V%d/%d,%s", $proctype,$currentRoot,$currentWord,$currentNodeId,$t,getVolForPage($currentPage),$currentPage,$lineno);
      $t =~ s/A@/{/g;
    }
    if ($t =~ /A_/) {
      writelog($blog,sprintf "6,%s,%s,%s,%s,%s,V%d/%d,%s", $proctype,$currentRoot,$currentWord,$currentNodeId,$t,getVolForPage($currentPage),$currentPage,$lineno);
    $t =~ s/A_/I/g;
    }
    if ($t =~ /A\^/) {
      writelog($blog,sprintf "7,%s,%s,%s,%s,%s,V%d/%d,%s", $proctype,$currentRoot,$currentWord,$currentNodeId,$t,getVolForPage($currentPage),$currentPage,$lineno);
    $t =~ s/A\^/O/g;
    }
    if ($t =~ /y\^/) {
      writelog($blog,sprintf "8,%s,%s,%s,%s,%s,V%d/%d,%s", $proctype,$currentRoot,$currentWord,$currentNodeId,$t,getVolForPage($currentPage),$currentPage,$lineno);
    $t =~ s/y\^/}/g;
    }
    if ($t =~ /w\^/) {
      writelog($blog,sprintf "9,%s,%s,%s,%s,%s,V%d/%d,%s", $proctype,$currentRoot,$currentWord,$currentNodeId,$t,getVolForPage($currentPage),$currentPage,$lineno);
    $t =~ s/w\^/W/g;
    }
    # get rid of the &c,
    # this might need fixing properly
    # may when proctype = "word" or "root" we can strip it out
    #

    if ($t =~ /&/) {
      writelog($blog,sprintf "3,%s,%s,%s,%s,%s,V%d/%d,%s", $proctype,$currentRoot,$currentWord,$currentNodeId,$t,getVolForPage($currentPage),$currentPage,$lineno);
      if ($proctype eq "alternateroot") {
        $t =~ s/&c\.*/ /g;
      }
    }
  }
# Following regex from:
# https://stackoverflow.com/questions/3845518/how-do-i-convert-escaped-characters-into-actual-special-characters-in-perl
#
      $t=~s/\\(
        (?:[arnt'"\\]) |               # Single char escapes
        (?:[ul].) |                    # uc or lc next char
        (?:x[0-9a-fA-F]{2}) |          # 2 digit hex escape
        (?:x\{[0-9a-fA-F]+\}) |        # more than 2 digit hex
        (?:\d{2,3}) |                  # octal
        (?:N\{U\+[0-9a-fA-F]{2,4}\})   # unicode by hex
        )/"qq|\\$1|"/geex;

  #  $t =~ s/&amp;c/ /g);
  my $c = 0;
  $c += ($t =~ tr/'|OWI}A/\x{621}\x{622}\x{623}\x{624}\x{625}\x{626}\x{627}/);
  $c += ($t =~ tr/bptvjHx/\x{628}\x{629}\x{62a}\x{62b}\x{62c}\x{62d}\x{62e}/);
  $c += ($t =~ tr/d*rzs$S/\x{62f}\x{630}\x{631}\x{632}\x{633}\x{634}\x{635}/);
  $c += ($t =~ tr/DTZEg\-f/\x{636}\x{637}\x{638}\x{639}\x{63a}\x{640}\x{641}/);
  $c += ($t =~ tr/qklmnhw/\x{642}\x{643}\x{644}\x{645}\x{646}\x{647}\x{648}/);
  $c += ($t =~ tr/YyFNKau/\x{649}\x{64a}\x{64b}\x{64c}\x{64d}\x{64e}\x{64f}/);
  # ` for dagger alef
  # { for alef wasla
  $c += ($t =~ tr/i~o`{/\x{650}\x{651}\x{652}\x{670}\x{671}/);


  $c += ($t =~ tr/PJVG/\x{67e}\x{686}\x{6a4}\x{6af}/);
  # ^ hamza above
  # = madda above
  # _ hamza below
  $c += ($t =~ tr/^=_/\x{654}\x{653}\x{655}/);


#  $c += ($t =~ tr/PJVG/\x{67e}\x{686}\x{6a4}\x{6af}/);


  my $sz = length $t;
  my $j = 0;

#
#  go through checking for characters that have not been converted
#  and report them as type 5 errors
#
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
          writelog($blog,sprintf "5,%d,%d,%d,%s,%s,%s,%s,%s,%s,%d,%s,%s,V%d,%d,%s",
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
                   $t,getVolForPage($currentPage),
                   $currentPage,
                   $lineno);

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
          # this is done in vowelling code
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
                #
                # do not understand what these are. They do not matching anything explicit in
                # the text but seem to have been inserting as part of the conversion.
                #
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
#####################################################################
#
# this is where itype promotion happens as part of <form> processing
#
####################################################################
sub processNode {
  my $node = shift;
  my $nodeName;

  $nodeName =  $node->nodeName;
  $node->removeAttribute("TEIform");
  if ($nodeName eq "form") {
    processForm($node);
  } elsif ($node->nodeName eq "pb") {
    my $pageAttr = $node->getAttributeNode("n");
    # save the first proper page number so we can fixup the records that
    # don't have it set
    if ($pageAttr) {
      if ($currentPage == -1) {
        $firstPage = $pageAttr->getValue();
      }
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
  my $perseusxml = shift;
  my $ret = 0;
  $debug && print $dlog "ENTRY write: [$root][$broot][$word][$itype][$bword][$node]\n";

  if ($dryRun) {
    $entryDbCount++;
    return 1;
  }

  my $nodenum;
  $nodenum = $node;
  if ($nodenum =~ s/^n//) {
    if ($nodenum =~ /(\d+)-(\d+)/) {
      $nodenum = $1 + ($2 / 10);
    }
    else {
      $nodenum = $nodenum + 0.0;
    }
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
  $entrysth->bind_param(11,$nodenum);
  $entrysth->bind_param(12,$perseusxml);
  if ($entrysth->execute()) {
    $entryDbCount++;
    $writeCount++;
    $ret = 1;
  } else {
    $dbErrorCount++;
  }
  if ($writeCount > $commitCount) {
    $dbh->commit(); # reports 'commit ineffictive with Autocommit enabled
    #    $dbh->begin_work();
    $totalWriteCount += $writeCount;
    $writeCount = 0;
  }
  return $ret;
}
sub writeOrths {
  my $node = shift;
  my $root = shift;
  my $broot = shift;
  my @forms = @_;

  # get max(id) from entry
  $lastentrysth->execute();
  my ($entryid) = $lastentrysth->fetchrow_array;
  my $max = scalar @forms;
  for(my $i=0;$i < $max;$i++) {
    $orthsth->bind_param(1,$entryid);
    $orthsth->bind_param(2,convertString($forms[$i],"orth"));
    $orthsth->bind_param(3,$forms[$i]);
    $orthsth->bind_param(4,$node);
    $orthsth->bind_param(5,$root);
    $orthsth->bind_param(6,$broot);
    $orthsth->execute();
    $writeCount++;
  }
#  print STDERR sprintf "node %s, entry id %d, %s\n",$node,$entryid,join ",", @forms;
}
######################################################################
# $dbh->prepare("insert into xref (word,bword,node) values (?,?,?)")
#
#####################################################################
sub writeXref {
  my $word = shift;
  my $bword = shift;
  my $node = shift;
  my $type = shift;
  $debug && print $dlog "XREF write: [$word][$bword][$node]\n";

  if ($dryRun) {
    $xrefDbCount++;
    return;
  }
  if (! defined $type ) {
    $type = -1;
  }
  $xrefsth->bind_param(1,$word);
  $xrefsth->bind_param(2,$bword);
  $xrefsth->bind_param(3,$node);
  $xrefsth->bind_param(4,$currentPage);
  $xrefsth->bind_param(5,$type);
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
  my $letter = convertString($bletter,"letter",$rootLineNumber);
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
  $rootsth->bind_param(9,$currentFile);
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
        my $type = -1;
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
          $type = 1;
        }
        my $str = convertString($text,$nodeName,$node->line_number());
        $textNode->setData($str);
        #
        # write xref record using: $currentWord,$currentNodeId,$text,$str
        #
        writeXref($str,$text,$currentNodeId,$type,$node->line_number());
        #
        # to aid with searching routines, split multi-word text and write
        # record for each word
        #
        my @words = split '\s+',$text;
        if ($#words > 1) {
          $type = 2;
          foreach my $word (@words) {
            writeXref(convertString($word,$nodeName),$word,$currentNodeId,$type,$node->line_number());
          }
        }
      }
    } else {
      print $plog "Parse warning 2: node <$nodeName> has lang=ar but no text\n";
      $genWarning++;
    }
  }
}
########################################################################
# change all sense separators -An- or -bn- :
#   -b2-  <sense type="b" n="2">-b2-</sense>
#
#######################################################################
sub insertSenses {
  my $xml = shift;

  my $t;
  my $n;
  my $s;
  my $x;
  my $r;
  my $lastpos = 0;
  my $ix;
  while ($xml =~  /-([Ab])(\d+)-/g) {
    $t = $1;
    $n = $2;
    $s = sprintf "-%s%d-",$t,$n;
    $r = sprintf "<sense type=\"%s\" n=\"%d\">%s</sense>",$t,$n,$s,$s;
    if ($t && $n) {
      $x .= substr($xml,$lastpos,pos($xml) - $lastpos - length($s));
      $x .= $r;
      $lastpos = pos($xml);
    }
  }
  $x .= substr($xml,$lastpos);
  return $x;
}
sub insertTropical {
  my $xml = shift;
  my $t;
  my $x;
  my $r;
  my $lastpos = 0;
  while ($xml =~  /(\(\s*(assumed)*\s*tropical\s*[:]*\s*\))/g) {
    $t = $1;
    if ($t =~ /assumed/) {
      $r = sprintf "<assumedtropical>%s</assumedtropical>",$t;
    }
    else {
      $r = sprintf "<tropical>%s</tropical>",$t;
    }
    if ($t) {
      $x .= substr($xml,$lastpos,pos($xml) - $lastpos - length($t));
      $x .= $r;
      $lastpos = pos($xml);
    }
  }
  $x .= substr($xml,$lastpos);
  return $x;
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
  my $firstNodeId;
  my @alternates;
  $currentText = $node->toString;

  $rootLineNumber = $node->line_number();

  if ($currentRoot =~ /^\s*Quasi/i) {
    $quasiRoot = 1;
    $currentRoot =~ s/^\s*Quasi\s*//;

  }
  $currentRoot =~ s/&c\.*//;
  $currentRoot =~ s/&amp;/and/g;

  # if ($currentRoot =~ /^\(.+\)$/) {
  #   $currentRoot =~ s/^\(//;
  #   $currentRoot =~ s/\)$//;

  # }
  $currentRoot =~ s/[():,\.]//g;

  # some of the Quasi entries have : Quasi xxxx:
  # TODO there is also: txm and quasi txm ???? (t0.xml)
  # there are (xxx or xxx) , xxxx and xxxx
  # d0.xml line 12032 has; (dmw or dmY) , V3 82/916
  #
  # t0.xml, 3387,Quasi tqY: or, accord. to some, tqw
  # q0.xml,12374,qnf*, or, accord. to some, qf*
  #
  $currentRoot =~ s/accord\s+to\s+some//;
  $currentRoot =~ s/see\s+art/see/;
#    $currentRoot =~ "tqY and tqw";
#  }
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
  if ($entryCount > 0) {
    my $entry = $entries->item(0);
    $currentText = $entry->toString;
    if ($currentText =~ /See\s+supplement/i) {
      $entryCount--;
      if ($entryCount > 0) {
        print $plog sprintf "ERROR: see supplement with entryCount > 1\n";
      }
    }
  }
  #
  # write root record
  # Some roots are just xxxx See yyyy. They will be skipped because they
  # have no entries but will be added later by the alternates code.
  #
  if ($entryCount > 0) {
    writeRoot(convertString($currentRoot,"root",$rootLineNumber),$currentRoot,$currentLetter,$quasiRoot,scalar(@alternates));
    if (scalar(@alternates) > 0) {
      my $id = $dbh->func('last_insert_rowid');
      my $quasi = 0;
      foreach my $word (@alternates) {
        if ($word =~ /quasi/) {
          $quasi = 1;
          next;
        }
        writeAlternate(convertString($word,"alternateroot",$rootLineNumber),$word,$currentLetter,$quasi,$id);
        $quasi = 0;
      }
    }
  }

  #
  # Process each <entryFree> for the root
  #
  for (my $i=0;$i < $entryCount;$i++) {
    my $entry = $entries->item($i);
    $entryLineNumber = $entry->line_number();
    $currentText = $entry->toString;
    #    print sprintf "Processing entryFree %d [ %s  ]\n",$entryLineNumber,$entry->nodeName;
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
        next;
      }
    }

    #
    # get the node id of form nNNNNN
    # often (?) verb forms don't have either a node or key they just have something like:
    #  <entryFree>
    #    <form>
    #      <itype>2</itype>
    #     <orth lang="ar">$aA~a^a</orth>
    #    </form>
    #  </entryFree>
    #
    # A nodeId is created by appending the entry index ($i) to the last node id
    # Eg n21492-7 means that the entry with this node id is the seventh entry for
    # the current root and that it occurs after the known entry with id n21492
    #
    $idAttr = $entry->getAttributeNode("id");
    if ($idAttr) {
      $id = $idAttr->getValue();
    } else {
      $verbose && print $plog "Node has no ID:" . $entry->toString . "\n";
      if ( $lastNodeId ) {
        $id = sprintf "%s-%d",$lastNodeId,$i;
      } else {
        $id = createId();
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
      #=============================
      # alef wasla  TODO ?
      #=============================
      $currentWord =~ s/A@/L/g;
    }
    if ( ! $id ) {
      print $plog "Parse warning 4: No ID field\n";
      $genWarning++;
      next;
    }
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
    $entry->setAttribute("key",encode("UTF-8",$currentWord));
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
      my $perseusxml;
      if ($withPerseus) {
       $perseusxml = $entry->toString;
      }
      #          if (! $skipConvert ) {
      my $clone = $entry->cloneNode(1);
      if ($clone->nodeType == XML_ELEMENT_NODE) {
        $convertMode = 1;
        traverseNode($clone);
        $clone->setAttribute("key",convertString($currentWord,"word",$entry->line_number()));
        $xml =  $clone->toString;
      } else {
        print $elog "Error cloning node for transliteration:$currentNodeId,$currentWord";
      }
      if (! $xml ) {
        $xml = $entry->toString;
      }
      $xml = insertSenses($xml);
      $xml = insertTropical($xml);
      #          }
      #
      # update db
      #
      my $ok = writeEntry(convertString($currentRoot,"root",$rootLineNumber),$currentRoot,
                          convertString($currentWord,"word",$entryLineNumber),
                          $currentItype,$currentNodeId,$currentWord,$xml,$perseusxml);
      #
      #
      #
      if ($ok && ($#currentForms != -1)) {
        writeOrths($currentNodeId,
                   convertString($currentRoot,"root",$rootLineNumber),
                   $currentRoot,
                   @currentForms);
      }
      # for use by the alternates
      if (! $firstNodeId ) {
        $firstNodeId = $currentNodeId;
      }
      if ($currentNodeId !~ /-/) {
        $lastNodeId = $currentNodeId;
      }
    } else {
      print $plog "Parse warning 3: No node or word\n";
      $genWarning++;
    }
  }
  #
  # write alternates ?
  #
  #
  my $quasi = 0;
  my $see = 0;
  my $jumpToRoot;
  my $jumpFromRoot;
  for (my $i=0; $i < scalar(@alternates);$i++)  {
    if ($node->toString =~ /See Supplement/i) {
      # TODO what to do with these
      #      probably nothing, since if they are in the supplement they will be loaded
      last;
    }
    my $alternate = $alternates[$i];
    if ($alternate =~ /quasi/i) {
      $quasi = 1;
      next;
    }
    if ($alternate =~ /see/i) {
      $see = 1;
      next;
    }
    if ($see) {
      $jumpFromRoot = $currentRoot;
      $jumpToRoot = $alternate;
    }
    else {
      $jumpFromRoot = $alternate;
      $jumpToRoot = $currentRoot;
    }
    # they all have the same letter
    #
    writeRoot(convertString($jumpFromRoot,"root",$rootLineNumber),$jumpFromRoot,$currentLetter,$quasi,0);

    #
    # Now right a simple entry record that has something like this but pointing to root
    # <foreign lang="ar" goto="44316" nodeid="n7560" linkid="103440" bareword="1">ﻢِﺣْﺭَﺎﺛْ</foreign>
    # using the firstNode for the just written root
    #
    # create a new nodeid
    # my $j = -1;

    # if ($lastNodeId =~ /-(\d+)$/) {
    #   $j = $1;
    # }
    # $lastNodeId =~ s/-\d+//;
    # $j++;
    # if (! $firstNodeId ) {
    #   print STDERR "no node for : [$currentRoot][$entryCount][$alternate]\n";
    #   print STDERR $node->toString;
    # }
    $jumpId++;
    my $nodeid = sprintf "j%d",$jumpId;
    my $xml = sprintf "<entryFree id=\"%s\" key=\"%s\" type=\"main\">",$nodeid,convertString($jumpFromRoot,"root",$rootLineNumber);
    $xml .= " See ";
    $xml .= sprintf "<foreign lang=\"ar\" jumptoroot=\"%s\" nodeid=\"%s\">%s</foreign>",
      $jumpToRoot,$nodeid,convertString($jumpToRoot,"root",$rootLineNumber);

    $xml .= "</entryFree>";
    writeEntry(convertString($jumpFromRoot,"root",$rootLineNumber),$jumpFromRoot,
               convertString($jumpFromRoot,"word",$entryLineNumber),
               "",$nodeid,$i,$xml,$xml);
    $quasi = 0;
    $see = 0;
  }
}
############################################################
#  create subdirectory of the given base directory
#
#  if no base is given, use the system temporary directory
# if unable to create subdirectory of the given base
# create subdirec
#
###########################################################
sub getLogDirectory {
  my $base = shift;
  my $id = shift;

  # check the base exists or can be created
  if (! $base ) {
      $base = dirname(tempdir());
  }
  if ( -d $base ) {
  }
  else {
    if (! mkdir $base) {
      $base = dirname(tempdir());
    }
  }
  # try to create the subdirectory
  my $logdir = catfile($base,$id);
  if (-d $logdir ) {
    return $logdir;
  }
  if ( mkdir $logdir) {
    return $logdir;
  }
  # couldn't create, so try create as subdirectory of current
  $logdir = catfile(getcwd(),$id);
  if (-d $logdir ) {
    return $logdir;
  }
  elsif ( mkdir $logdir) {
    return $logdir;
  }
  # couldn't do that either, so use the temporary directory
  # or the current working directory ignore the $dbid
  $logdir = catfile(dirname(tempdir()),$id);
  if (-d $logdir ) {
    return $logdir;
  }
  elsif ( mkdir $logdir) {
    return $logdir;
  }
  return getcwd();
}

sub getLogBase {
  my $filename = shift;
  my ($base,$p,$suffix) = fileparse($filename,'\..*');

  # this is a global variable
  $currentFile = $base;

  # if (! $logbase ) {
  #   my $dt = POSIX::strftime "%y%m%d", localtime;
  #   $base = $dt . "-" . $base;
  # } else {
  #   $base = $logbase . "-" . $base;
  # }
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
#  $base = sprintf "%s-%s", $base,$dbId;
  my $errlog = File::Spec->catfile($logDir,$base . "-err.log");
  my $parselog = File::Spec->catfile($logDir,$base . "-parse.log");
  my $convlog = File::Spec->catfile($logDir,$base . "-conv.log");
  my $debuglog = File::Spec->catfile($logDir,$base . "-debug.log");
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

  print STDERR "Parsing file: $fileName\n" unless ! $showProgress;
  my $parser = XML::LibXML->new;
  $parser->set_options("line_numbers" => "parser");

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
  $doc->setEncoding("UTF-8");
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
#  my $str =  $doc->toString;

#  open(OUT,">:encoding(UTF8)","/tmp/test.xml");
#  binmode OUT, ":utf8";
#  print OUT $str;
#  close OUT;

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
    print STDERR "No such directory:$d\, process terminatingn";
    exit 1;

  }
  print STDERR "Parsing directory $d\n" unless ! $showProgress;
  print STDERR "Creating log files in $logDir\n" unless ! $showProgress;

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
      $currentPage = -1;
      $currentRootPage = -1;

      parseFile($file);
      fixupPages();
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
                     "Entry count" => $entryDbCount
                    }
    }

  };

  if ($@) {
    print STDERR "File::Find error opening directory:[$d]  : $@\n";
    return;
  }
  my %audit;
  foreach my $h (@totals) {
    my ($k,$b,$c) = fileparse($h->{File},qw(.xml));
    $audit{$k} = $h;
  }
  my $str = Data::Dumper->Dump([\%audit],[qw(audit)]);

  open AUD , ">","$logDir/audit.txt";
  print AUD $str;
  close AUD;
}

sub generateId {
  my  $str = sprintf("%0.8x",rand()*0xffffffff);
  $str .= sprintf("%0.8x",rand()*0xffffffff);

  print STDERR "Run ID: $str\n" unless ! $showProgress;
  return $str;
}
################################################################
#
#  we only know page breaks, not page numbers so the first records
#  in root,entry and xref will have page number = -1, so we find the
#  while processing the entries $firstPage is set to the value of
#  <pb n="nnn"/>
#  after all records have been written, we use this to set the page
#  for those records
#
#  If the first entry in a volume is longer than one page this will
#  not set the right number.
#
################################################################
sub fixupPages {

  return unless ! $dryRun;

  if ($firstPage) {
    $firstPage--;
    my $sth = $dbh->prepare("update root set page = $firstPage where page = -1 and datasource = 1");
    $sth->execute();
    $sth = $dbh->prepare("update xref set page = $firstPage where page = -1 and datasource = 1");
    $sth->execute();
    $sth = $dbh->prepare("update entry set page = $firstPage where page = -1 and datasource = 1");
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
    $parser->set_options("line_numbers" => "parser");

  #  my $parser = new XML::DOM::Parser;

  $writeCount = 0;
  $sth = $dbh->prepare("select * from entry where datasource = 1");
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
# print details of <orth type="arrow">
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
#  this just prints detail of nodes with <orth type="arrow">
#  was a testing function and is no longer needed
#
############################################################
sub scanArrow {
  my $sth;
  my $parser = XML::LibXML->new;
    $parser->set_options("line_numbers" => "parser");

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
  my $bareWordMatch = 0;
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
  #
  #
  if ($nodeName eq "foreign") {
    my $attr = $node->getAttributeNode("jumptoroot");
    if ($attr) {
      return;
    }
  }
  #
  #  can it have multiple text nodes ?
  #
  if ($node->hasChildNodes) {
    my $textNode = $node->getFirstChild;
    if ($textNode->nodeType == XML_TEXT_NODE) {
      my $text = $textNode->nodeValue;
      # lookup the word
      #   see if there is an 'entry' record for this word
      #   setting $id to the record num of the matched entry
      #
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
      if (! $id ) {
        #
        # it could be a bare form without diacritics
        #
        my $word = $text;
        my $count = ($word =~ tr/\x{64b}-\x{652}\x{670}\x{671}//d);
        my $bareword;
        $baresth->bind_param(1,$word);
        if ($baresth->execute()) {
          ($id,$word,$bword,$bareword,$nodeId) = $baresth->fetchrow_array;
          if ($id) {
#            print STDERR sprintf "[%d] bareword match %s, $nodeId\n",$isArrow,decode("UTF-8",$word);
            $bareWordMatch = 1;
          }
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
          $node->setAttribute("bareword",$bareWordMatch);
          $updateNode = 1;
          push @links, { type => 0,id => $id,node => $nodeId,bword => $bword,word => $text,linkid => $linkCount,bareword => $bareWordMatch};
        } else {
          print STDERR "Record id:$id has no nodeid\n";
        }
      }
    }
  }
}
#############################################################
#
# NOTE: All links and headword code has been moved to
# a separate file (links.pl)
#
# can optionally just do links for letter supplied as param
# otherwise it will do all
############################################################
sub setLinks {
  my $letter = shift;
  my $parser = XML::LibXML->new;
    $parser->set_options("line_numbers" => "parser");

  #  my $parser = new XML::DOM::Parser;

  print STDERR "Updating links\n" unless ! $showProgress;
  my @letters;
  my @roots;
  if ($letter) {
    if ($letter =~ /,/) {
    } else {
      push @letters,$letter;
    }
  } else {
    my $x = $dbh->selectall_arrayref("select distinct bletter from root where datasource = 1");
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
  my $lettersth = $dbh->prepare("select bword from root where bletter = ? and datasource = 1");
  my $entrysth = $dbh->prepare("select id,root,broot,word,bword,nodeId,xml,page from entry where broot = ? and datasource = 1");
  my $updatesth = $dbh->prepare('update entry set xml = ? where id = ?');
  $baresth = $dbh->prepare("select id,word,bword,bareword,nodeId from entry where bareword = ? and datasource = 1");

  my $lastentrysth;

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
        $doc->setEncoding("UTF-8");
        my $nodes = $doc->getElementsByTagName ("entryFree");
        my $n = $nodes->size();
        $currentRecordId = $id;
        for (my $i = 0; $i < $n; $i++) {
          $#links = -1;         # clear old links
          my $node = $nodes->item($i);
          $updateNode = 0;
          $currentNodeId = $nodeId;
          $currentWord = $word;
          #
          # in links mode this wil call
          # setLinksForNode
          #
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
                print $llog sprintf "[%d]    [%s]  to  [%d][%s] [%s][%d]\n",$link->{linkid},$link->{word},$link->{id},$link->{node},$link->{bword},$link->{bareword};
              } else {
                my $w = $link->{word}; # this should be arabic unless we have run with --no-convert
                my $aw = "";
                if ($w =~ /^[\p{InArabic}\p{IsSpace}\p{IsPunct}]+$/) {
                  $aw = convertString($w,"link");
                }

                eval {
                print $llog sprintf "[unresolved arrow %d ] %s, %s  , V%d/%d\n",$link->{id},$w,$aw,getVolForPage($page),$page;
                };
                if ($@) {
                  print $@ . "\n";
                  print "w = $w, aw = $aw\n";
                }
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
  print STDERR "Links count $arrowsCount, unresolved : $unresolvedArrows\n";
}
#
# update the entry for each xref record, store the associated root & entry word (ie the entry
# in which the word occurred. We need this so we can load the entry when we present the search result
#
sub updateXrefs {

  print STDERR "Updating cross-references\n" unless ! $showProgress;
  my $sth =  $dbh->prepare("select id,node from xref where datasource = 1");
  my $uh = $dbh->prepare("update xref set root = ?,broot = ?,entry = ?,bentry = ?,nodenum = ? where id = ?");
  my $lh = $dbh->prepare("select root,broot,word,bword,nodenum from entry where nodeId = ? and datasource = 1");
  if (! $sth || ! $uh || ! $lh) {
    print STDERR "Error preparing update xref SQL";
    return;
  }
  $sth->execute();
  $writeCount = 0;
  my $nodenum;
  while (my @xref = $sth->fetchrow_array()) {
    # get the entry
    $lh->bind_param(1,$xref[1]);
    $lh->execute();
    my @entry = $lh->fetchrow_array();
    if ($#entry != -1) {
      $uh->bind_param(1,$entry[0]);
      $uh->bind_param(2,$entry[1]);
      $uh->bind_param(3,$entry[2]);
      $uh->bind_param(4,$entry[3]);
      $nodenum = $entry[4];
      $uh->bind_param(5,$entry[4]);
      $uh->bind_param(6,$xref[0]);
      $uh->execute();
      $writeCount++;
      if ($writeCount > $commitCount) {
        $dbh->commit();
        #           $dbh->begin_work();
        $writeCount = 0;
      }
    }
  }
  $dbh->commit();
}
sub get_insert_point {
  my $rec = shift;
  my $x = $rec->{itype};
  $x += 0;

  my $entry = $dbh->prepare("select id,root,word,itype,nodeid,nodenum,file from entry where root = ?  and supplement = 0 order by nodenum asc");

  $entry->bind_param(1,decode("UTF-8",$rec->{root}));
  $entry->execute();
  while(my $entryrec = $entry->fetchrow_hashref) {
    my $itype = $entryrec->{itype};
    if ($itype !~ /^\d+$/) {
      return $entryrec;
    }
    $itype += 0;
    if ($itype > $x) {
      return $entryrec;
    }
  }
}

####################################################################
# without running this supplement entries with itypes appear at the
# end of the entries. This code merges them with the other itypes
####################################################################
sub fix_supplement_itype {
  print STDERR "Fixing supplement details\n" unless ! $showProgress;
  my $sth = $dbh->prepare("select id,broot,root,word,itype,nodeId,nodenum,file from entry where supplement = 1 and itype != \"\" order by id asc");
  my $dup = $dbh->prepare("select id,root,word,itype,nodeid,nodenum,file from entry where root = ?  and supplement = 0 order by nodenum asc");

  my $numh = $dbh->prepare("select id,nodenum from entry where nodenum < ? order by nodenum desc");
  my $updateh = $dbh->prepare("update entry set nodenum = ? where id = ?");

  my $rec;
  my $duprec;
  my $root;
  my $itype;

  $sth->execute();
  my @candidates;
  while ($rec = $sth->fetchrow_hashref) {
    $root = decode("UTF-8",$rec->{root});
    $itype = $rec->{itype};
    if ($itype !~ /^\d+$/) {
      next;
    }
    $dup->bind_param(1,$root);
    $dup->execute();
    $duprec = $dup->fetchrow_hashref;
    next unless $duprec;    # ignore if no matching root in main text
    push @candidates, $rec;
  }
#  print STDERR "Candidate count:" . scalar(@candidates) . "\n";

  foreach my $c (@candidates) {
    my $p = get_insert_point($c);
    if ($p) {
      $numh->bind_param(1,$p->{nodenum});
      $numh->execute();
      my $prior = $numh->fetchrow_hashref;
      if ($prior) {
        my $n = ($p->{nodenum} - $prior->{nodenum})/2;
        $n += $prior->{nodenum};
#        print sprintf "Insert between %f %f = %f\n",$prior->{nodenum},$p->{nodenum},$n;
        $updateh->bind_param(1,$n);
        $updateh->bind_param(2,$c->{id});
        if ($updateh->execute()) {
#          print STDERR sprintf "Root %s, update node %s, nodenum set %f\n",$c->{broot},$c->{nodeId},$n;
        }
        else {
#          print STDERR sprintf "Error updating node %s\n",$c->{nodeId};
        }
      }
      else {
#        print STDERR "No prior nodenum record for root %s, node %s, using nodenum %f from \n",$c->{broot},$c->{nodeId},$p->{nodenum},$p->{nodeid};
      }

    }
    else {
#      print STDERR "Cannot find insert point for root %s, node %s\n",$c->{broot},$c->{nodeId};
    }
  }
  $dbh->commit();
}

sub stripDiacritics {
  print STDERR "Creating bare word entries without diacritics\n" unless ! $showProgress;
  my $count = 0;
  my $sth =  $dbh->prepare("select id,word from xref where datasource = 1");
  my $uh = $dbh->prepare("update xref set bareword = ? where id = ?");
  if (! $sth || ! $uh ) {
    print STDERR "Error preparing update xref SQL";
    return;
  }
  $sth->execute();

  $writeCount = 0;
  while (my @xref = $sth->fetchrow_array()) {
    $count++;
    my $id = $xref[0];
    my $word = decode("UTF-8",$xref[1]);
    my $count = ($word =~ tr/\x{64b}-\x{652}\x{670}\x{671}//d);
#    print STDERR sprintf "id %d %d, %s\n",$id,$count,$word;
    # get the entry


      $uh->bind_param(1,$word);
      $uh->bind_param(2,$id);
      $uh->execute();
      $writeCount++;
      if ($writeCount > $commitCount) {
        $dbh->commit();
        #           $dbh->begin_work();
        $writeCount = 0;
      }
   }
  #print sprintf "Xref rows to be updated : %d\n",$count;
  $count = 0;
  #
  # same again for entry
  #
  $sth = $dbh->prepare("select id,word from entry where datasource = 1");
  $uh = $dbh->prepare("update entry set bareword = ? where id = ?");
  if (! $sth || ! $uh ) {
    print STDERR "Error preparing update entry SQL";
    return;
  }
  $sth->execute();
  $writeCount = 0;
  while (my @entry = $sth->fetchrow_array()) {
    $count++;
    my $id = $entry[0];
    my $word = decode("UTF-8",$entry[1]);
    my $count = ($word =~ tr/\x{64b}-\x{652}\x{670}\x{671}//d);
#    print STDERR sprintf "id %d %d, %s\n",$id,$count,$word;
      $uh->bind_param(1,$word);
      $uh->bind_param(2,$id);
      $uh->execute();
      $writeCount++;
      if ($writeCount > $commitCount) {
        $dbh->commit();
        #           $dbh->begin_work();
        $writeCount = 0;
      }
   }
#  print sprintf "Entry rows updated : %d\n",$count;
  $count = 0;
  #
  # same again for itype
  #
  $sth = $dbh->prepare("select id,word from itype where datasource = 1");
  $uh = $dbh->prepare("update itype set bareword = ? where id = ?");
  if (! $sth || ! $uh ) {
    print STDERR "Error preparing update entry SQL";
    return;
  }
  $sth->execute();
  $writeCount = 0;
  while (my @itype = $sth->fetchrow_array()) {
    my $id = $itype[0];
    my $word = decode("UTF-8",$itype[1]);
    my $count = ($word =~ tr/\x{64b}-\x{652}\x{670}\x{671}//d);
#    print STDERR sprintf "id %d %d, %s\n",$id,$count,$word;
      $uh->bind_param(1,$word);
      $uh->bind_param(2,$id);
      $uh->execute();
      $writeCount++;
      if ($writeCount > $commitCount) {
        $dbh->commit();
        #           $dbh->begin_work();
        $writeCount = 0;
      }
   }
  $dbh->commit();
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
  if ($page < 2476) {
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
#############################################################
#
#
############################################################
sub testEncoding {
  my $entries = $dbh->selectall_arrayref("SELECT id,root,broot,word,bword,nodeId,xml from entry limit 20");

  foreach my $row (@$entries) {
    my ($id, $root,$broot,$word,$bword,$nodeId,$xml) = @$row;
    #    print STDOUT Encode::decode('utf8', $root); ## fuck!
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
sub writeSource {
  my $sno = shift;
  my $sth;
  my $id;
  eval {
    $sth = $dbh->prepare("select id from lexicon where sourceid = $sno");
  };
  if ( $@ ) {
    print STDERR $@;
    return 1;
  }
  my $mode = 0;
  if ($sth->execute()) {
    my $rec = $sth->fetchrow_hashref;
    if (! $rec ) {
      $mode = 1;
    }
    else {
      $mode = 2;
      $id = $rec->{id};
    }
  }
  my $version = `cat SCRIPTVERSION`;
  $version =~ s/\n//g;
  my $xmlversion = `cat XMLVERSION`;
  $xmlversion =~ s/\n//g;
  # create new entry
  if ($mode == 1) {
    eval {
    $sth = $dbh->prepare("insert into lexicon (sourceid,description,createversion,createdate,xmlversion,dbid) values (?,?,?,?,?,?)");
    };
    if ($@) {
      print STDERR $@;
      return 1;
    }
    $sth->bind_param(1,$sno);
    $sth->bind_param(2,"Lane's Arabic-English Lexicon");
    $sth->bind_param(3,$version);
    $sth->bind_param(4,scalar(localtime()));
    $sth->bind_param(5,$xmlversion);
    $sth->bind_param(6,$dbId);
    $sth->execute();
    $dbh->commit();
  }
  elsif ($mode == 2) {
    eval {
    $sth = $dbh->prepare("update lexicon set updateversion = ?,updatedate = ?,xmlversion = ? where id = ?");
    };
    if ($@) {
      print STDERR $@;
      return 1;
    }
    $sth->bind_param(1,$version);
    $sth->bind_param(2,scalar(localtime()));
    $sth->bind_param(3,$id);
    $sth->bind_param(4,$xmlversion);
    $sth->execute();
    $dbh->commit();
  }
  return 0;
}
sub prepareSql {
  #
  # this doesn't catch the errors, so if file exists and tables are not right it will crash
  #
  eval {
    $xrefsth = $dbh->prepare("insert into xref (datasource,word,bword,node,page,type) values (1,?,?,?,?,?)");
    $entrysth = $dbh->prepare("insert into entry (datasource,root,broot,word,itype,nodeId,bword,xml,supplement,file,page,nodenum,perseusxml) values (1,?,?,?,?,?,?,?,?,?,?,?,?)");
    $rootsth = $dbh->prepare("insert into root (datasource,word,bword,letter,bletter,supplement,quasi,alternates,page,xml) values (1,?,?,?,?,?,?,?,?,?)");
    $alternatesth = $dbh->prepare("insert into alternate (datasource,word,bword,letter,bletter,supplement,quasi,alternate) values (1,?,?,?,?,?,?,?)");
    # these are for the set-links searches
    $lookupsth = $dbh->prepare("select id,bword,nodeId from entry where word = ? and datasource = 1");
    # for the <orth> forms
    $orthsth = $dbh->prepare("insert into orth (datasource,entryid,form,bform,nodeid,root,broot) values (1,?,?,?,?,?,?)");
    $lastentrysth = $dbh->prepare("select max(id) from entry where datasource = 1");
  };
  if ($@) {
    print STDERR "SQL prepare error:$@\n";
    print STDERR "DB updates disabled\n";
    $dryRun = 1;
  }
}
########################################################
# do the post processing
#########################################################
sub postParse() {
    $xrefMode = 1;
    updateXrefs();
    $diacriticsMode = 1;
    stripDiacritics();
    fix_supplement_itype();
#    $linksMode = 1;
#    my $linklog = File::Spec->catfile($logDir,"link.log");
#    open($llog,">:encoding(UTF8)",$linklog);
#    setLinks();#$linkletter) ;
}
#############################################################
#
# MAIN
#
############################################################
GetOptions (
            "do-all" => \$doAll,
            "no-logs" => \$noLogging,
            "scan-arrows" => \$arrowMode,
            "scan-tags" => \$tagsMode,
#            "set-links" => \$linksMode,
            "letter=s" => \$linkletter,
            "log-dir=s" => \$logDir,
            "show-progress" => \$showProgress,
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
            "db=s" => \$dbname,
            "xrefs" => \$xrefMode,
            "diacritics" => \$diacriticsMode,
            "with-perseus" => \$withPerseus,
            "supplement-itypes" => \$supplementItypeMode,
            "test-conversion=s" => \$testConversionMode
           )
  or die("Error in command line arguments\n");

if ($testConversionMode) {
  $noLogging = 1;
  print $testConversionMode . "\n";
  print convertString($testConversionMode,"word") . "\n";
  exit 1;
}

$dbId = generateId();
if (! $dbname ) {
  $dbname = sprintf "%s.sqlite",$dbId;
}
if ($sqlSource) {
  eval {
    # get SQL source from file
    open(SQL,"<$sqlSource") or die "Error opening SQL $sqlSource";
    while(<SQL>) {
      chomp;
      $sql .= $_;
    }
    close SQL;
  };
  if ($@) {
    print STDERR "Error reading SQL source: $@\n";
    exit 1;
  }

}
else {
  if ($initdb) {
    print STDERR "initialise db requested but no SQL source specified\n";
    exit 1;
  }
}
#
# set the directory for logs
#
$logDir = getLogDirectory($logDir,$dbId);
#
#
#
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
  prepareSql();
}
if ($doTest) {
  runTest($doTest);
  exit 1;
}
########################################################
# Do a single file
#########################################################
if ($xmlFile) {
  if ( ! -e $xmlFile) {
    print STDERR "No such file: $xmlFile";
    exit 1;
  }
  print STDERR "Parse single file $xmlFile\n" unless ! $showProgress;
  print STDERR "Creating log files in $logDir\n" unless ! $showProgress;
  parseFile($xmlFile);
  fixupPages();
  if ($doAll) {
    postParse();
  }
  writeSource(1);
  exit 0;
}
########################################################
#  Do all files in the directory
########################################################
if ($parseDir ) {
  if ( ! -d $parseDir ) {
    print STDERR "No such directory: $parseDir\n";
    exit 1;
  }
  parseDirectory($parseDir);
  if ($doAll) {
    postParse();
  }
  writeSource(1);
  print STDERR "Run ID: $dbId\n" unless ! $showProgress;
  open OUT,">LASTRUNID";
  print OUT $dbId;
  close OUT;
  exit 0;
}
elsif ($tagsMode) {
  scanTags();
} elsif ($arrowMode) {
  scanArrow();
} else {
  print "Nothing to do here\n";
}
