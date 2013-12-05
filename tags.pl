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
binmode STDERR, ":utf8";
binmode STDOUT, ":utf8";

my %tags;

################################################################
#
#
################################################################
sub processNode {
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
################################################################
#
#
################################################################
sub traverseNode {
  my $node = shift;

  while ($node) {
    if ($node->nodeType == XML_ELEMENT_NODE) {
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
sub parseFile {
  my $file = shift;
  my $parser = XML::LibXML->new;


  print STDERR "Parsing $file\n";
  my $doc = $parser->parse_file($file);

  my $root = $doc->documentElement;

  foreach my $child ($root->findnodes('text')) {
    if ($child->nodeType == XML_ELEMENT_NODE) {
      traverseNode($child);
    }
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
      parseFile($file);
    }

  };

  if ($@) {
    print STDERR "File::Find error opening directory:[$d]\n";
    return;
  }

}
sub test {
  my $xml;
  #$xml = "test/test_j0.xml";
  $xml = "xml/j0.xml";
  my $parser = XML::LibXML->new;
  my $doc = $parser->parse_file($xml);

  my $root = $doc->documentElement;

  foreach my $child ($root->findnodes('text')) {
    if ($child->nodeType == XML_ELEMENT_NODE) {
      traverseNode($child);
    }
  }
  printStatsCsv();
}
sub printStats {
  foreach my $key (sort keys %tags ) {
    print sprintf "%-20s %d\n",$key,$tags{$key}->{count};
    my $attr = $tags{$key}->{attr};
    foreach my $key (sort keys %{$attr} ) {
      if ($key !~ /^(root|n|id|key)$/) {
        print sprintf "     %-20s %s\n",$key,join ",",keys %{$attr->{$key}};
      } else {
        print sprintf "     %-20s %d items\n",$key,scalar (keys %{$attr->{$key}});
      }
    }
  }
}
sub printStatsCsv {
  foreach my $key (sort keys %tags ) {
    print sprintf "%s,%d,,\n",$key,$tags{$key}->{count};
    my $attr = $tags{$key}->{attr};
    foreach my $key (sort keys %{$attr} ) {
      if ($key !~ /^(root|n|id|key)$/) {
        print sprintf ",,%s,%s\n",$key,join ",",keys %{$attr->{$key}};
      } else {
        print sprintf ",,%s,%d items\n",$key,scalar (keys %{$attr->{$key}});
      }
    }
  }
}
sub scanAll {
  parseDirectory("./xml");
  printStatsCsv();

}

test();
#scanAll();
