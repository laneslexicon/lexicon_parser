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
use Time::localtime;
my $dbh;
my $logDir;
my $dbname;
my $xmlfile;
my $verbose=0;
my $export=0;
my $node;
my $buckwalter=0;
my $showxml=0;
my $fixup=0;
my $dryrun=0;
my $arrowCount=0;
my $lh;
my $writeCount = 0;
my $updateCount = 0;
my $showtext = 0;
my $withword = 0;
my $outfile;
my %np;
my %notfixed;
my $showhelp = 0;
my $logdir;
my $logfh;
my $inputdb;
my $outputdb;
#
# sql variables
#
my $sth;
my $sql;
my $usql;
my $usth;
# record variables
my ($id,$root,$broot,$page,$word,$bword,$xml,$nodeid);
use List::Util qw( max );

sub max_depth {
  my ($ele) = @_;
  return 1 + max 0, map max_depth($_), $ele->findnodes('*');
}
binmode STDERR, ":encoding(UTF-8)";
binmode STDOUT, ":encoding(UTF-8)";
############################################################
#  copied from links.pk
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

  } else {
    if (! mkdir $base) {
      $base = dirname(tempdir());
    }
  }
  # try to create the subdirectory
  my $logdir = catfile($base,$id);
  if (-d $logdir) {
    return $logdir;
  }
  if ( mkdir $logdir) {
    return $logdir;
  }

  # couldn't create, so try create as subdirectory of current
  $logdir = catfile(getcwd(),$id);
  if (-d $logdir ) {
    return $logdir;
  } elsif ( mkdir $logdir) {
    return $logdir;
  }
  # couldn't do that either, so use the temporary directory
  # or the current working directory ignore the $dbid
  $logdir = catfile(dirname(tempdir()),$id);
  if (-d $logdir ) {
    return $logdir;
  } elsif ( mkdir $logdir) {
    return $logdir;
  }
  return getcwd();
}

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
  $dbh->{AutoCommit} = 0;
}
sub isBreak {
  my $t = shift;
  my $dx = shift;
  print $logfh ">>> [$t] <<<\n" if $showtext;
  if ($dx == 1) {
    if ($t =~ /[a-zA-Z]/) {
      return 1;
    }
  }
  if ($t =~ /↓\s*$/) {
    return 0;
  }
  $t =~ s/↓/ /;
  if ($t =~ /^\p{IsSpace}+$/) {
    return 0;
  }
  if ($t =~ /^\s*\,\s*$/) {
    return 0;
  }
  if ($t =~ /[a-zA-Z]/) {
    return 1;
  }

  return 1;
}
sub getSiblings {
  my $node = shift;
  my $dx = shift;
  my $uk = shift;
  my @orths;
  my $c = 0;
  my $nodeCount = 0;
  my $n;
  my @nodes;
  if ($dx == 1) {
    $n = $node->nextSibling;
  } else {
    $n = $node->previousSibling;
  }
  my $s = "";

  while ($n) {
    if ($n->nodeType == XML_TEXT_NODE) {
      my $t = $n->textContent;
      if (isBreak($t,$dx)) {
        last;
      } elsif ($t =~ /↓\s*$/) {
        push @nodes,$n;

        if ($t =~ /[a-zA-Z]+/) {
          $s .= "W";
          last;
        } elsif ($t =~ /^\p{IsSpace}*[\(\)\[\]\,\.]+\p{IsSpace}*↓/) {
          $s .= "P";
        } else {
          $s .= "S";
        }
      } else {
        push @nodes,$n;
        $s .= "T";
      }
    }
    if ($n->nodeType == XML_ELEMENT_NODE) {

      if ($n->nodeName !~ /foreign|orth|lb/) {
        last;
      }
      if (($n->nodeName eq "foreign") || ($n->nodeName eq "orth")) {
        if ($n->getAttribute("lang") !~ /ar/) {
          last;
        }
      }
      $s .= "O" if $n->nodeName eq "orth";
      $s .= "F" if $n->nodeName eq "foreign";
      $s .= "L" if $n->nodeName eq "lb";
      push @nodes,$n;
      $nodeCount++;
      #      if (($n->nodeName eq "orth") && ($n->getAttribute("type") eq "arrow")) {
      #        $uk->{$n->unique_key} = 1;
      #      }
    }
    if ($dx == 1) {
      $n = $n->nextSibling;
    } else {
      $n = $n->previousSibling;
    }
  }
  ## if we are reading nodes after the orth, we are not interested
  ## in trailing spaces text nodes
  if ($dx == 1) {
    while ($s =~ /T$/) {
      chop $s;
      $nodeCount--;
      pop @nodes;
    }
  }
  ## if we are reading backwards and all we have is a text node not containg English letters
  ## then just ignore it (it will be spaces with down arrow);
  if ($dx == -1) {
    $s = reverse $s;
    @nodes = reverse @nodes;
    #    if ($s =~ /^T$/) {
    #      $s = "";
    #    }
  }
  return {'nodes' => \@nodes, 'types' => $s};
}
sub processEntry {
  my $xml = shift;
  my $nxml;

  my $parser = XML::LibXML->new;
  $parser->set_options("line_numbers" => "parser","suppress_errors" => 1);
  #  my $parser = new XML::DOM::Parser;
  my $doc = $parser->parse_string($xml);
  $doc->setEncoding("UTF-8");
  my $nodes = $doc->getElementsByTagName ("entryFree");
  my @orths = $doc->findnodes('//orth[@type="arrow"]');
  my $orthindex = 0;
  my $t;
  my $fixtype = 0;
  my $linkid;
  foreach my $orth (@orths) {
    $orthindex++;
    my $nb = getSiblings($orth,-1); ## siblings before
    my $na = getSiblings($orth,1);  ## siblings after
    my $p = sprintf "%sO%s",$nb->{types},$na->{types};
    if (! exists $np{$p} ) {
      $np{$p} = 0;
    }
    $np{$p} = $np{$p} + 1;
    $linkid = $orth->getAttribute("linkid");
    if (! $linkid ) {
      print STDERR sprintf "%s %d : <orth> has no link id, terminating\n",$nodes->[0]->getAttribute("id"),$orthindex;
      exit 0;
    }
    $t .= sprintf "%6d  %2d  %-15s ",$linkid,$orthindex,":$p:";
    my @n = @{$nb->{nodes}};
    push @n , $orth;
    push (@n,@{$na->{nodes}});
    my $vtext = "";
    if ($verbose) {
      my $txt;
      foreach my $x (@n) {
        $txt .= $x->textContent;
      }
      $txt =~ s/\n//g;
      $vtext .= ">>>$txt<<<\n";
    }
    if ($fixup) {
      if (length($p) ne scalar(@n)) {
        print STDERR "Pattern error\n";
        exit;
      }
      $fixtype = fixEntry($orthindex,$p,@n);
      if ($fixtype == -1) {
        if (! exists $notfixed{$p} ) {
          $notfixed{$p} = 0;
        }
        $notfixed{$p} = $notfixed{$p} + 1;
      }
      $t .= "[$fixtype]" . "\n";
      $t .= $vtext if $verbose;
      #  $lh = $dbh->prepare("update links set orthfixtype = ?,orthpattern = ?,orthindex = ? where linkid = ?");
      if (! $dryrun ) {
        $lh->bind_param(1,$fixtype);
        $lh->bind_param(2,$p);
        $lh->bind_param(3,$orthindex);
        $lh->bind_param(4,$linkid);
        $lh->execute();
        if ($lh->err ) {
          print STDERR "Error unable to update link record, terminating " . $lh->err . " error msg: " . $lh->errstr . "\n";
          $dryrun = 1;
          exit 0;
        } else {
          $writeCount++;
        }
      }
    }
    else {
      $t .= "\n";
    }
  }

  # return the fixed xml
  return {xml => $nodes->[0]->toString,orths => scalar(@orths), text => $t};
}
#
# these are the possibilites (with one example of <lb/> ) :
#
# FTFSOSOTF 2
#        WO 30469
#   FSOTFSO 6
#      TFSO 241
#   FTFSOTF 1
#    WOTFTF 2
#     FTFSO 160
#    TFSOTF 7
#   FSOTLTF 1
#      WOSO 58
#         O 3
#    TFTFSO 5
#       FSO 3613
#    WOTFSO 6
#      WOTF 430
#        SO 803
#      SOTF 12
#     FTLSO 1
#     FSOSO 12
#     FSOTF 191
#      SOSO 12
#
# we want to change them to this:
#<foreign lang="ar">preceding text <ref cref="linkid" target="linkword"/> linkword and the following text</foreign>
#
sub fixEntry {
  my $orthindex = shift;
  my $seq = shift;
  my @nodes = @_;

  my $ix = 0;
  # remove the down arrow
  foreach my $node (@nodes) {
    my $p = substr $seq , $ix , 1;
    if ($p =~ /W|S/) {
      my $t = $node->textContent;
      $t =~ s/↓/ /g;
      $node->setData($t);
    }
    $ix++;
  }
  my $linkid;
  my $linktext;
  my $linkword;
  my $fixtype = -1;
  if ($seq =~ /^WO$|^O$|^SO$/) {
    $ix = index $seq,"O";
    my $orth = $nodes[$ix];
    $fixtype = 1;
    $linkid = $orth->getAttribute("linkid");
    $linktext = $orth->textContent;
    my @words = split /\s+/,$linktext;
    $linkword = $words[$#words];
    my $foreign = XML::LibXML::Element->new("foreign");
    $foreign->setAttribute("lang","ar");
    #    if (scalar(@words) > 0) {
    #      $foreign->appendText(join ' ',@words);
    #    }
    my $refnode = XML::LibXML::Element->new("ref");
    $refnode->setAttribute("cref",$linkid);
    $refnode->setAttribute("target",$linkword);
    $refnode->setAttribute("n",$orthindex);
    $refnode->setAttribute("type",$fixtype);
    $refnode->setAttribute("subtype",$seq);
    $foreign->appendChild($refnode);
    $foreign->appendText($linktext);
    my $parent = $orth->parentNode;
    $parent->replaceChild($foreign,$orth);

  }
  # this is just where the preceding Arabic is not contiguous but
  # does end in things like ])., so we have to force the text direction
  # the XSLT will do that, so we just insert an <anchor> tag so it knows
  # to do something
  elsif ($seq eq "FPO") {
    my $parent;
    $ix = index $seq, "P";
    my $punct = $nodes[$ix];
    my $t = $punct->textContent;
    $fixtype = 2;
    $t =~ s/↓/ /g;
    $punct->setData("$t");
    $parent = $punct->parentNode;
    my $kludgeNode = XML::LibXML::Element->new("anchor");
    $parent->insertAfter($kludgeNode,$punct);
    my $orth = $nodes[index "O",$seq];
    $linkid = $orth->getAttribute("linkid");
    $linktext = $orth->textContent;
    my @words = split /\s+/,$linktext;
    $linkword = $words[$#words];
    my $foreign = XML::LibXML::Element->new("foreign");
    $foreign->setAttribute("lang","ar");
    my $refnode = XML::LibXML::Element->new("ref");
    $refnode->setAttribute("cref",$linkid);
    $refnode->setAttribute("target",$linkword);
    $refnode->setAttribute("n",$orthindex);
    $refnode->setAttribute("type",$fixtype);
    $refnode->setAttribute("subtype",$seq);
    $foreign->appendChild($refnode);
    $foreign->appendText($linktext);
    $parent = $orth->parentNode;
    $parent->replaceChild($foreign,$orth);

  } elsif ($seq eq "PO") {
    $fixtype = 3;
    my $parent;
    $ix = index $seq, "P";
    my $punct = $nodes[$ix];
    my $t = $punct->textContent;
    $t =~ s/↓/ /g;
    $punct->setData("$t");
    $parent = $punct->parentNode;
    my $kludgeNode = XML::LibXML::Element->new("anchor");
    $parent->insertAfter($kludgeNode,$punct);
    my $orth = $nodes[index "O",$seq];
    $linkid = $orth->getAttribute("linkid");
    $linktext = $orth->textContent;
    my @words = split /\s+/,$linktext;
    $linkword = $words[$#words];
    my $foreign = XML::LibXML::Element->new("foreign");
    $foreign->setAttribute("lang","ar");
    my $refnode = XML::LibXML::Element->new("ref");
    $refnode->setAttribute("cref",$linkid);
    $refnode->setAttribute("target",$linkword);
    $refnode->setAttribute("n",$orthindex);
    $refnode->setAttribute("type",$fixtype);
    $refnode->setAttribute("subtype",$seq);
    $foreign->appendChild($refnode);
    $foreign->appendText($linktext);
    $parent = $orth->parentNode;
    $parent->replaceChild($foreign,$orth);

  } elsif ($seq =~ /^T*F[SLT]*O$/) {
    my $max = length($seq) - 1;
    my $foreigntext = "";
    for (my $i=0;$i < $max;$i++) {
      my $n = $nodes[$i];
      my $ntype = substr $seq,$i,1;
      if ($ntype eq "F") {
        $foreigntext .= $n->textContent;
      }
    }
    my $orth = $nodes[index "O",$seq];
    $linkid = $orth->getAttribute("linkid");
    $linktext = $orth->textContent;
    my @words = split /\s+/,$linktext;
    $linkword = $words[$#words];
    my $foreign = XML::LibXML::Element->new("foreign");
    $foreign->setAttribute("lang","ar");


    my $refnode = XML::LibXML::Element->new("ref");
    $refnode->setAttribute("cref",$linkid);
    $refnode->setAttribute("target",$linkword);
    $refnode->setAttribute("n",$orthindex);
    if ($seq =~ /L/) {
      $foreign->appendChild($refnode);
      $foreign->appendText($foreigntext);
      $foreign->appendText($linktext);
      $fixtype = 4;
    } else {
      $foreign->appendText($linktext);
      $foreign->appendChild($refnode);
      $foreign->appendText($foreigntext);
      $fixtype = 5;
    }
    $refnode->setAttribute("type",$fixtype);
    $refnode->setAttribute("subtype",$seq);
    my $parent = $orth->parentNode;
    for (my $i=0;$i < $max;$i++) {
      $parent->removeChild($nodes[$i]);
    }
    $parent->replaceChild($foreign,$orth);
  }
  #  these are strange as we have two adjecent <foreign>. This code assumes that
  #  there is a new line after the first text, so append everything to it.
  #
  elsif ($seq eq "FTFSO") {
    my $max = length($seq) - 1;
    $fixtype = 6;
    my $foreignbefore = $nodes[0]->textContent;
    my $foreignafter = $nodes[2]->textContent;
    $ix = index $seq, "O";
    my $orth = $nodes[$ix];
    $linkid = $orth->getAttribute("linkid");
    $linktext = $orth->textContent;
    my @words = split /\s+/,$linktext;
    $linkword = $words[$#words];
    my $foreign = XML::LibXML::Element->new("foreign");
    $foreign->setAttribute("lang","ar");


    my $refnode = XML::LibXML::Element->new("ref");
    $refnode->setAttribute("cref",$linkid);
    $refnode->setAttribute("target",$linkword);
    $refnode->setAttribute("n",$orthindex);
    $foreign->appendText("$foreignbefore ");
    $foreign->appendText($linktext);
    $foreign->appendChild($refnode);
    $foreign->appendText(" $foreignafter");


    $refnode->setAttribute("type",$fixtype);
    $refnode->setAttribute("subtype",$seq);
    my $parent = $orth->parentNode;
    for (my $i=0;$i < $max;$i++) {
      $parent->removeChild($nodes[$i]);
    }
    $parent->replaceChild($foreign,$orth);
  }
  # orth followed by foreign, append the foreign to the orth
  #
  # if we have two foreigns after the orth, then assume there is a line breaj
  # and keep appending
  #
  elsif ($seq =~ /^(W|P)O(TF)+$/) {
    $fixtype = 7;
    my $t;
    my $textafter = "";
    my $n;
    my $parent;
    if ($seq =~ /^P/) {
      $n = $nodes[0];
      $t = $n->textContent;
      $t =~ s/↓/ /g;
      $n->setData("$t");
      $parent = $n->parentNode;
      my $kludgeNode = XML::LibXML::Element->new("anchor");
      $parent->insertAfter($kludgeNode,$n);
    } else {
      $n = $nodes[0];
      $t = $n->textContent;
      $t =~ s/↓/ /g;
      $n->setData("$t");
    }
    $ix = index $seq,"O";
    my $orth = $nodes[$ix];
    if ($orth) {
      $linkid = $orth->getAttribute("linkid");
      $linktext = $orth->textContent;
      my @words = split /\s+/,$linktext;
      $linkword = $words[$#words];
      my $foreign = XML::LibXML::Element->new("foreign");
      $foreign->setAttribute("lang","ar");
      my $refnode = XML::LibXML::Element->new("ref");
      $refnode->setAttribute("cref",$linkid);
      $refnode->setAttribute("target",$linkword);
      $refnode->setAttribute("n",$orthindex);
      $foreign->appendText($linktext);
      $foreign->appendChild($refnode);
      $parent = $orth->parentNode;
      if ($parent) {
        my $startix = index $seq,"O";
        $startix++;
        my $max = length $seq;
        for (my $i=$startix;$i < $max;$i++) {
          if ($nodes[$i]->nodeName eq "foreign") {
            $textafter .= " " . $nodes[$i]->textContent;
          }
        }
        for (my $i=$startix;$i < $max;$i++) {
          $parent->removeChild($nodes[$i]);
        }
        $foreign->appendText($textafter);
        $parent->replaceChild($foreign,$orth);
      }
    }
  } else {
    $ix = index $seq,"O";
    my $orth = $nodes[$ix];
    $fixtype = -1;
    $linkid = $orth->getAttribute("linkid");
    $linktext = $orth->textContent;
    my @words = split /\s+/,$linktext;
    $linkword = $words[$#words];
    my $foreign = XML::LibXML::Element->new("foreign");
    $foreign->setAttribute("lang","ar");
    my $refnode = XML::LibXML::Element->new("ref");
    $refnode->setAttribute("cref",$linkid);
    $refnode->setAttribute("target",$linkword);
    $refnode->setAttribute("n",$orthindex);
    $refnode->setAttribute("type",$fixtype);
    $refnode->setAttribute("subtype",$seq);
    $foreign->appendChild($refnode);
    $foreign->appendText($linktext);
    my $parent = $orth->parentNode;
    $parent->replaceChild($foreign,$orth);
  }
  return $fixtype;
}
#################################################################
#
#  This never updates the database
#
#
#################################################################
sub processFile {
  my $filename = shift;

  if (! -e $filename ) {
    print STDERR "Supplied xml file not found:$filename\n";
    exit 0;
  }
  open IN,"<$filename";
  binmode IN,":encoding(UTF-8)";
  my $xml = "";
  while (<IN>) {
    $xml .= $_;
  }
  my $parser = XML::LibXML->new;
  $parser->set_options("line_numbers" => "parser","suppress_errors" => 1);
  #  my $parser = new XML::DOM::Parser;
  my $doc = $parser->parse_string($xml);
  $doc->setEncoding("UTF-8");
  my @nodes = $doc->getElementsByTagName ("entryFree");
  foreach my $node (@nodes) {
    my $nodeid = $node->getAttribute("id");
    my $word = $node->getAttribute("key");
    my $nodexml = $node->toString;
    print $logfh $nodexml if $showxml;
    #  perseus($xml);
    my $ret = processEntry($nodexml);
    print $logfh sprintf "\n\n%s %s \n%s\n",$nodeid,$word,$ret->{text} if $ret->{orths} > 0;
    print $logfh $ret->{xml} if $showxml;
    if ($outfile) {
      my $filename = $outfile;
      $filename =~ s/NODE/$nodeid/;
      open OUT,">$filename";
      binmode OUT, ":encoding(UTF-8)";
      print OUT "<word>" if $withword;
      print OUT $ret->{xml};
      print OUT "</word>" if $withword;
      close OUT;
    }
  }
  return;
}
sub processNode {
  my $xml = shift;

  my $ret = processEntry($xml);

  $arrowCount += $ret->{orths};
  print $logfh sprintf "%s %s %s\n%s\n",$nodeid,$broot,$bword,$ret->{text} if $ret->{orths} > 0;

  print $logfh $ret->{xml} if $showxml;
  if ($outfile) {
    my $filename = $outfile;
    $filename =~ s/NODE/$nodeid/;
    open OUT,">$filename";
    binmode OUT, ":encoding(UTF-8)";
    print OUT "<word>" if $withword;
    print OUT $ret->{xml};
    print OUT "</word>" if $withword;
    close OUT;
  }
  if ($fixup && ($xml ne $ret->{xml})) {
    # update xml
    if (! $dryrun ) {
      $usth->bind_param(1,$ret->{xml});
      $usth->bind_param(2,$id);
      $usth->execute();
      $writeCount++;
      if ( $usth->err ) {
        die "Update error $node :" . $usth->err . " error msg: " . $usth->errstr . "\n";
      }
    }
  }
  if ($writeCount > 500) {
    $dbh->commit;
    $updateCount += $writeCount;
    $writeCount = 0;
  }
}
##########################################################################
#
#   n208 has consecutive orths arrows
#   n5217 has mutliword arabic left and single word arabic left
#   n4900 (V2/371/7) has multiword 1st and middle has TFTF
#   Doing this on the output:
#   grep 'O[TF]*\] B' orths.txt | wc -l
#
#   reports 49 cases of 'consecutive' <orth type="arrow">
#
#   Ones that need fixing:
#   grep 'T*FT*\] B' orths.txt | wc -l
#   reports 4238 of <foreign> preceding an <orth type="arrow">
#
#   For <orths> followed by spaces and then <foreign>
#   grep 'A \[T*F' orths.txt | wc -l
#   reports 475
#
#   TFTF before needs handling  (there 176 of them. It looks like we have
#   arabic text with a new line + more text and then the orth
#
#
#
# To test in isolation, first generate the XML:
# >perl orths.pl --show --verbose --fix --dry-run --node n1126 --with-word --out n1126.xml
#
# Then test XLST from the shownode directory:
# >perl ./shownode.pl --xsl cref.xslt --xmlin ../mansur/parser/n1126.xml
##########################################################################

GetOptions(
           "db=s" => \$inputdb,
           "dbout=s" => \$outputdb,
           "file=s" => \$xmlfile,           # dev only
           "out-template=s" => \$outfile,            # dev only
           "verbose" => \$verbose,
           "node=s" => \$node,
           "show" => \$showxml,
           "dry-run" => \$dryrun,
           "log-dir=s" => \$logdir,
           "no-fix" => \$fixup,
           "very" => \$showtext,
           "export" => \$export,
           "with-word" => \$withword,
           "buck" => \$buckwalter, # show buckwalter transliteration, development only
           "help" => \$showhelp

          );
if ($showhelp) {
  print STDERR "perl orths.pl\n";
  print STDERR "\t--db              Name of input database (required)\n";
  print STDERR "\t--dbout           Name of output database if different (optional)\n";
  print STDERR "\t--node            Do <orths> for only the given node or comma separated list of nodes\n";
  print STDERR "\t--log-dir         Write log file to given directory, defaults to current\n";
  print STDERR "\t--dry-run         Do not update the database\n";
  print STDERR "\t--show            Show the before/after XML\n";
  print STDERR "\t--export          Export the current link table records before updating\n";
  print STDERR "\t--verbose         Show relevant node text in log\n";
  print STDERR "\t--no-fix          Just report on the orth entries, don't fix them\n";
  print STDERR "\t--with-word       (Development use : generating surround <word> tags in the output XML)\n";
  print STDERR "\t--out-template    Output XML using the supplied value as a filename template, replacing\n";
  print STDERR "\t                  the literal NODE by the node number\n;For example, --out-template test-NODE.xml\n";
  print STDERR "\t--help      print this\n";
  exit 1;

}
if ($xmlfile) {
  if (-e $xmlfile) {
    print STDERR "Cannot find the input XML file supplied : $xmlfile\n";
    exit 0;
  }
  my $logfile = File::Spec->catfile(getcwd(),"orths.log");
  open($logfh,">:encoding(UTF8)",$logfile) or die "Cannot open logfile $@\n";
  $dryrun = 1;                 # so we don't try to update link record
  processFile($xmlfile);
  exit 0;
}
#   /tmp/lexicon.sqlite is the 'clean' version
#
#
if (! $inputdb ) {
  print STDERR "No input database name supplied, use --db <name of sqlite db>,terminating\n";
  exit 0;
}
if ($inputdb && ! -e $inputdb ) {
  print STDERR "Database not found : $inputdb,terminating\n";
  exit 0;
}
if (! $dryrun ) {
  if ($export) {
    my $tm = localtime;
    my $sqlfile = sprintf "links-%04d-%02d-%02d.sql",$tm->year+1900,($tm->mon)+1,$tm->mday;
    my $fh = File::Temp->new(UNLINK => 0,TEMPLATE => "linksdumpXXXX"); #//tempfile();
    my $filename = $fh->filename;
    binmode $fh, ":utf8";
    print $fh ".open $inputdb\n";
    print $fh ".out $sqlfile\n";
    print $fh ".dump links\n";
    print $fh ".exit\n";
    $fh->close;
    system("sqlite3 < $filename");
    unlink $filename;
    if (! -e $sqlfile ) {
      print STDERR "Could not dump SQL,terminating\n";
      exit;
    }
  }
  if ($outputdb) {
    system("cp $inputdb $outputdb");
    openDb("$outputdb");
  } else {
    openDb("$inputdb");
  }
} else {
  openDb("$inputdb");
}
# get the dbid from the database
# if a directory is supplied, use the dbid as a subdirectory
# otherwise default to current
#

my $dbid;
eval {
  my $sth = $dbh->prepare("select dbid from lexicon");
  $sth->execute;
  my $rec = $sth->fetchrow_hashref;
  if ($rec) {
    $dbid = $rec->{dbid};
  }
};
if (!$dbid) {
  $logdir = getcwd();
}
if (! $logdir ) {
  $logdir = getcwd();
}
else {
  $logdir = getLogDirectory($logdir,$dbid);
}

#
# changed the option to from fix to no-fix, so flip it
#
if ($fixup) {
  $fixup = 0;
}
else {
  $fixup = 1;
}
my $logfile = File::Spec->catfile($logdir,"orths.log");
open($logfh,">:encoding(UTF8)",$logfile) or die "Cannot open logfile $@\n";
if ($logdir eq getcwd()) {
  print $logfh sprintf "<orth> report for dbid %s\n\n",$dbid;
}
#
#  prepare the update SQL
#

if (! $dryrun ) {
  $usql = "update entry set xml = ? where id = ?";
  $usth = $dbh->prepare($usql);
  if ( $usth->err ) {
    die "ERROR preparing update SQL:" . $usth->err . " error msg: " . $usth->errstr . "\n";
    exit 0;
  }
  $lh = $dbh->prepare("update links set orthfixtype = ?,orthpattern = ?,orthindex = ? where linkid = ?");
  if ( $lh->err ) {
    die "ERROR preparing update link SQL:" . $lh->err . " error msg: " . $lh->errstr . "\n";
    exit 0;
  }

}
if ($node) {
  $sql = sprintf "select id,root,broot,page,word,bword,nodeid,XML from entry where nodeid = ? order by nodenum asc";
}
else {
  $sql = "select id,root,broot,page,word,bword,nodeid,XML from entry order by nodenum asc";
}
#
# don't do this with a live DB
#
if ($buckwalter) {
  $sql =~ s/XML/perseusxml/;
} else {
  $sql =~ s/XML/xml/;
}

$sth = $dbh->prepare($sql);
if ( $sth->err ) {
    die "ERROR preparing node SQL:" . $sth->err . " error msg: " . $sth->errstr . "\n";
    exit 0;

  }

my @nodes;
if ($node) {
  @nodes = split /,/,$node;
  foreach my $n (@nodes) {
    if ($n !~ /^n\d+/) {
      $n = "n" . $n;
    }
    $sth->bind_param(1,$n);
    $sth->execute();
    if ( $sth->err ) {
      die "ERROR preparing node SQL:" . $sth->err . " error msg: " . $sth->errstr . "\n";
      exit 0;
    }
    $sth->bind_columns(\$id,\$root,\$broot,\$page,\$word,\$bword,\$nodeid,\$xml);
    $sth->fetch();
    processNode($xml);
  }
}
else {
  $sth->execute();
  $sth->bind_columns(\$id,\$root,\$broot,\$page,\$word,\$bword,\$nodeid,\$xml);
  while ($sth->fetch) {
    processNode($xml);
  }
}

if ($writeCount > 0) {
  $dbh->commit;
  $updateCount += $writeCount;
  $writeCount = 0;
}
print $logfh "Orth Patterns:\n";
foreach my $p (sort keys %np) {
  print $logfh sprintf "%10s %d\n",$p,$np{$p};
}
print $logfh "Not fixed patterns\n";
foreach my $p (sort keys %notfixed) {
  print $logfh sprintf "%10s %d\n",$p,$notfixed{$p};
}
