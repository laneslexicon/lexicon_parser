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

my $dbName = "";
my $nodeName = "";
my $logDir = "";
my $verbose=0;
my $dbh;
my $lookupsth;
my $baresth;
my $headsth;
my $linkCount=0;
my $arrowsCount=0;
my $resolvedArrows=0;
my $multiMatches=0;
my $unresolvedArrows=0;
my $writeCount=0;
my $logfh;
my $headfh;
my @links;
my $linkType;
my $currentRecordId;
my $commitCount = 500;
my $updateNode;
my $currentWord;
my $currentNodeId;
my $headwords=0;
my $noUpdate=0;
my $showXml=0;
my $showHelp=0;
binmode STDERR, ":utf8";
binmode STDOUT, ":utf8";
######################################################
#
# this block of code reads through the head words
# and for those that have > 1 word, tries to find the
# single head that best matches the root
#
# (it also prints all the buckwalter characters it finds,
# but that's not relevant)
#
######################################################
sub build_rx {
  my $word = shift;
  my @letters = split '',$word;
  my $rx = "";
  foreach my $letter (@letters) {
    $rx .= $letter;
    $rx .= "\\w*";
  }
  return $rx;

}
sub find_word {
  my $root = shift;
  my $entry = shift;

  my $rx = build_rx($root);
  my @words = split /\s+/,$entry;
  my $ix = -1;
  for (my $j=0;$j < scalar(@words);$j++) {
    #      print STDERR sprintf "Checking %s\n",$words[$j];
    if ($words[$j] =~ /$rx/) {
      return $j;
    }
  }
  return -1;
}
sub find_headwords {
  my %b;
  my @bletters;
  my $bletter;
  my $dbname = shift;
  my $writeCount = 0;
  my $commitCount = 500;
  my $updateCount = 0;
  openDb($dbname);
  if (! $dbh) {
    print STDERR "Failed to open db $dbname\n";
    return;
  }
  my $sth = $dbh->prepare("select id,root,broot,word,bword,nodeId from entry");
  my $update = $dbh->prepare("update entry set headword = ? where id = ?");
  if ( $update->err )    {
    die "ERROR return code:" . $update->err . " error msg: " . $update->errstr . "\n";
  }
  my $max = 100;


  my $i = 0;
  my $rx;
  my $word_index;
  my $candidate_count = 0;
  my $match_count = 0;
  my $wy = 0;
  my $root;
  my $head;
  my $rec;
  $sth->execute();
  while ($rec = $sth->fetchrow_arrayref) {
    #  my ($id,$root,$broot,$word,$bword,$nodeid) = split '|', $_;
    @bletters = split '',$rec->[4];
    for (my $i=0;$i < scalar(@bletters);$i++) {
      $bletter = $bletters[$i];
      my $c = -1;
      if ( exists $b{$bletter} ) {
        $c = $b{$bletter};
      }
      $b{$bletter} = $c + 1;
    }
    $head = decode("UTF-8",$rec->[3]);
    my @words = split /\s+/,$head;
    if (scalar(@words) > 1) {
      $root = decode("UTF-8",$rec->[1]);
      $word_index = find_word($root,$head);
      $candidate_count++;
      if ($word_index == -1) {
        if ($root =~ /\N{ARABIC LETTER WAW}/) {
          my $r = $root;
          $r =~ s/\N{ARABIC LETTER WAW}/\N{ARABIC LETTER ALEF}/;
          $word_index = find_word($r,$head);
          if ($word_index == -1) {
            $r = $root;
            $r =~ s/\N{ARABIC LETTER WAW}/\N{ARABIC LETTER YEH}/;
            $word_index = find_word($r,$head);
          }
          if ($word_index == -1) {
            $r = $root;
            $r =~ s/\N{ARABIC LETTER WAW}/\N{ARABIC LETTER ALEF MAKSURA}/;
            $word_index = find_word($r,$head);
          }
        }
      }
      if ($word_index == -1) {
        if ($root =~ /\N{ARABIC LETTER ALEF MAKSURA}$/) {
          my $r = $root;
          $r =~ s/\N{ARABIC LETTER ALEF MAKSURA}$/\N{ARABIC LETTER ALEF}/;
          $word_index = find_word($r,$head);
          if ($word_index == -1) {
            $r = $root;
            $r =~ s/\N{ARABIC LETTER WAW}/\N{ARABIC LETTER YEH}/;
            $word_index = find_word($r,$head);
          }
          if ($word_index == -1) {
            $r = $root;
            $r =~ s/\N{ARABIC LETTER WAW}/\N{ARABIC LETTER ALEF MAKSURA}/;
            $word_index = find_word($r,$head);
          }
        }
      }
      if ($word_index == -1) {
        if ($root =~ /\N{ARABIC LETTER YEH}/) {
          my $r = $root;
          $r =~ s/\N{ARABIC LETTER YEH}/\N{ARABIC LETTER ALEF}/;
          $word_index = find_word($r,$head);
        }
      }
      if ($word_index == -1) {
        if ($root =~ /\N{ARABIC LETTER ALEF}/) {
          my $r = $root;
          $r =~ s/\N{ARABIC LETTER ALEF}/\N{ARABIC LETTER ALEF MAKSURA}/;
          $word_index = find_word($r,$head);
        }
      }
      if ($word_index == -1) {
        my $r = $root;
        $r =~ s/.$//;
        $word_index = find_word($r,$head);
      }
      if ($word_index == -1) {
        my $r = $root;
        $r =~ s/^.//;
        $word_index = find_word($r,$head);
      }
      if ($word_index != -1) {
        $update->bind_param(1,$words[$word_index]);
#        print STDERR "Updating with:" . $words[$word_index] . "\n";
        $update->bind_param(2,$rec->[0]);
        $update->execute();
        if ( $update->err )    {
          die "ERROR return code:" . $update->err . " error msg: " . $update->errstr . "\n";
        }
        $writeCount++;
        $updateCount++;
        if ($writeCount > $commitCount) {
          $dbh->commit;
          $writeCount = 0;
        }
      }
      print $headfh sprintf "%d[%s][%s][%s][%s][%s]\n",$word_index,$rec->[5],$root,$rec->[2],$head,$rec->[4];
      #    }
      if ($word_index != -1) {
        $match_count++;
      }
      #print $rec->[4] . "\n";
    }
    $i++;
    #  if ($i > $max) {
    #    last;
    #  }

  }
  if ($writeCount > 0) {
    $dbh->commit;
  }
  print STDERR sprintf "Candidates %d, matches %d, updates %d\n",$candidate_count,$match_count,$updateCount;
#    print sort keys %b;
#    print "\n";
#    foreach $bletter (sort keys %b) {
#      print sprintf "[%s][%04x]\t%d\n",$bletter,ord($bletter),$b{$bletter};
#    }
#  }
}
###############################################################
#
# end headword code
#
##############################################################
################################################################
#
#
################################################################
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

