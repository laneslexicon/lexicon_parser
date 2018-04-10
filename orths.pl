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
my %requirenodes;
my $dbh;
my $logDir;
my $dbname;
my $xmlfile;
my $xmlsource;
my $verbose=0;
my $export=0;
my $inputnode = "";
my $nodefile = "";
my $buckwalter=0;
my $showxml=0;
my $dryrun=0;
my $arrowCount=0;
my $report = 0;
my $broken = 0;
my $lh;
my $lq;
my $writeCount = 0;
my $updateCount = 0;
my $showtext = 0;
my $withword = 0;
my $backup = 0;
my $outfile;
my %np;
my %notfixed;
my $showhelp = 0;
my $logdir;
my $logfh;
my $inputdb;
my $outputdb;
my $updaterun = 0;
my $processcount = 0;
my $commitCount = 500;
my $allnodes = 0;
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
#   Viewing the <orth> as the center
#   any following node containing a-z is a break
#   O   = <orth>
#   F   = <foreign>
#   For text fields, we have
#   W = trailing node ending down arrow but with other text functioning as a break
#   P = trailing node ending down arrow but with brackets
#   S = spaces with a down arrow
#   T = spaces without a down arrow

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
  my $t = "";
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
    $linkid = $orth->getAttribute("orthid");
    if (! $linkid ) {
      print STDERR sprintf "%s %d : <orth> has no link id, terminating\n",$nodes->[0]->getAttribute("id"),$orthindex;
      exit 0;
    }
    $t .= sprintf "%-10s  %2d  %-15s ",$linkid,$orthindex,":$p:";
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
    if (length($p) ne scalar(@n)) {
      print STDERR "Pattern error\n";
      exit;
    }

      # for updates we need to read the link record and set the @target attribute appropriately
    my $tonode;
    #  this is not an update, but --report can be run without a db
    if ($updaterun) {
      $lq->bind_param(1,$linkid);
      $lq->execute();
      if ($lq->err ) {
        print STDERR "Error unable to query link record " . $lq->err . " error: " . $lq->errstr . "\n";
      } else {
        my $rec = $lq->fetchrow_hashref;
        if (exists $rec->{tonode}) {
          if (defined $rec->{tonode} && (length($rec->{tonode}) > 0)) {
            $tonode =$rec->{tonode};
          }
        }
      }
    }

    $fixtype = fixEntry($orthindex,$p,$tonode,@n);
    if ($fixtype == 0) {
      if (! exists $notfixed{$p} ) {
        $notfixed{$p} = 0;
      }
      $notfixed{$p} = $notfixed{$p} + 1;
    }
    $t .= "[$fixtype]" . "\n";
    $t .= $vtext if $verbose;
    if ($updaterun ) {
      $lh->bind_param(1,$fixtype);
      $lh->bind_param(2,$p);
      $lh->bind_param(3,$orthindex);
      $lh->bind_param(4,$linkid);
      $lh->execute();
      if ($lh->err ) {
        print STDERR "Error unable to update link record, terminating " . $lh->err . " error msg: " . $lh->errstr . "\n";
        exit 0;
      }
      else {
        $writeCount++;
      }
    }
