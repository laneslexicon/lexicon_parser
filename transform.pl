#!/usr/bin/perl
use strict;
use POSIX;
use Encode;
use utf8;
use DBI;
use File::Spec;
use File::Basename;
use File::Find;
use Data::Dumper;
use Getopt::Long;
use Time::HiRes qw( time );
use XML::LibXSLT;
use XML::LibXML;

my $dbh;
my $rootsth;
my $verbose = 1;
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
  $dbh->{AutoCommit} = 0;
  $rootsth = $dbh->prepare("select root,broot,word,bword,xml,page,itype from entry where broot = ? order by nodeId");
}

sub getXmlForRoot {
  my $root = shift;
  my $filename = shift;

  if ( ! $filename ) {
    $filename = $root;
  }
  $filename .= ".xml";
  $rootsth->bind_param(1,$root);
  $rootsth->execute();
    ### Retrieve the returned rows of data
#  print STDERR "Field count:" . $rootsth->{NUM_OF_FIELDS} . "\n";

  my @row;
  my $contents = "";
  my $aroot;

  while ( @row = $rootsth->fetchrow_array(  ) ) {
      $aroot = decode("UTF-8",$row[0]);
      $contents .= sprintf "<word buckwalter=\"%s\" ar=\"%s\" page=\"%d\" itype=\"%s\">\n",decode("UTF-8",$row[3]),decode("UTF-8",$row[2]),decode("UTF-8",$row[5]),$row[6];
      $contents .= decode("UTF-8",$row[4]);
      $contents .= "</word>\n";
  }
  my $xml  = sprintf "<root btext=\"%s\" text=\"%s\">\n",$root,$aroot;
  $xml .= $contents;
  $xml .= "</root>";
  open OUT ,">:encoding(UTF8)",$filename;
  print OUT $xml;
  close OUT;
}
binmode STDERR, ":utf8";
binmode STDOUT, ":utf8";
sub test {
 my $parser = XML::LibXML->new();
 my $xslt = XML::LibXSLT->new();

 my $source = $parser->parse_file('dxdr.xml');
 my $style_doc = $parser->parse_file('entry.xslt');

 my $stylesheet = $xslt->parse_stylesheet($style_doc);

 my $results = $stylesheet->transform($source);

 print $stylesheet->output_string($results);
}
sub getroots{
openDb("lexicon.sqlite");
getXmlForRoot("jwb");
getXmlForRoot("dxdr");
getXmlForRoot("ktb");
getXmlForRoot("j*f");
}

#test();
#getroots();
test();
