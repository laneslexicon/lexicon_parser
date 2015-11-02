#!/usr/bin/perl
use strict;
use warnings;
use File::Find;
use File::Basename;
use File::Temp qw/tempdir/;
use File::Spec::Functions qw(catfile);
use English;
use FileHandle;
use DBI;
use Cwd;
use Encode;
use XML::LibXML;
use Getopt::Long;
use utf8;
my $dbh;
my $logDir;
my $dbname;
my $dbid;
my $xmlDir;
my $doHeads=0;
my $doSummary=0;
my $doConversionErrors=0;
my $doLongRoots=0;
my $doWrongLetter=0;
my $doHeadWords=0;
my $doDoubleQuestions=0;
my $doAll=0;
my $unmatchedOnly=0;
use List::Util qw( max );

sub max_depth {
   my ($ele) = @_;
   return 1 + max 0, map max_depth($_), $ele->findnodes('*');
}
binmode STDERR, ":encoding(UTF-8)";
binmode STDOUT, ":encoding(UTF-8)";
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
#
# return list of xml in supplied directory, optionally passing each to supplied function
#
#
sub parseDirectory {
  my $d = shift;
  my $fn = shift;
  my @arr;
  if (! -d $d ) {
    print STDERR "No such directory:[$d]\n";
    return @arr;

  }
  my @totals;

  eval {

    find sub { if ((-f $_) && ($File::Find::name =~ /xml$/))  {  push @arr,$File::Find::name; } }, $d;

    foreach my $file (sort @arr) {
      if ($fn) {
        print $file . "\n\n";
        $fn->($file);
      }
    }

  };

  if ($@) {
    print STDERR "File::Find error opening directory:[$d]\n";
    return @arr;
  }
  return sort @arr;
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

  }
  $dbh->{AutoCommit} = 1;
}
sub dump_tree {
  my $node = shift;

  while ($node) {
    if ($node->nodeType == XML_TEXT_NODE) {
      my $t = $node->textContent;
      $t =~ s/\s+/ /g;
      print sprintf "[t:%s]",$t;
    } elsif ($node->nodeType == XML_ELEMENT_NODE) {
      print sprintf "<%s>\n",$node->nodeName;
      if ($node->hasChildNodes()) {
        dump_tree($node->firstChild());
      }
    }
    $node = $node->nextSibling;
  }
}
sub checkForward {
  my $node = shift;
  my $uk = shift;
  my @orths;
  my $c = 0;
  my $nodeCount = 0;
  my $n = $node->nextSibling;
  my $s = "";
  while ($n) {
    if ($n->nodeType == XML_TEXT_NODE) {
      my $t = $n->textContent;
      if ($t =~ /[a-zA-Z]/) {
        return { 'size' => $c,'nodes' => $nodeCount, 'types' => $s};
      }
      $s .= "T";
    }
    if ($n->nodeType == XML_ELEMENT_NODE) {
      if ($n->nodeName !~ /foreign|orth/) {
        return { 'size' => $c,'nodes' => $nodeCount, 'types' => $s};
      }
      if ($n->getAttribute("lang") !~ /ar/) {
        return { 'size' => $c,'nodes' => $nodeCount, 'types' => $s};
      }
      $s .= "O" if $n->nodeName eq "orth";
      $s .= "F" if $n->nodeName eq "foreign";
      $nodeCount++;
      if (($n->nodeName eq "orth") && ($n->getAttribute("type") eq "arrow")) {
        $uk->{$n->unique_key} = 1;
      }
    }
    $c++;
    $n = $n->nextSibling;
    if ($c > 100) {
      return { 'size' => $c,'nodes' => $nodeCount, 'types' => $s};
    }
  }
   return { 'size' => $c,'nodes' => $nodeCount, 'types' => $s};
}
sub checkBackward {
  my $node = shift;
  my $uk = shift;
  my $c = 0;
  my @orths;
  my $nodeCount = 0;
  my $s = "";
  my $n = $node->previousSibling;
  while ($n) {
    if ($n->nodeType == XML_TEXT_NODE) {
      my $t = $n->textContent;
      if ($t =~ /[a-zA-Z]/) {
        return { 'size' => $c,'nodes' => $nodeCount, 'types' => $s};
      }
      $s .= "T";
    }
    if ($n->nodeType == XML_ELEMENT_NODE) {
      if ($n->nodeName !~ /foreign|orth/) {
        return { 'size' => $c,'nodes' => $nodeCount, 'types' => $s};
      }
      if ($n->getAttribute("lang") !~ /ar/) {
        return { 'size' => $c,'nodes' => $nodeCount, 'types' => $s};
      }
      $s .= "O" if $n->nodeName eq "orth";
      $s .= "F" if $n->nodeName eq "foreign";
      $nodeCount++;
      if (($n->nodeName eq "orth") && ($n->getAttribute("type") eq "arrow")) {
        $uk->{$n->unique_key} = 1;
      }
    }
    $c++;
    $n = $n->previousSibling;
    if ($c > 100) {
      return { 'size' => $c,'nodes' => $nodeCount, 'types' => $s};
    }
  }
  return { 'size' => $c,'nodes' => $nodeCount, 'types' => $s };
}
#
# get text for the supplied number of siblings before and after the supplied node
#
sub getText {
  my $node = shift;
  my $x = shift;              # nodes before
  my $y = shift;              # nodes after

  my @t;

  my $sz = $x + $y + 1;

  my $n = $node->previousSibling;
  while($x > 0) {
    push @t, $n->textContent;
    $n = $n->previousSibling;
    $x--;
  }
  @t = reverse @t;
  push @t, $node->textContent;
  $n = $node->nextSibling;
  while($y > 0) {
    push @t, $n->textContent;
    $y--;
    $n = $n->nextSibling;
  }
  my $str = join ' ',@t;
  $str =~ s/\n//g;
  return $str;
}

