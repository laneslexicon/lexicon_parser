#!/usr/bin/perl -w
use strict;
use XML::DOM;
use XML::Parser;
use Encode;
use utf8;
use DBI;

binmode STDOUT, ":utf8";
my $dbname="testjeem.sqlite";
my $db = DBI->connect("dbi:SQLite:$dbname","","") or die "couldn’t connect to db" . DBI->errstr;

my $alldb="lexicon.sqlite";
my $xref = DBI->connect("dbi:SQLite:$alldb","","") or die "couldn’t connect to db" . DBI->errstr;
#
#
#

sub getItem {
  my $key = shift;
  my $found = 0;
  my @ids;

  print "lookup [$key]\n";
  if (length $key == 1) {
    }
  my $sth = $xref->prepare(q{SELECT id,word,nodeId FROM itype where word =  ?; });
  $sth->execute($key);
  while (my @row = $sth->fetchrow_array) {
    print "found >>>> itype lookup id: $row[0]  word $row[1] node $row[2]\n";
    push @ids, $row[0];

    $found++;
  }
  $sth = $xref->prepare(q{SELECT id,word,nodeId FROM entry where word =  ?; });
  $sth->execute($key);
  while (my @row = $sth->fetchrow_array) {
    print "found >>>> entry lookup id: $row[0]  word $row[1] node $row[2]\n";
    $found++;
    push @ids, $row[0];

  }
  $sth = $xref->prepare(q{SELECT id,word FROM root where word =  ?; });
  $sth->execute($key);
  while (my @row = $sth->fetchrow_array) {
    print "found >>>> root lookup id: $row[0]  word $row[1]\n";
    push @ids, $row[0];
  }
  print sprintf "Key [%s] at: %s\n",$key, join ",", @ids;
  return $found;
}


my $roots = $db->selectall_arrayref("select id,word from root");
foreach my $row (@$roots) {
  my ($rootId,$root) = @$row;
  $root = Encode::decode('UTF-8', $root);
  my $itypes = $db->selectall_arrayref("SELECT itype,nodeId,word,xml FROM itype where rootId = $rootId");
  foreach my $ic (@$itypes) {
    my ($itype,$node,$word,$xml) = @$ic;
    $xml = Encode::decode('UTF-8', $xml);
    $node = Encode::decode('UTF-8', $node);
    $word = Encode::decode('UTF-8', $word);
    print "$root : $itype : $node : $word\n";
    if ($xml =~ /ee\s+([\p{InArabic}]+)\s+in\s+art\.\s+([\p{InArabic}]+)/) {
      print "see in:$1 in $2\n";
    }
    if ($xml =~ /ee\s+([\p{InArabic}]+)\./) {
      print "see. $1\n";
      getItem($1);
    }
    if ($xml =~ /ee\s+also\s+art\.\s*([\p{InArabic}]+)/) {
      print "see also art. $1\n";
      getItem($1);

    }

  }
  my $entries = $db->selectall_arrayref("SELECT nodeId,word,xml FROM entry where rootId = $rootId");
  foreach my $entry (@$entries) {
    my ($node,$word,$xml) = @$entry;
    $xml = Encode::decode('UTF-8', $xml);
    $word = Encode::decode('UTF-8', $word);
    $node = Encode::decode('UTF-8', $node);
    print "$root : $node  : $word\n";
    if ($xml =~ /see\.+<foreign lang="ar"/i) {
      print "foreign lookup\n";
    }
    if ($xml =~ /ee\s+([\p{InArabic}]+)\s+in\s+art\.\s+([\p{InArabic}]+)/) {
      print "$1 in $2\n";
    }
    if ($xml =~ /ee.+>([\p{InArabic}]+)<./) {
      print ">> see. $1\n";
      getItem($1);
    }
    if ($xml =~ /See\s+also\s+art.+([\p{InArabic}]+)/) {
      print "see also art. $1\n";
      getItem($1);
    }
    if ($node eq "n6623") {
      #        print $xml;

    }
    if ($xml =~ /See also art\..+>([\p{InArabic}]+)</) {
      my $key = $1;
      getItem($key);
    }
  }
}


$db->disconnect;
$xref->disconnect;

sub test() {

my $x = "See  مُنْجَابٌ in art.  مِجْوَبٌ";
my $count=0;
print "Length total:" . length $x;
for (my $i=0;$i < length $x;$i++) {
  my $c =  substr $x,$i,1;
  printf "%04x ",ord($c);
  if ( $c =~ /\p{InArabic}/) {
    $count++;
  }
}
print "arabic letter count $count\n";
if ($x =~ /([\p{InArabic}]+)/) {
  print "yep [$1]\n";
}
if ($x =~ /See\s+([\p{InArabic}]+)\s+in\s+art\.\s+([\p{InArabic}]+)/) {
  print "yep [$1][$2]\n";
}

my $y = "مُنْجَابٌ";

if ($y =~ /\p{isArabic}/) {
  print "\this one is\n";
}
my $z = "ddddd " . chr(0x635) . chr(0x636). chr(0x931);
if ($z =~ /([\p{InArabic}]+)/) {
  print "\nbut this one is\n";
  print $1;
}
print "Testing:\n\n";
$x = chr(0x62f) . chr(0x631) . chr(0x64a);
#$x = chr(0x64a) . chr(0x631) . chr(0x62f);
getItem($x);
my $sql = sprintf "SELECT * FROM root WHERE word = %s", $xref->quote($x);
print $sql;

getItem("درى");
}
