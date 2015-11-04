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
my $xmlfile;
my $verbose=0;
my $node;
my $buckwalter=0;
my $showxml=0;
my $maxerrors=0;
my $fixup=0;
my $dryrun=0;
my $showall=0;
my $fixCount=0;
my $arrowCount=0;
my $lh;
my $writeCount = 0;
my $updateCount = 0;
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
  $dbh->{AutoCommit} = 0;
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
sub isBreak {
  my $t = shift;

  if ($t =~ /^\s*↓\s*$/) {
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
sub checkSiblings {
  my $node = shift;
  my $dx = shift;
  my $uk = shift;
  my @orths;
  my $c = 0;
  my $nodeCount = 0;
  my $n;
  if ($dx == 1) {
    $n = $node->nextSibling;
  } else {
    $n = $node->previousSibling;
  }
  my $s = "";

  while ($n) {
    if ($n->nodeType == XML_TEXT_NODE) {
      my $t = $n->textContent;
      if (isBreak($t)) {
        last;
      }
      else {
        $s .= "T";
      }
    }
    if ($n->nodeType == XML_ELEMENT_NODE) {
      if ($n->nodeName !~ /foreign|orth/) {
        last;
      }
      if ($n->getAttribute("lang") !~ /ar/) {
        last;
      }
      $s .= "O" if $n->nodeName eq "orth";
      $s .= "F" if $n->nodeName eq "foreign";
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
    while($s =~ /T$/) {
      chop $s;
      $nodeCount--;
    }
  }
  ## if we are reading backwards and all we have is a text node not containg English letters
  ## then just ignore it (it will be spaces with down arrow);
  if ($dx == -1) {
    $s = reverse $s;
    if ($s =~ /^T$/) {
      $s = "";
    }
  }
  return {'nodes' => $nodeCount, 'types' => $s};
}
#
# get text for the supplied number of siblings before and after the supplied node
#
sub getText {
  my $node = shift;
  my $x = shift;              # nodes before
  my $y = shift;              # nodes after
  my $delim = shift;
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
  my $str = join $delim,@t;
  $str =~ s/\n//g;
  $str =~ s/\s+/ /g;
#  $str =~ s/↓/ /g;
  return $str;
}
#
# analyse a single entry (i.e. one entryFree)
#
sub perseus {
  my $xml = shift;


  my $parser = XML::LibXML->new;
  $parser->set_options("line_numbers" => "parser","suppress_errors" => 1);
  #  my $parser = new XML::DOM::Parser;
  my $doc = $parser->parse_string($xml);
  $doc->setEncoding("UTF-8");
  my $nodes = $doc->getElementsByTagName ("entryFree");
  my $n = $nodes->size();
  my @orths = $doc->findnodes('//orth[@type="arrow"]');

  my $t = "";

#  dump_tree($nodes->[0]);
  my %processed;
  my $ret = 0;
  my $errs = 0;
  my $i=1;
  my $txt = "";
  my $rtle ="‫";
  my $pop = "‬";
  my $wordcount=0;
  my $fixed;
  my $linkId;
  my $fixtype=-1;
  if ($buckwalter) {
    $rtle = "";
    $pop = "";
  }
  #
  foreach my $orth (@orths) {
    $arrowCount++;

    my $nodesbefore = checkSiblings($orth,-1);    ## siblings before
    my $nodesafter = checkSiblings($orth,1);     ## siblings after
    $fixed = " ";

    $orth->setAttribute("n","$i");
    $wordcount = scalar(split /\s+/,$orth->textContent);
    if ($wordcount > 1) {
      $orth->setAttribute("subtype","multiwordlink");
    }
    else {
      $orth->setAttribute("subtype","singlewordlink");
    }

    # remove this when finished
    $linkId = $orth->getAttribute("linkId");
    if ($linkId) {
      $orth->setAttribute("nogo",$linkId);
    }
    # treat before and after entries as 'errors'
    if ((length($nodesbefore->{types}) > 0) || (length($nodesafter->{types}) > 0 )) {
      $errs++;
    }
    # a multiword link where the xref is to the last Arabic word
    if ((length($nodesbefore->{types}) == 0) && (length($nodesafter->{types}) == 0)) {
      $wordcount = scalar(split /\s+/,$orth->textContent);
      if ($wordcount > 1) {
        $orth->setAttribute("subtype","multiwordlink");
        $wordcount = fix_link_type3($orth);
        $fixCount++;
        $fixed = "3";
        $fixtype = 1;   # multiword link no b/a
      }
      # a single word link, nothing needs to be done
      elsif ($wordcount == 1) {
        $fixCount++;
        $fixed = "s";
        $orth->setAttribute("subtype","singlewordlink");
        $fixtype = 0;   # single word link
      }
    }

    if ((length($nodesbefore->{types}) > 0) &&
        ((length($nodesafter->{types}) == 0) || ($nodesafter->{types} eq "T"))) {
      if ($fixup) {
        if ($nodesbefore->{types} eq "FT") {
          $wordcount = fix_link_type1($orth,length($nodesbefore->{types}),length($nodesafter->{types}));
          $fixCount++;
          $fixed = "1";
          $fixtype = 2;
        }
        if (($nodesbefore->{types} eq "FTFT") || ($nodesbefore->{types} eq "FTFTF")) {
          $wordcount = fix_link_type2($orth,length($nodesbefore->{types}),length($nodesafter->{types}));
          $fixCount++;
          $fixed = "2";
          $fixtype = 3;
        }
      }
    }


      if ($nodesafter->{types} eq "TF") {
        if ($fixup) {
          if (($nodesbefore->{types} eq "TF") || ($nodesbefore->{types} eq "" )) {
            $wordcount = fix_link_type4($orth,length($nodesbefore->{types}),length($nodesafter->{types}));
            $fixCount++;
            $fixed = "4";
            $fixtype = 4;
          }
        }
      }


      $txt .= sprintf "%6d %6d:%s:[%02d] %2d %10s B [$rtle%40s$pop] A [%s]\n",$arrowCount,$linkId,$fixed,$wordcount,$i,
          (sprintf "[%s]",$nodesbefore->{types}),
          $orth->textContent,
          $nodesafter->{types} if $verbose;

    $i++;
    if (! $dryrun && ($linkId > 0)) {
      $lh->bind_param(1,$fixtype);
      $lh->bind_param(2,$linkId);
      $lh->execute();
      if ($lh->err ) {
        print STDERR "Warning: unable to update link record, disabling writes " . $lh->err . " error msg: " . $lh->errstr . "\n";
        $dryrun = 1;
      }
      else {
        $writeCount++;
      }

    }

  }

  my $newxml;
  if ($fixup) {
    $newxml = $nodes->[0]->toString;
  }
  return (scalar(@orths),$errs,$txt,$newxml);

}
#
#  TF before
#
sub fix_link_type1 {
  my $orth = shift;
  my $nodesbefore = shift;
  my $nodesafter = shift;
  my $node;
  my $ix;
  my @nodes;
  $node = $orth->previousSibling;
  my $beforetext = "";
  my $wordcount;

 $ix = $nodesbefore;

  while($ix) {
    if (($node->nodeType == XML_ELEMENT_NODE) && ($node->nodeName eq "foreign")) {
      push @nodes,$node;
      $beforetext .= " ";
      $beforetext .= $node->textContent;
    }
    elsif ($node->nodeType == XML_TEXT_NODE) {
      push @nodes,$node;
      my $str = $node->textContent;
      $str =~ s/↓/ /g;
      if ($str =~ /^[\s\n\r]+$/) {
#        print STDERR "[YEP SPACED OUT\n";
      }
    }
    $node = $node->previousSibling;
    $ix--;
  }
  # delete the nodes before
  foreach $node (@nodes) {
    my $p = $node->parentNode;
    $p->removeChild($node);
  }
  $wordcount = scalar(split /\s+/,$beforetext);
  # get the text, remove the linked to word
  # and add it as a <ref> child, then add the remaining text
  my $textnode = $orth->firstChild;
  if ($textnode->nodeType == XML_TEXT_NODE) {
    my @words = split /\s+/,$textnode->textContent;
    if (scalar(@words) > 0) {
      # print STDERR "\n" . $words[$#words] . "\n";
      my $linkword = pop @words;
      my $newtext = XML::LibXML::Text->new(sprintf "%s ", join ' ',@words );
      $orth->replaceChild($newtext,$textnode);
      my $linknode = $orth->addNewChild("","ref");
      $linknode->appendText("$linkword");
      $linknode->setAttribute("render","linkwordwitharrow");
      $linknode->setAttribute("type","1");
    }
    $wordcount += scalar(@words);
  }

  $orth->appendText($beforetext);
  $orth->setAttribute("subtype","multiwordlink");
  return $wordcount;
#  if ($nodesafter == 0) {
#    return;
#  }
  # this is when the next non-Arabic character is '['
#  $node = $orth->nextSibling;
#  print "Testing " . $node->textContent;

}
#
#  TFTFO  which should be ones where the arabic preceding the link arrow has
#  a line break
#
#  should be FOF
#
sub fix_link_type2 {
  my $orth = shift;
  my $nodesbefore = shift;
  my $nodesafter = shift;
  my $node;
  my $ix;
  my @nodes;
  my $wordcount = 0;
  my $beforetext = "";
  my $appendtext = "";
  my $nodetype;
  $ix = $nodesbefore;


  $node = $orth->previousSibling;
  if ($nodesbefore =~ /T$/) {
    push @nodes, $node;
    $node = $orth->previousSibling;
  }
  # we should pointing at the foreign before the orth
  if (($node->nodeType == XML_ELEMENT_NODE) && ($node->nodeName eq "foreign")) {
    $appendtext .= " ";
    $appendtext .= $node->textContent;
  }
  push @nodes, $node;
  # move back skipping the expected text node
  $node = $node->previousSibling;
  if ($node->nodeType == XML_TEXT_NODE) {
    push @nodes, $node;
    $node = $node->previousSibling;
  }
  $beforetext = $node->textContent;
  push @nodes, $node;

  # delete the nodes before
  foreach $node (@nodes) {
    my $p = $node->parentNode;
    $p->removeChild($node);
  }
  my @words = split /\s+/,$orth->textContent;

  $wordcount = scalar(@words) + scalar(split /\s+/,$beforetext) + scalar(split /\s+/,$appendtext);

  my $textnode = $orth->firstChild;
  if ($textnode->nodeType == XML_TEXT_NODE) {
    my @words = split /\s+/,$textnode->textContent;
    if (scalar(@words) > 0) {
      # print STDERR "\n" . $words[$#words] . "\n";
      my $linkword = pop @words;
      push @words,$appendtext;
      my $newtext = XML::LibXML::Text->new(sprintf "%s ", join ' ',@words );
      $orth->replaceChild($newtext,$textnode);
      my $linknode = $orth->addNewChild("","ref");
      $linknode->appendText("$linkword");
      $linknode->setAttribute("render","linkwordwitharrow");
      $linknode->setAttribute("type","2");
    }
  }
  $orth->appendText($beforetext);
  $orth->setAttribute("subtype","multiwordlink");
  return $wordcount;
}
######################################################
# For plain multiword links with no befores or afters
######################################################
sub fix_link_type3 {
  my $orth = shift;

  my $hasArrow = 0;
  my $p = $orth->previousSibling;
  if ($p->textContent =~ /↓/) {
    $hasArrow = 1;
  }
  my $textnode = $orth->firstChild;
  if ($textnode->nodeType != XML_TEXT_NODE) {
    return;
  }


  my @words = split /\s+/,$textnode->textContent;
  my $wordcount = scalar(@words);
  my $linkword = pop @words;

  $orth->removeChild($textnode);



  my $newtext = XML::LibXML::Text->new(sprintf "%s ", join ' ',@words );
  $orth->appendText($newtext);

  my $linknode = $orth->addNewChild("","ref");
  $linknode->appendText("$linkword");
  $linknode->setAttribute("type","3");
  if ($hasArrow) {
    $linknode->setAttribute("render","linkword");
  }
  else {
    $linknode->setAttribute("render","linkwordwitharrow");
  }
  $orth->setAttribute("subtype","multiwordlink");
  return $wordcount;
}
#
#  TF after optionally with TF before
#
sub fix_link_type4 {
  my $orth = shift;
  my $nodesbefore = shift;
  my $nodesafter = shift;
  my $node;
  my $ix;
  my @nodes;

  my $aftertext = "";
  my $beforetext = "";
  $ix = $nodesbefore;
  $node = $orth->previousSibling;

  while($ix) {
    if (($node->nodeType == XML_ELEMENT_NODE) && ($node->nodeName eq "foreign")) {
      push @nodes,$node;
      $beforetext .= " ";
      $beforetext .= $node->textContent;
    }
    elsif ($node->nodeType == XML_TEXT_NODE) {
      push @nodes,$node;
#     my $str = $node->textContent;
#      $str =~ s/↓/ /g;
#      if ($str =~ /^[\s\n\r]+$/) {
#        print STDERR "[YEP SPACED OUT\n";
#      }
    }
    $node = $node->previousSibling;
    $ix--;
  }

  $node = $orth->nextSibling;
  $ix = $nodesafter;
  while($ix) {
    if (($node->nodeType == XML_ELEMENT_NODE) && ($node->nodeName eq "foreign")) {
      push @nodes,$node;
      $aftertext .= " ";
      $aftertext .= $node->textContent;
    }
    elsif ($node->nodeType == XML_TEXT_NODE) {
      push @nodes,$node;
#      my $str = $node->textContent;
#      $str =~ s/↓/ /g;
#      if ($str =~ /^[\s\n\r]+$/) {
#        print STDERR "[YEP SPACED OUT\n";
#      }
    }
    $node = $node->nextSibling;
    $ix--;
  }
  # delete the nodes
  foreach $node (@nodes) {
    my $p = $node->parentNode;
    $p->removeChild($node);
  }
  # get the text and then drop the text node
  my @words  = split /\s+/,$orth->textContent;
  my $wordcount = scalar(@words) + scalar(split /\s+/,$beforetext) + scalar(split /\s+/,$aftertext);

  my $linkword = pop @words;
  my $textchild = $orth->firstChild;
  $orth->removeChild($textchild);

  # add the linked word

  if (scalar(@words) > 0) {
    my $t = sprintf "%s ",join " ",@words;
    $orth->appendText($t);
  }
  my $linknode = $orth->addNewChild("","ref");
  $linknode->appendText("$linkword");
  $linknode->setAttribute("render","linkwordwitharrow");
  $linknode->setAttribute("type","4");
  $orth->appendText($beforetext);
  $orth->appendText($aftertext);
  $orth->setAttribute("subtype","multiwordlink");
  return $wordcount;
}
#################################################################
#
#################################################################
sub process_file {
  my $filename = shift;

  if (! -e $filename ) {
    print STDERR "Supplied xml file not found:$filename\n";
    exit 0;
  }
  my $xml;
  my $errs = 0;
  my $rtle ="‫";
  my $pop = "‬";
  if ($buckwalter) {
    $rtle = "";
    $pop = "";
  }
  my $parser = XML::LibXML->new;
  $parser->set_options("line_numbers" => "parser","suppress_errors" => 1);
  #  my $parser = new XML::DOM::Parser;
  my $doc = $parser->parse_file($filename);
  print STDERR "XML encoding:" .   $doc->encoding . "\n"; # prints ISO-8859-15
#  $doc->setEncoding("UTF-8");
  my $nodes = $doc->getElementsByTagName ("entryFree");
  my $n = $nodes->size();

  for (my $i=0;$i < $n;$i++) {
    my @orths = $nodes->[$i]->findnodes('//orth[@type="arrow"]');
    my $txt = "";
    my $fixed = " ";
    foreach my $orth (@orths) {
      my $nodesbefore = checkSiblings($orth,-1); ## siblings before
      my $nodesafter = checkSiblings($orth,1);   ## siblings after
      if ($fixup) {
        if ((length($nodesbefore->{types}) > 0) && (length($nodesafter->{types}) == 0)) {
          fix_link($orth,length($nodesbefore->{types}),length($nodesafter->{types}));
          $fixed = "x";
        }
      }


      if ((length($nodesbefore->{types}) > 0) || (length($nodesafter->{types}) > 0 )) {
        $errs++;
        $txt .= sprintf "[%s] %2d %10s B [$rtle%40s$pop] A [%s]\n",$fixed,$i,
          (sprintf "[%s]",$nodesbefore->{types}),
          $orth->textContent,
          $nodesafter->{types} if $verbose;


      }
      $i++;

    }
  }
  open OUTF,">/tmp/xxx.xml";
  binmode OUTF,":encoding(UTF-8)";
  print OUTF $doc->toString;
  return;
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
##########################################################################

GetOptions(
           "file=s" => \$xmlfile,
           "verbose" => \$verbose,
           "node=s" => \$node,
           "show" => \$showxml,
           "dry-run" => \$dryrun,
           "fix" => \$fixup,
           "max=s" => \$maxerrors,
           "buck" => \$buckwalter                  # show buckwalter transliteration
       );

if ($xmlfile) {
  process_file($xmlfile);
  exit 0;
}
#   /tmp/lexicon.sqlite is the 'clean' version
#
#
if (! $dryrun ) {
  unlink "lexicon3.sqlite";
  system("cp /tmp/lexicon.sqlite lexicon3.sqlite");
  openDb("lexicon3.sqlite");
}
else {
  openDb("/tmp/lexicon.sqlite");
}
#$node = "n5217";
my $sth;
my $sql;
my $usql;
my $usth;
if ($node) {
  if ($node !~ /^n\d+/) {
    $node = "n" . $node;
  }
$sql = sprintf "select id,root,broot,page,word,bword,nodeid,XML from entry where nodeid=\"%s\" order by nodenum asc",$node;
}
else {
  $sql = "select id,root,broot,page,word,bword,nodeid,XML from entry order by nodenum asc";
}

if ($buckwalter) {
  $sql =~ s/XML/perseusxml/;
}
else {
  $sql =~ s/XML/xml/;
}
if (! $dryrun ) {
  $usql = "update entry set xml = ? where id = ?";
  $usth = $dbh->prepare($usql);
  if ( $usth->err ) {
    die "ERROR preparing update SQL:" . $usth->err . " error msg: " . $usth->errstr . "\n";
    exit 0;
  }
  $lh = $dbh->prepare("update links set orthtype = ? where id = ?");
  if ( $lh->err ) {
    die "ERROR preparing update link SQL:" . $lh->err . " error msg: " . $lh->errstr . "\n";
    exit 0;
  }

}

$sth = $dbh->prepare($sql);
$sth->execute();
my ($root,$broot,$page,$word,$bword);
my $xml;
my $nxml;                       # fixed xml
my $errors = 0;
my $a;
my $e;
my $t;
my $id;
$sth->bind_columns(\$id,\$root,\$broot,\$page,\$word,\$bword,\$node,\$xml);
while ($sth->fetch) {
  if ($showxml) {
    print decode("UTF-8",$xml);
  }
  ($a,$e,$t,$nxml) = perseus($xml);
  $errors += $e;

  print sprintf "%s %s %s\n%s\n",$node,$broot,$bword,$t if $a > 0;
    #    print $nxml;
  if ($fixup && ($xml ne $nxml)) {
    print $nxml if $showxml;
    # update xml
    if (! $dryrun ) {
      $usth->bind_param(1,$nxml);
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
  if ($maxerrors  && ($errors > $maxerrors)) {
    last;
  }
}
if ($writeCount > 500) {
  $dbh->commit;
  $updateCount += $writeCount;
  $writeCount = 0;
}
print sprintf "Arrow count %d, probable error count:%d\n",$arrowCount,$errors;
print sprintf "Fixed count:%d\n",$fixCount;
print sprintf "Records update: %d\n",$updateCount;