#    $t .= "\n";
    # return the fixed xml
  }
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
  my $tonode = shift;
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
  my $fixtype = 0;     # not fixed
  if ($seq =~ /^WO$|^O$|^SO$/) {
    $ix = index $seq,"O";
    my $orth = $nodes[$ix];
    $fixtype = 1;
    $linkid = $orth->getAttribute("orthid");
    $linktext = $orth->textContent;
    my @words = split /\s+/,$linktext;
    $linkword = $words[$#words];
    $linkword = pop @words;
    $linktext = join ' ',@words;
    $linktext .= " ";
    my $foreign = XML::LibXML::Element->new("foreign");
    $foreign->setAttribute("lang","ar");
    #    if (scalar(@words) > 0) {
    #      $foreign->appendText(join ' ',@words);
    #    }
    $foreign->appendText($linktext);
    my $refnode = XML::LibXML::Element->new("ref");
    $refnode->setAttribute("cref",$linkid);
    $refnode->setAttribute("target",$linkword);
    $refnode->setAttribute("n",$orthindex);
    $refnode->setAttribute("type",$fixtype);
    $refnode->setAttribute("subtype",$seq);
    $refnode->setAttribute("lang","ar");
    $refnode->setAttribute("select",$tonode) if $tonode;
    $foreign->appendChild($refnode);
    my $parent = $orth->parentNode;
    $parent->replaceChild($foreign,$orth);

  }
  # this is just where the preceding Arabic is not contiguous but
  # does end in things like ])., so we have to force the text direction
  # the XSLT will do that, so we just insert an <anchor> tag after the ]) etc so it knows
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
    $linkid = $orth->getAttribute("orthid");
    $linktext = $orth->textContent;
    my @words = split /\s+/,$linktext;
    $linkword = $words[$#words];
    $linkword = pop @words;
    $linktext = join ' ',@words;
    $linktext .= " ";
    my $foreign = XML::LibXML::Element->new("foreign");
    $foreign->setAttribute("lang","ar");
    my $refnode = XML::LibXML::Element->new("ref");
    $refnode->setAttribute("cref",$linkid);
    $refnode->setAttribute("target",$linkword);
    $refnode->setAttribute("n",$orthindex);
    $refnode->setAttribute("type",$fixtype);
    $refnode->setAttribute("subtype",$seq);
    $refnode->setAttribute("lang","ar");
    $refnode->setAttribute("select",$tonode) if $tonode;

    $foreign->appendText($linktext);
    $foreign->appendChild($refnode);

#    $foreign->appendChild($refnode);
#    $foreign->appendText($linktext);

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
    $linkid = $orth->getAttribute("orthid");
    $linktext = $orth->textContent;
    my @words = split /\s+/,$linktext;
    $linkword = $words[$#words];
    $linkword = pop @words;
    $linktext = join ' ',@words;
    $linktext .= " ";
    my $foreign = XML::LibXML::Element->new("foreign");
    $foreign->setAttribute("lang","ar");
    my $refnode = XML::LibXML::Element->new("ref");
    $refnode->setAttribute("cref",$linkid);
    $refnode->setAttribute("target",$linkword);
    $refnode->setAttribute("n",$orthindex);
    $refnode->setAttribute("type",$fixtype);
    $refnode->setAttribute("subtype",$seq);
    $refnode->setAttribute("lang","ar");
    $refnode->setAttribute("select",$tonode) if $tonode;
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
    $linkid = $orth->getAttribute("orthid");
    $linktext = $orth->textContent;
    my @words = split /\s+/,$linktext;
    $linkword = $words[$#words];
    $linkword = pop @words;
    $linktext = join ' ',@words;
    $linktext .= " ";
    my $foreign = XML::LibXML::Element->new("foreign");
    $foreign->setAttribute("lang","ar");


    my $refnode = XML::LibXML::Element->new("ref");
    $refnode->setAttribute("cref",$linkid);
    $refnode->setAttribute("target",$linkword);
    $refnode->setAttribute("n",$orthindex);
    $refnode->setAttribute("select",$tonode) if $tonode;
    if ($seq =~ /L/) {
      $foreign->appendText($foreigntext);
      $foreign->appendText(" ");
      $foreign->appendText($linktext);
      $foreign->appendChild($refnode);
      $fixtype = 4;
    } else {
      $foreign->appendText($linktext);
      $foreign->appendChild($refnode);
      $foreign->appendText($foreigntext);
      $fixtype = 5;
    }
    $refnode->setAttribute("type",$fixtype);
    $refnode->setAttribute("subtype",$seq);
    $refnode->setAttribute("lang","ar");
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
    $linkid = $orth->getAttribute("orthid");
    $linktext = $orth->textContent;
    my @words = split /\s+/,$linktext;
    $linkword = $words[$#words];
    $linkword = pop @words;
    $linktext = join ' ',@words;
    $linktext .= " ";
    my $foreign = XML::LibXML::Element->new("foreign");
    $foreign->setAttribute("lang","ar");


    my $refnode = XML::LibXML::Element->new("ref");
    $refnode->setAttribute("cref",$linkid);
    $refnode->setAttribute("target",$linkword);
    $refnode->setAttribute("n",$orthindex);
    $refnode->setAttribute("select",$tonode) if $tonode;
    $foreign->appendText("$foreignbefore ");
    $foreign->appendText($linktext);
    $foreign->appendChild($refnode);
    $foreign->appendText(" $foreignafter");


    $refnode->setAttribute("type",$fixtype);
    $refnode->setAttribute("subtype",$seq);
    $refnode->setAttribute("lang","ar");
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
      $linkid = $orth->getAttribute("orthid");
      $linktext = $orth->textContent;
      my @words = split /\s+/,$linktext;
      $linkword = $words[$#words];
    $linkword = pop @words;
    $linktext = join ' ',@words;
    $linktext .= " ";
      my $foreign = XML::LibXML::Element->new("foreign");
      $foreign->setAttribute("lang","ar");
      my $refnode = XML::LibXML::Element->new("ref");
      $refnode->setAttribute("cref",$linkid);
      $refnode->setAttribute("target",$linkword);
      $refnode->setAttribute("n",$orthindex);
      $refnode->setAttribute("lang","ar");
      $refnode->setAttribute("type",$fixtype);
      $refnode->setAttribute("subtype",$seq);
      $refnode->setAttribute("select",$tonode) if $tonode;
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
  } elsif ($seq eq "FSOTF") {
    # this code assumes that we have is the Arabic <foreign> followed by  <orth> text going to the end of line
    # and the new line starts with Arabic which is tagged with foreign
    # So if we have visually : F1O1F2
    # The sequence should be : O1F1F2

    $fixtype = 8;
    my $max = length($seq) - 1;
    my $foreigntext = "";
    my $ix = index $seq,"O";

    my $orth = $nodes[$ix];
    $linkid = $orth->getAttribute("orthid");
    $linktext = $orth->textContent;
    my @words = split /\s+/,$linktext;
    $linkword = pop @words;
    $linktext = join ' ',@words;
    $linktext .= " ";

    my $foreign = XML::LibXML::Element->new("foreign");
    $foreign->setAttribute("lang","ar");

    my $refnode = XML::LibXML::Element->new("ref");
    $refnode->setAttribute("cref",$linkid);
    $refnode->setAttribute("target",$linkword);
    $refnode->setAttribute("n",$orthindex);
    $refnode->setAttribute("type",$fixtype);
    $refnode->setAttribute("subtype",$seq);
    $refnode->setAttribute("lang","ar");
    $refnode->setAttribute("select",$tonode) if $tonode;

    $foreign->appendText($linktext);
    $foreign->appendChild($refnode);

    # get the first foreign, we are going to replace this with our own
    my $f = shift @nodes;

    my $parent = $f->parentNode;

    $foreigntext .= $f->textContent;
    my $n = $nodes[$#nodes];
    $foreigntext .= " " . $n->textContent;

    $foreign->appendText($foreigntext);

    for (my $i=0;$i <= $#nodes;$i++) {
      $parent->removeChild($nodes[$i]);
    }
    $parent->replaceChild($foreign,$f);

  } else {
    $ix = index $seq,"O";
    my $orth = $nodes[$ix];
    $fixtype = 0;
    $linkid = $orth->getAttribute("orthid");
    $linktext = $orth->textContent;
    my @words = split /\s+/,$linktext;
    $linkword = $words[$#words];
    $linkword = pop @words;
    $linktext = join ' ',@words;
    $linktext .= " ";
    my $foreign = XML::LibXML::Element->new("foreign");
    $foreign->setAttribute("lang","ar");
    my $refnode = XML::LibXML::Element->new("ref");
    $refnode->setAttribute("cref",$linkid);
    $refnode->setAttribute("target",$linkword);
    $refnode->setAttribute("n",$orthindex);
    $refnode->setAttribute("type",$fixtype);
    $refnode->setAttribute("subtype",$seq);
    $refnode->setAttribute("lang","ar");
    $refnode->setAttribute("select",$tonode) if $tonode;
    $foreign->appendChild($refnode);
    $foreign->appendText($linktext);
    my $parent = $orth->parentNode;
    $parent->replaceChild($foreign,$orth);
  }
  return $fixtype;
}
################################################################
#  buckwalter conversion
#
################################################################
sub convertString {
  my $t = shift;

  my $s = $t;


  $t =~ s/^\s+//;
  $t =~ s/\s+$//;

  if ($t =~ /^\d+$/) {
    return $t;
  }
    if ($t =~ /\?\?/) {
#      return $t;
    }
    # convert all A@ to { for alef wasl
    if ($t =~ /A@/) {
      $t =~ s/A@/{/g;
    }
    if ($t =~ /A_/) {
      $t =~ s/A_/I/g;
    }
    if ($t =~ /A\^/) {
      $t =~ s/A\^/O/g;
    }
    if ($t =~ /y\^/) {
      $t =~ s/y\^/}/g;
    }
    if ($t =~ /w\^/) {
      $t =~ s/w\^/W/g;
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


  return $t;
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
    $r = sprintf "<sense type=\"%s\" n=\"%d\">%s</sense>",$t,$n,$s;
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
##
#n this does the same as lane.pl does when it loads the database but WITHOUT any of the checks
#
#
##
sub convertNode {
  my $nodeid = shift;
  my $node = shift;

  # convert arabic
  my $bword = $node->getAttribute("key");
  $node->setAttribute("key",convertString($bword));
  my @ars = $node->findnodes('.//*[@lang="ar"]');
  foreach my $ar (@ars) {
    my $t = $ar->textContent;
    my $a = convertString($t);

    my @cn = $ar->childNodes();
    if (scalar(@cn) == 1) {
      my  $text = XML::LibXML::Text->new( $a );
      $ar->replaceChild($text,$cn[0]);
    }
#    print sprintf "%10s %10s %5d %s\n",$root,$ar->nodeName,scalar(@cn),$t;
  }
  # set orthid
  my $ix = 1;
  my @orths = $node->findnodes('.//orth[@type="arrow"]');
  foreach my $orth (@orths) {
    $orth->setAttribute("orthid",sprintf "%s-%s",$nodeid,$ix);
    $ix++;
  }

  my $xml = $node->toString();
  $xml = insertSenses($xml);
  $xml = insertTropical($xml);
  return { xml => $xml,id => $nodeid,word => $bword};
}
#
# as long as the entry is simple this works
#
#
sub processPerseusFile {
  my $filename = shift;

  my $writeCount = 0;
  my %targetnodes;
  if (! -e $filename ) {
    print STDERR "Requested Perseus xml file not found:$filename\n";
    exit 0;
  }
  my $fq = $dbh->prepare("select id,xml from entry where nodeid = ?");
  if ( $fq->err ) {
    die "ERROR executing node find SQL:" . $fq->err . " error msg: " . $fq->errstr . "\n";
    exit 0;
  }
  my $uq = $dbh->prepare("update entry set xml = ? where id = ?");

  my $checknode = scalar(keys %requirenodes);
  my $outfh;
  if ($outfile && ($outfile !~ /NODE/)) {
    open $outfh,">:encoding(UTF8)", $outfile or die "Cannot open output file: $outfile\n";
    print $outfh "<updates>\n";
  }


  my $parser = XML::LibXML->new;
  $parser->set_options("line_numbers" => "parser","suppress_errors" => 1);
  #  my $parser = new XML::DOM::Parser;
  my $doc = $parser->parse_file($filename);
  $doc->setEncoding("UTF-8");
  my @nodes = $doc->getElementsByTagName ("entryFree");
  my $ok;
  print STDERR "Processing file:$filename\n" if $verbose;
  foreach my $node (@nodes) {
    $ok = 1;
    my $nodeid = $node->getAttribute("id");
    if (! $nodeid ) {
      $ok = 0;
    }
    elsif ($checknode) {
      $ok = exists $requirenodes{$nodeid};
    }
    if ($ok) {
      #
      # get the key attribute, if this contains arabic then assume we have processed this file
      # before and skip the conversion from Perseus to our format
      #
      if ($outfile && ($outfile =~ /NODE/)) {
        my $f = $outfile;
        $f =~ s/NODE/$nodeid/;
        open $outfh,">:encoding(UTF8)", $f or die "Cannot open output file: $f\n";
      }
      my $ret;
      my $key = $node->getAttribute("key");
      if ($key =~ /(\p{InArabic}+)/) {
        $ret = { xml => $node->toString,id => $nodeid,word => $key};
      }
      else {
        $ret = convertNode($nodeid,$node);
      }
      #
      # check we have a matching node, otherwise nothing to update
      #
      $fq->bind_param(1,$nodeid);
      $fq->execute;
      if ( $fq->err ) {
        die "ERROR executing node find SQL:" . $fq->err . " error msg: " . $fq->errstr . "\n";
        exit 0;
      }
      my $rec = $fq->fetchrow_hashref;
      if (! $rec ) {
        print STDERR "Cannot find matching node in entry table, update failed\n";
      }
      else {
        my $f = processEntry($ret->{xml});
        print $logfh $f->{text};
        if ($outfile) {
          print $outfh $f->{xml};
          if ($outfile =~ /NODE/) {
            close $outfh;
          }
        }
        if ( $updaterun ) {
            if ($backup) {
              open OUT,">$nodeid.xml.back";
              binmode OUT,":encoding(UTF-8)";
              print OUT decode("UTF-8",$rec->{xml});
              close OUT;
            }
            $uq->bind_param(1,$f->{xml});
            $uq->bind_param(2,$rec->{id});
            $uq->execute;
            if ( $uq->err ) {
              die "ERROR executing node update SQL:" . $uq->err . " error msg: " . $uq->errstr . "\n";
              exit 0;
            }
            $writeCount++;
          }
        }
    } else {
      #print STDERR sprintf "entry at line %d has no id, cannot convert\n",$node->line_number();
    }
  }
  if ($writeCount > 0) {
    $dbh->commit;
  }
  if ($outfile && ($outfile !~ /NODE/)) {
    print $outfh "</updates>\n";
    close $outfh;
  }
  return;
}
sub writeOutputXml {
  my $nodeid = shift;
  my $oldXml = shift;
  my $newXml = shift;

  if (length($outfile) == 0) {
    return;
  }
  my $filename = $outfile;
  if ($filename =~ /NODE/) {
    $filename =~ s/NODE/$nodeid/;
    open OUT, ">$filename" or die "Cannot open output file: $filename\n";
    binmode OUT, ":utf8";
    print OUT $newXml;
    close OUT;
    return;
  }
  if ($processcount == 0) {
  }
  open OUT, ">>$filename" or die "Cannot open output file: $filename\n";
  binmode OUT, ":utf8";
  print OUT $newXml;
  close OUT;
  $processcount++;
}
sub processDatabase {

  my $xml;
  my $id;
  my $writeCount = 0;
  my %targetnodes;

  my $fq = $dbh->prepare("select id,xml,nodeid from entry order by nodenum asc");
  if ( $fq->err ) {
    die "ERROR executing node find SQL:" . $fq->err . " error msg: " . $fq->errstr . "\n";
    exit 0;
  }
  my $uq = $dbh->prepare("update entry set xml = ? where id = ?");


  my $parser = XML::LibXML->new;
  $parser->set_options("line_numbers" => "parser","suppress_errors" => 1);

  #
  #
  #
  $fq->execute();
  while (my @entries = $fq->fetchrow_array()) {
    if (scalar(@entries) < 2) {
      next;
    }
    $xml = $entries[1];
    $id = $entries[0];
    #  my $parser = new XML::DOM::Parser;
    my $doc = $parser->parse_string($xml);
    $doc->setEncoding("UTF-8");
    my @nodes = $doc->getElementsByTagName ("entryFree");
    my $ok;

    foreach my $node (@nodes) {
      $ok = 1;
#      print STDERR $xml . "\n\n";
      my $f = processEntry($xml);
      if ($f->{orths} > 0) {
        print $logfh $f->{text};
        if ( $updaterun ) {
#          print STDERR $f->{xml} . "\n\n";
#          printf STDERR "Updating node:%s %s\n",$entries[2],$f->{text} if $verbose;
          $uq->bind_param(1,$f->{xml});
          $uq->bind_param(2,$id);
          $uq->execute;
          if ( $uq->err ) {
            die "ERROR executing node update SQL:" . $uq->err . " error msg: " . $uq->errstr . "\n";
            exit 0;
          }
          $writeCount++;
        } else {
          #print STDERR sprintf "entry at line %d has no id, cannot convert\n",$node->line_number();
        }
      }
    }
    if ($writeCount > $commitCount) {
      $dbh->commit;
      $writeCount = 0;
    }
  }
  if ($writeCount > 0) {
    $dbh->commit;
    $writeCount = 0;
  }
  return;
}
sub report {
  my $filename = shift;

  my $writeCount = 0;
  my %targetnodes;
  if (! -e $filename ) {
    print STDERR "Requested Perseus xml file not found:$filename\n";
    exit 0;
  }
  my $checknode = scalar(keys %requirenodes);

  my $text;

  $updaterun = 0;
  $dryrun = 1;
  my $parser = XML::LibXML->new;
  $parser->set_options("line_numbers" => "parser","suppress_errors" => 1);
  #  my $parser = new XML::DOM::Parser;
  my $doc = $parser->parse_file($filename);
  $doc->setEncoding("UTF-8");
  my @nodes = $doc->getElementsByTagName ("entryFree");
  my $ok;
  my $notfixed = 0;
  foreach my $node (@nodes) {
    $ok = 1;
    my $nodeid = $node->getAttribute("id");
    if (! $nodeid ) {
      $ok = 0;
    }
    elsif ($checknode > 0) {
      $ok = exists $requirenodes{$nodeid};
    }
    if ($ok) {
      #
      # get the key attribute, if this contains arabic then assume we have processed this file
      # before and skip the conversion from Perseus to our format
      #
      my $ret;
      my $key = $node->getAttribute("key");
      if ($key =~ /(\p{InArabic}+)/) {
        $ret = { xml => $node->toString,id => $nodeid,word => $key};
      }
      else {
        $ret = convertNode($nodeid,$node);
      }
      print $ret->{xml} . "\n" if $showxml;
      my $f = processEntry($ret->{xml});
      #  return {xml => $nodes->[0]->toString,orths => scalar(@orths), text => $t};
      print $f->{xml} . "\n" if $showxml;
      if ($f->{orths} > 0) {
        my @l = split '\n',$f->{text};
        foreach my $line (@l) {
          if ($line =~ /\[0\]/) {
            $notfixed++;
            print "$line\n";
          }
          else {
            print "$line\n" unless $broken;
          }
        }
      }
    }
  }
  return $notfixed;
}
sub isNode {
  my $t = shift;

  $t =~ s/^\s+//g;
  $t =~ s/\s+$//g;
  if ($t =~ /^[0-9]+$/) {
    return  sprintf "n$t";
  }
  if ($t =~ /^n[0-9]+$/) {
    return $t;
  }
  return undef;
}
sub setupNodes {
  my $node;

  if ($inputnode =~ /,/) {
    my @a = split /,/,$inputnode;
    foreach my $x (@a) {
      $node = isNode($x);
      $requirenodes{$node} = 1 if defined $node;
    }
  }
  else {
    $node = isNode($inputnode);
    $requirenodes{$node} = 1 if defined $node;
  }

  if ($nodefile) {
    if (! -e $nodefile ) {
      print STDERR "Cannot find node file $nodefile\n";
      return;
    }
  }
  else {
    return;
  }
  open IN, "<$nodefile" or die "error opening node file $@\n";
  while(<IN>) {
    chomp;
    $node = isNode($_);
    $requirenodes{$node} = 1 if defined $node;
  }
  close IN;

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
#
# To generate a report, not doing any updates,fixes etc
#
# perl orths.pl --db 151119.sqlite --dry-run
#
# (add --verbose to see the orth related text
#
# To import a 'raw' perseus entry, process the xml and fix the orth entries:
# (Note: this will only work with a 'regular' <entryFree> chunk. None of the exceptions
# that are handled by the horribly messy lane.pl routines
#
#  It creates a backup fle n1128.xml.back which can be reloaded into the database.
#
# perl orths.pl --db 151119.sqlite --perseus n1128.xml
#
# To update a database with a fixed link e.g one with <lb/> added:
#
# perl orths.pl --db lexicon.sqlite --perseus ../xml/_A0.xml --node n1126

# To show all info an a node:
# --xml /tmp/b0.xml --node n2033 --report --verbose --show
#
#  To show broken for all xml files:
#
#--report --xml ../xml  --broken
##########################################################################

GetOptions(
           "db=s" => \$inputdb,
           "dbout=s" => \$outputdb,
           "xml-out=s" => \$outfile,
           "verbose" => \$verbose,
           "node=s" => \$inputnode,
           "nodes=s" => \$nodefile,
           "show" => \$showxml,
           "dry-run" => \$dryrun,
           "log-dir=s" => \$logdir,
           "very" => \$showtext,
           "export" => \$export,
           "with-word" => \$withword,
           "buck" => \$buckwalter, # show buckwalter transliteration, development only
           "help" => \$showhelp,
           "xml=s" => \$xmlfile,
           "backup" => \$backup,
           "report" => \$report,
           "broken" => \$broken,
           "all"    => \$allnodes

          );
if ($showhelp) {
  print STDERR <<EOF;
perl orths.pl
\t--db   <db file>            Name of input database
\t--dbout <db file>           Name of output database if different (optional)
\t--node                      Process only the given node or comma separated list of nodes
\t--nodes <filename>          Process the nodes listed one per line in the supplied file
\t--log-dir                   Write log file to given directory, defaults to current
\t--dry-run                   Do not update the database
\t--xml-out  <output file>    Output fixed XML as either one file or individual files if the supplied
\t                            names contains NODE, with NODE being replaced by the actual node id
\t--show                      Show the before/after XML
\t--export                    Export the current link table records before updating
\t--verbose                   Show relevant node text in log
\t--xml                       XML source file or directory
\t--backup                    Create a backup copy of each node before updating
\t--all                       Do all nodes in the database
\t--help                      Print this


Use cases

1. To report on all the <orths> in a file

    perl orths.pl --report --xml ../xml/b0.xml

2. To show the original XML,the fixed XML and orth analysis for a node

    perl orths.pl --report --xml ../xml/b0.xml --node n2033 --show

3. To generate a fixed file for a node

   perl orths.pl --db lexicon.sqlite --xml ../xml/b0.xml --node n2033 --dry-run --xml-out fixed.xml

4. To apply corrected xml directly to the database

   perl orths.pl --db lexicon.sqlite --xml ../xml/b0.xml --node n2033

EOF
  exit 1;

}
#
$updaterun = ! $dryrun;
setupNodes();
#
# report does not need a database
#
if ($report) {
  my @arr;
  if (-d $xmlfile) {
    find sub { if ((-f $_) && ($File::Find::name =~ /xml$/))  {  push @arr,$File::Find::name; } }, $xmlfile;
  }
  elsif (-e $xmlfile ) {
    push @arr, $xmlfile;
  }
  my $total = 0;
  foreach my $file (@arr) {
    my $count = report($file);
    print "$file   not fixed : $count\n";
    $total += $count;
  }
  if (scalar(@arr) > 1) {
    print "Total not fixed : $total\n";
  }
  exit 0;
}
if (! $inputdb ) {
  print STDERR "No input database name supplied, use --db <name of sqlite db>,terminating\n";
  exit 0;
}
if ($inputdb && ! -e $inputdb ) {
  print STDERR "Database not found : $inputdb,terminating\n";
  exit 0;
}
if ( $updaterun ) {
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
  ###### TODO makes this Windows compat
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
my $logfile;
if ($inputnode && ($inputnode !~ /,/)) {
  $logfile = File::Spec->catfile($logdir,"orths$inputnode.log");
}
else {
  $logfile = File::Spec->catfile($logdir,"orths.log");
}
print STDERR "Writing log entryies to $logfile\n" if $verbose;
open($logfh,">:encoding(UTF8)",$logfile) or die "Cannot open logfile $@\n";
if ($logdir eq getcwd()) {
  print $logfh sprintf "<orth> report for dbid %s\n\n",$dbid;
}
#
# the perseus process routines need this to set the @select
#
$lq = $dbh->prepare("select * from links where orthid = ?");
$lh = $dbh->prepare("update links set orthfixtype = ?,orthpattern = ?,orthindex = ? where linkid = ?");
#
# A single Perseus format file containing an entry. Actually this would work
# for an entire Perseus file but it would break stuff because we are skipping
# a lot of the validation checks in lane.pl
#
# Only do this for entries you know to be "standard"
#
if ($xmlfile) {
  if (! -e $xmlfile) {
    print STDERR "Cannot find the input XML file supplied : $xmlfile\n";
    exit 0;
  }
  processPerseusFile($xmlfile);
  print $logfh "\nOrth Patterns:\n";
  foreach my $p (sort keys %np) {
    print $logfh sprintf "%10s %d\n",$p,$np{$p};
  }
  print $logfh "Not fixed patterns\n";
  foreach my $p (sort keys %notfixed) {
    print $logfh sprintf "%10s %d\n",$p,$notfixed{$p};
  }
  exit 0;
}
if ($allnodes) {
  processDatabase();
}
exit 0;