sub traverseNode {
  my $node = shift;

  while ($node) {
    if ($node->nodeType == XML_ELEMENT_NODE) {
      setLinksForNode($node);
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
  print $nodeName . "\n";
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
# can optionally just do links for letter supplied as param
# otherwise it will do all
############################################################
sub setLinksOld {
  my $node = shift;
  my $parser = XML::LibXML->new;
  $parser->set_options("line_numbers" => "parser");
  my $sql;
  my $entrysth;
  if (! $node ) {
    $sql = "select id,root,broot,word,bword,nodeId,xml,page,headword from entry where datasource = 1";
    $entrysth = $dbh->prepare($sql);
  } else {
    $sql = "select id,root,broot,word,bword,nodeId,xml,page,headword from entry where datasource = 1 and nodeid = ?";
    $entrysth = $dbh->prepare($sql);
    $entrysth->bind_param(1,$node);
  }
  my $updatesth = $dbh->prepare('update entry set xml = ? where id = ?');
  $baresth = $dbh->prepare("select id,word,bword,bareword,nodeId from entry where bareword = ? and datasource = 1");

  my $lastentrysth;
  my @entry;
  $entrysth->execute();
  while (@entry = $entrysth->fetchrow_array()) {
    my ($id, $root,$broot,$word,$bword,$nodeId,$xml,$page) = @entry;
    print STDERR "$nodeId\n" unless ! $verbose;
    my $doc = $parser->parse_string($xml);
    $doc->setEncoding("UTF-8");
    my $nodes = $doc->getElementsByTagName("entryFree");
    my $n = $nodes->size();
    $currentRecordId = $id;
    for (my $i = 0; $i < $n; $i++) {
      $#links = -1;             # clear old links
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
      $updateNode = 0;
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
        print $logfh sprintf "Links for [%d][%s][%s][%s]\n",$id,$nodeId,decode("UTF-8",$word),$bword;
        foreach my $link (@links) {
          if ($link->{type} == 0) {
            print $logfh sprintf "[%d]    [%s]  to  [%d][%s] [%s][%d]\n",$link->{linkid},$link->{word},$link->{id},$link->{node},$link->{bword},$link->{bareword};
          } else {
            my $w = $link->{word}; # this should be arabic unless we have run with --no-convert
            eval {
              print $logfh sprintf "[unresolved arrow %d ] %s, V%d/%d\n",$link->{id},$w,getVolForPage($page),$page;
            };
            if ($@) {
              print STDERR $@ . "\n";
            }
          }
        }
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
################################################
# link match types:
#  1  : word
#  2  : headword
#  3  : bareword
###############################################
sub lookupWord {
  my $word = shift;

  $lookupsth->bind_param(1,$word);
  $lookupsth->execute();
  my $rec = $lookupsth->fetchrow_hashref;
  if ($rec) {
    return ($rec->{id},$rec->{root},$rec->{nodeId},$rec->{word},$rec->{page},1);
  }
  $headsth->bind_param(1,$word);
  $rec = $lookupsth->fetchrow_hashref;
  if ($rec) {
    return ($rec->{id},$rec->{root},$rec->{nodeId},$rec->{word},$rec->{page},2);
  }
  my $count = ($word =~ tr/\x{64b}-\x{652}\x{670}\x{671}//d);
  my $bareword;
  $baresth->bind_param(1,$word);
  if ($baresth->execute()) {
    $rec = $baresth->fetchrow_hashref;
    if ($rec) {
      return ($rec->{id},$rec->{root},$rec->{nodeId},$rec->{word},$rec->{page},3);
    }
  }
  #
  # don't need this, the bareword should catch them
  #
  $lookupsth->bind_param(1,$word . chr(0x64c));
  $lookupsth->execute();
  $rec = $lookupsth->fetchrow_hashref;
  if ($rec) {
    return ($rec->{id},$rec->{root},$rec->{nodeId},$rec->{word},$rec->{page},4);
  }
  return ();
}
sub findLink {
  my $text = shift;
  my @words;
  $text =~ s/^\s+//g;
  $text =~ s/\s+$//g;
  if ($text =~ /\s/) {
    push @words,$text;
    push @words,split /\s/,$text;
  }
  else {
    push @words,$text;
  }
  my @matches;
  my ($linkToId,$linkToRoot,$linkToNode,$linkToWord,$linkType,$linkToPage);
  my $wordMatched;
  foreach my $linkword (@words) {
    ($linkToId,$linkToRoot,$linkToNode,$linkToWord,$linkToPage,$linkType) = lookupWord($linkword);
    if ($linkToNode) {
      push @matches,{ node => $linkToNode,
                      id => $linkToId,
                      root => decode("UTF-8",$linkToRoot),
                      matchedword => $linkword,
                      word => decode("UTF-8",$linkToWord),
                      page => $linkToPage,
                      type => $linkType };
    }
  }
#  print Data::Dumper->Dump([\@matches],[qw(matches)]);
  return @matches;
}
sub setLinks {
  my $node = shift;
  my $parser = XML::LibXML->new;
  $parser->set_options("line_numbers" => "parser");
  my $sql;
  my $attrnode;
  my $entrysth;
  my $linktext;
  my $linkToNode;
  my $updateRequired;
  if (! $node ) {
    $sql = "select id,root,broot,word,bword,nodeId,xml,page from entry where datasource = 1 order by nodenum asc";
    $entrysth = $dbh->prepare($sql);
  } else {
    $sql = "select id,root,broot,word,bword,nodeId,xml,page from entry where datasource = 1 and nodeid = ?";
    $entrysth = $dbh->prepare($sql);
    $entrysth->bind_param(1,$node);
  }
  my $updatesth = $dbh->prepare('update entry set xml = ? where id = ?');
  $baresth = $dbh->prepare("select id,root,word,bword,bareword,nodeId,page from entry where bareword = ? and datasource = 1");

  my $lookupsth = $dbh->prepare("select id,root,bword,nodeId,page from entry where word = ? and datasource = 1");

  my $lastentrysth;
  my @entry;

  $entrysth->execute();
  while (@entry = $entrysth->fetchrow_array()) {
    my ($id, $root,$broot,$word,$bword,$nodeId,$xml,$page) = @entry;
    my $doc = $parser->parse_string($xml);
    $doc->setEncoding("UTF-8");
    my $nodes = $doc->getElementsByTagName("orth");
    my $n = $nodes->size();
    my $printHeader=0;
    $updateRequired = 0;
    $currentRecordId = $id;
    for (my $i = 0; $i < $n; $i++) {
      $#links = -1;             # clear old links
      my $node = $nodes->item($i);
      $attrnode = $node->getAttributeNode("type");
      if ($attrnode && ($attrnode->value eq "arrow")) {
        # show node name
        if ($verbose && !$printHeader ) {
          print STDERR $nodeId . "\n";
          $printHeader = 1;
        }
        if ($showXml) {
          print STDERR $node->toString . "\n";
        }
        $arrowsCount++;
        $linktext = $node->textContent;
        my @matches = findLink($linktext);
        if ((scalar @matches) > 1) {
          $multiMatches++;
        }
        if ((scalar @matches) > 0) {
          for(my $j=0;$j <= $#matches;$j++) {
            my $m = $matches[$j];
            my ($linkToId,$linkToNode,$linkToWord,$linkType);
            print  $logfh sprintf "‎ %d,%d,%s,%s,%s,%s,%s\n",
              scalar(@matches),
              $m->{type},
              $linktext,
              $nodeId,
              $m->{matchedword},
              $m->{node},
              $m->{word};
          }
          ### update the node xml,
          my $matchIx = -1;
          if (scalar(@matches) == 1) {
            $matchIx = 0;
          }
          if (scalar(@matches) > 1) {
            ### very much TODO
            $matchIx = 0;
          }
          if ($matchIx != -1) {
            my $m = $matches[$matchIx];
            $node->setAttribute("goto",$m->{id});
            $node->setAttribute("root",$m->{root});
            $node->setAttribute("page",$m->{page});
            $node->setAttribute("vol",getVolForPage($m->{page}));
            $node->setAttribute("nodeid",$m->{node});
            $node->setAttribute("matched",$m->{matchedword});
            $node->setAttribute("linktype",$m->{type});
            $updateRequired = 1;
            if ($showXml) {
              print STDERR $node->toString . "\n\n";
            }
            $resolvedArrows++;

          }
        }
        else {
          print $logfh sprintf "0,%s,%s\n",$linktext,$nodeId;
        }
      }
    }
    if (! $noUpdate && $updateRequired) {
        my $xml = decode("UTF-8",$doc->toString);
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
#      print STDERR decode("UTF-8",$doc->toString) . "\n";
    }
  if ($writeCount > 0) {
    $dbh->commit();
    $writeCount = 0;
  }
  print STDERR sprintf "Links count %d, resolved : %d (%d)\n",$arrowsCount,$resolvedArrows,($arrowsCount - $resolvedArrows);
  print STDERR sprintf "Multiple matches %d\n",$multiMatches;
}
###########################################################################
# main
#
# eg perl links.pl --db vanilla.sqlite --node n9017
##########################################################################
GetOptions(
           "db=s" => \$dbName,
           "node=s" => \$nodeName,
           "log-dir=s" => \$logDir,
           "verbose" => \$verbose,
           "heads" => \$headwords,
           "no-update" => \$noUpdate,
           "with-xml" => \$showXml,
           "help" => \$showHelp
          );
if ($showHelp) {
  print STDERR "--db <name of sqlite file>   use the supplied database\n";
  print STDERR "--node <node number>         do only the given node or comma separated nodes\n";
  print STDERR "--log-dir <directory>        write log file to given directory, defaults to current\n";
  print STDERR "--no-update                  do not update the database\n";
  print STDERR "--with-xml                   print the before/after XML to STDERR\n";
  print STDERR "--heads                      Update the headword entry\n";
  print STDERR "--help                       print this\n";
  exit 1;

}
if (! $logDir ) {
  $logDir = ".";
}

if ($headwords) {
  my $logfile = File::Spec->catfile($logDir,"heads.log");
  open($headfh,">:encoding(UTF8)",$logfile) or die "Cannot open logfile $@\n";
  find_headwords($dbName);
  exit 0;
}
my $linklog = File::Spec->catfile($logDir,"link.log");
open($logfh,">:encoding(UTF8)",$linklog) or die "Cannot open logfile $@\n";
if (! $dbName ) {
  print STDERR "No database name given,exiting\n";
  exit 0;
}
openDb($dbName);
$lookupsth = $dbh->prepare("select id,root,word,bword,nodeId,page from entry where word = ? and datasource = 1");
$baresth = $dbh->prepare("select id,root,word,bword,bareword,nodeId,page from entry where bareword = ? and datasource = 1");
$headsth = $dbh->prepare("select id,root,word,bword,bareword,nodeId,headword,page from entry where headword = ? and datasource = 1");
my @nodes;

@nodes = split /,/,$nodeName;
if ($nodeName) {
  foreach my $node (@nodes) {
    $node =~ s/^\s+//g;
    $node =~ s/\s+//g;
    setLinks($node);
    # clear the counters
    $linkCount=0;
    $arrowsCount=0;
    $resolvedArrows=0;
    $multiMatches=0;
    $unresolvedArrows=0;
  }
}
else {
  setLinks();
}
