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

my $dbName;
my $nodeName;
my $logDir = "";
my $verbose=0;
my $dbh;
my $lookupsth;
my $baresth;
my $linkCount=0;
my $arrowsCount=0;
my $resolvedArrows=0;
my $unresolvedArrows=0;
my $writeCount=0;
my $logfh;
my @links;
my $linkType;
my $currentRecordId;
my $commitCount = 500;
my $updateNode;
my $currentWord;
my $currentNodeId;
binmode STDERR, ":utf8";
binmode STDOUT, ":utf8";
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
    $sql = "select id,root,broot,word,bword,nodeId,xml,page from entry where datasource = 1";
    $entrysth = $dbh->prepare($sql);
  } else {
    $sql = "select id,root,broot,word,bword,nodeId,xml,page from entry where datasource = 1 and nodeid = ?";
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
sub lookupWord {
  my $word = shift;

  $lookupsth->bind_param(1,$word);
  $lookupsth->execute();
  my $rec = $lookupsth->fetchrow_hashref;
  if ($rec) {
    return ($rec->{id},$rec->{nodeId},$rec->{word},1);
  }
  $lookupsth->bind_param(1,$word . chr(0x64c));
  $lookupsth->execute();
  $rec = $lookupsth->fetchrow_hashref;
  if ($rec) {
    return ($rec->{id},$rec->{nodeId},$rec->{word},2);
  }
  my $count = ($word =~ tr/\x{64b}-\x{652}\x{670}\x{671}//d);
  my $bareword;
  $baresth->bind_param(1,$word);
  if ($baresth->execute()) {
    $rec = $baresth->fetchrow_hashref;
    if ($rec) {
      return ($rec->{id},$rec->{nodeId},$rec->{word},3);
    }
  }
  return ();
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
  if (! $node ) {
    $sql = "select id,root,broot,word,bword,nodeId,xml,page from entry where datasource = 1";
    $entrysth = $dbh->prepare($sql);
  } else {
    $sql = "select id,root,broot,word,bword,nodeId,xml,page from entry where datasource = 1 and nodeid = ?";
    $entrysth = $dbh->prepare($sql);
    $entrysth->bind_param(1,$node);
  }
  my $updatesth = $dbh->prepare('update entry set xml = ? where id = ?');
  $baresth = $dbh->prepare("select id,word,bword,bareword,nodeId from entry where bareword = ? and datasource = 1");
  my $lookupsth = $dbh->prepare("select id,bword,nodeId from entry where word = ? and datasource = 1");

  my $lastentrysth;
  my @entry;
  $entrysth->execute();
  while (@entry = $entrysth->fetchrow_array()) {
    my ($id, $root,$broot,$word,$bword,$nodeId,$xml,$page) = @entry;
    my $doc = $parser->parse_string($xml);
    $doc->setEncoding("UTF-8");
    my $nodes = $doc->getElementsByTagName("orth");
    my $n = $nodes->size();
    $currentRecordId = $id;
    for (my $i = 0; $i < $n; $i++) {
      $#links = -1;             # clear old links
      my $node = $nodes->item($i);
      $attrnode = $node->getAttributeNode("type");
      if ($attrnode && ($attrnode->value eq "arrow")) {
        $arrowsCount++;
        $linktext = $node->textContent;
        if ($linktext) {
          my ($linkToId,$linkToNode,$linkToWord,$linkType) = lookupWord($linktext);
          if ($linkToNode) {
            print  $logfh sprintf "%d,%s,%s,%s,%s,%s\n",$linkType,$linktext,$nodeId,decode("UTF-8",$word),$linkToNode,decode("UTF-8",$linkToWord);
            $resolvedArrows++;
          }
          else {
            print $logfh sprintf "0,%s,%s\n",$linktext,$nodeId;
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
  print STDERR sprintf "Links count %d, resolved : %d (%d)\n",$arrowsCount,$resolvedArrows,($arrowsCount - $resolvedArrows);
}
###########################################################################
# main
##########################################################################
GetOptions(
           "db=s" => \$dbName,
           "node=s" => \$nodeName,
           "log-dir=s" => \$logDir,
           "verbose" => \$verbose
          );

if (! $logDir ) {
  $logDir = ".";
}
my $linklog = File::Spec->catfile($logDir,"link.log");
open($logfh,">:encoding(UTF8)",$linklog) or die "Cannot open logfile $@\n";
if (! $dbName ) {
  print STDERR "No database name given,exiting\n";
  exit 0;
}
openDb($dbName);
$lookupsth = $dbh->prepare("select id,word,bword,nodeId from entry where word = ? and datasource = 1");
$baresth = $dbh->prepare("select id,word,bword,bareword,nodeId from entry where bareword = ? and datasource = 1");
setLinks($nodeName);