sub perseus {
  my $node = shift;
  my $xml = shift;


    my $parser = XML::LibXML->new;
  $parser->set_options("line_numbers" => "parser","suppress_errors" => 1);
  #  my $parser = new XML::DOM::Parser;
  my $doc = $parser->parse_string($xml);
  $doc->setEncoding("UTF-8");
  my $nodes = $doc->getElementsByTagName ("entryFree");
  my $n = $nodes->size();
  my @orths = $nodes->[0]->findnodes('//orth[@type="arrow"]');
  my $i=0;
  my $t = "";
#  dump_tree($nodes->[0]);
  my %processed;
  my $ret = 0;
  foreach my $orth (@orths) {
    #    my $p = $orth->find("preceding-sibling::*");
    #    my $f = $orth->find("following-sibling::*");
    my $nb;
    my $na;
    my $eNodes = 0;
    my $v;

    my $v = checkBackward($orth,\%processed);
    $nb = $v->{size};
    $eNodes += $v->{nodes};

    my $w = checkForward($orth,\%processed);
    $na = $w->{size};
    $eNodes += $w->{nodes};

    if (! exists $processed{$orth->unique_key}) {
#      if (($nb > 0) || ($na > 0)) {
      if ($eNodes > 0) {
        $t .= sprintf "[%s] %d [%d][%s] [%s][%d][%s]-->[%s]\n",$node,$i,$nb,
          $v->{types},
          $orth->textContent,
          $na,$w->{types},
          getText($orth,$nb,$na);
        $ret++;
      }
    }
    $i++;

  }
  return ($ret,$t);
}
##########################################################################
#
#
##########################################################################


openDb("lexicon1.sqlite");

#my $sth = $dbh->prepare("select root,broot,page,word,bword,nodeid,perseusxml from entry order by nodenum asc");
my $sth = $dbh->prepare("select root,broot,page,word,bword,nodeid,perseusxml from entry where nodeid=\"n9430\" order by nodenum asc");
$sth->execute();
my ($root,$broot,$page,$word,$bword);
my $node;
my $xml;
my $total = 0;
  $sth->bind_columns(\$root,\$broot,\$page,\$word,\$bword,\$node,\$xml);
while($sth->fetch) {
#   print decode("UTF-8",$xml);
  my ($ret,$t) = perseus($node,$xml);
  if ($ret > 0) {
    $total += $ret;
    print sprintf "%s %s %s %s %s V%d/%d,\n%s",$broot,decode("UTF-8",$root),$bword,decode("UTF-8",$word),$node,getVolForPage($page),$page,$t;
  }
}
print "Total $total\n";