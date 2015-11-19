#!/usr/bin/perl -w
#
#
#
#
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
my $itypesth;
my $baresth;
my $headsth;
my $linksth;
my $posh;
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
my $verbForms=0;
my $fixLinks=0;
my $noUpdate=0;
my $showXml=0;
my $showHelp=0;
my $characterCoverage=0;
my $headFixesFile = "headword_fixes.csv";
my %headwordFixes;
binmode STDERR, ":utf8";
binmode STDOUT, ":utf8";
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
sub load_manual_fixes {
  my $filename = shift;
  my $fh;
  my @w;

  return unless -e $filename;
  open($fh,"<:encoding(UTF8)",$filename);
  while(<$fh>) {
    @w = split /,/,$_;
    if ($#w == 5) {
      $headwordFixes{$w[0]} = $w[4];
    }
  }
}
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
sub check_manual_fixup {
  my $node = shift;

  if ( ! exists $headwordFixes{$node} ) {
    return -1;
  }
  return $headwordFixes{$node};
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
###################################################################################
#
#  sets the headword field in entry table
#
###################################################################################
sub find_headwords {
  my %b;
  my @bletters;
  my $bletter;
  my $writeCount = 0;
  my $commitCount = 500;
  my $updateCount = 0;


  print $headfh sprintf "Index,Node,Root,Broot,Head,BHead\n";
  my $sth = $dbh->prepare("select id,root,broot,word,bword,nodeid from entry");
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
  my $node;
  my $rec;
  $sth->execute();
  while ($rec = $sth->fetchrow_arrayref) {
    #  my ($id,$root,$broot,$word,$bword,$nodeid) = split '|', $_;
    #
    # This is the character coverage
    #
    if ($characterCoverage) {
      @bletters = split '',$rec->[4];
      for (my $i=0;$i < scalar(@bletters);$i++) {
        $bletter = $bletters[$i];
        my $c = -1;
        if ( exists $b{$bletter} ) {
          $c = $b{$bletter};
        }
        $b{$bletter} = $c + 1;
      }
    }
    $node = $rec->[5];
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
      if ($word_index == -1) {
        $word_index = check_manual_fixup($node);
      }
      if ($word_index != -1) {

        print $headfh sprintf "%d|%s|%s|%s|%s|%s\n",$word_index,$rec->[5],$root,$rec->[2],$head,$rec->[4];
        #      print $headfh sprintf "%d[%s][%s][%s][%s][%s]\n",$word_index,$rec->[5],$root,$rec->[2],$head,$rec->[4];
      #    }
        $head = $words[$word_index];
        $match_count++;
      }
    }
    if (! $noUpdate) {
      $update->bind_param(1,$head);
      $update->bind_param(2,$rec->[0]);
      $update->execute();
      if ( $update->err ) {
        die "ERROR return code:" . $update->err . " error msg: " . $update->errstr . "\n";
      }
      $writeCount++;
      $updateCount++;
      if ($writeCount > $commitCount) {
        $dbh->commit;
        $writeCount = 0;
      }
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
  if ($characterCoverage) {
    print STDERR sort keys %b;
    print STDERR "\n";
    foreach $bletter (sort keys %b) {
      print STDERR sprintf "[%s][%04x]\t%d\n",$bletter,ord($bletter),$b{$bletter};
    }
  }
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
  if ($nodeName eq "ptr") {
      return;
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
      my ($id,$bword,$nodeid) = $lookupsth->fetchrow_array;
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
          ($id,$bword,$nodeid) = $lookupsth->fetchrow_array;
          #          if ($id) {
          #            print STDERR "Found at [$id][$bword][$nodeid]\n";
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
          ($id,$word,$bword,$bareword,$nodeid) = $baresth->fetchrow_array;
          if ($id) {
            #            print STDERR sprintf "[%d] bareword match %s, $nodeid\n",$isArrow,decode("UTF-8",$word);
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
        if ($nodeid) {
          $linkCount++;
          $node->setAttribute("goto",$id);
          $node->setAttribute("nodeid",$nodeid);
          $node->setAttribute("linkid",$linkCount);
          $node->setAttribute("bareword",$bareWordMatch);
          $updateNode = 1;
          push @links, { type => 0,id => $id,node => $nodeid,bword => $bword,word => $text,linkid => $linkCount,bareword => $bareWordMatch};
        } else {
          print STDERR "Record id:$id has no nodeid\n";
        }
      }
    }
  }
}

sub gen_verbs {
  my $root = shift;

  if (length($root) != 3) {
    return;
  }
  my $c1 = substr $root, 0,1;
  my $c2 = substr $root, 1,1;
  my $c3 = substr $root, 2,1;

  my @forms;
  my $sukun = chr(0x652);
  my $shadda = chr(0x651);
  my $alef = chr(0x627);
  my $teh = chr(0x62a);
  my $noon = chr(0x646);
  my $seen = chr(0x633);
  # TODO
  #
  # form VIII changes for emphatics
  #
  push @forms,$root;
  push @forms, sprintf "%s%s%s%s",$c1,$c2,$shadda,$c3;                # II
  push @forms, sprintf "%s%s%s%s",$c1,$c2,$alef,$c3;                  # III
  push @forms, sprintf "%s%s%s%s%s",$alef,$c1,$sukun,$c2,$c3;         # IV
  push @forms, sprintf "%s%s%s%s%s",$teh,$c1,$c2,$shadda,$c3;         # V
  push @forms, sprintf "%s%s%s%s%s",$teh,$c1,$alef,$c2,$c3;           # VI
  push @forms, sprintf "%s%s%s%s%s%s",$alef,$noon,$sukun,$c1,$c2,$c3;  # VII
  push @forms, sprintf "%s%s%s%s%s%s",$alef,$c1,$sukun,$teh,$c2,$c3;  # VIII
  push @forms, sprintf "%s%s%s%s%s%s",$alef,$c1,$sukun,$c2,$c3,$shadda;  # IX
  push @forms, sprintf "%s%s%s%s%s%s",$alef,$seen,$teh,$c1,$c2,$c3;  # X

#  print sprintf "[%s][%s][%s]\n",$c1,$c2,$c3;
#  print join "\n",@forms;
  return @forms;

}
#########################################
# tries to find a matching verb form
#########################################
sub check_verbforms {
  my $root = shift;
  my $word = shift;

  my @forms = gen_verbs($root);

  if (scalar(@forms) == 0) {
    return -1;
  }

  # remove all fatha,damma,kasra etc
  $word =~ s/[\x64b-\x650]//g;

  my $ix = 0;
  foreach my $form (@forms) {
    if ($word =~ /$form/) {
      return $ix;
    }
    $ix++;
  }
  return -1;
}
################################################
# link match types:
#  1  : word
#  2  : headword
#  3  : bareword
#  4  : verb form
###############################################
sub lookupWord {
  my $root = shift;
  my $word = shift;

#  print STDERR "Doing root $root, link word $word \n";
  $lookupsth->bind_param(1,$word);
  $lookupsth->execute();
  my $rec = $lookupsth->fetchrow_hashref;
  if ($rec) {

    return ($rec->{id},$rec->{root},$rec->{nodeid},$rec->{word},$rec->{page},1);
  }

  $posh->bind_param(1,$word);
  $posh->execute();
  $rec = $posh->fetchrow_hashref;
  if ($rec) {
#    print STDERR "found in pos " .$rec->{nodeid} . "\n";
    return ($rec->{id},$rec->{root},$rec->{nodeid},$rec->{headword},-1,5);
  }
  $headsth->bind_param(1,$word);
  $rec = $lookupsth->fetchrow_hashref;
  if ($rec) {
    return ($rec->{id},$rec->{root},$rec->{nodeid},$rec->{word},$rec->{page},2);
  }

  my $itype = check_verbforms($root,$word);
  if ($itype != -1) {
    $itypesth->bind_param(1,$root);
    $itypesth->bind_param(2,$itype);
    $itypesth->execute();
    $rec = $itypesth->fetchrow_hashref;
    if ($rec) {
      return ($rec->{id},$rec->{root},$rec->{nodeid},$rec->{word},$rec->{page},4);
    }
  }
  return ();
  #
  # checking on the bareword gives 5000+ successful matches
  # not very reliable though
  #
  my $count = ($word =~ tr/\x{64b}-\x{652}\x{670}\x{671}//d);
  my $bareword;
  $baresth->bind_param(1,$word);
  if ($baresth->execute()) {
    $rec = $baresth->fetchrow_hashref;
    if ($rec) {
      return ($rec->{id},$rec->{root},$rec->{nodeid},$rec->{word},$rec->{page},3);
    }
  }

  return ();
}
sub remove_affixes {
  my $word = shift;
  my $t = $word;


  $word =~ s/^\N{ARABIC LETTER TEH}(\N{ARABIC KASRA}|\N{ARABIC FATHA}|\N{ARABIC DAMMA})(.)\N{ARABIC SUKUN}/$2/;
#  print STDERR "Affixes before:$t, after : $word\n";

  $word =~ s/\N{ARABIC SUKUN}$//;
  $word =~ s/\N{ARABIC LETTER HEH}\N{ARABIC DAMMA}\N{ARABIC LETTER MEEM}$//;
  $word =~ s/\N{ARABIC LETTER NOON}\N{ARABIC FATHA}\N{ARABIC LETTER ALEF}$//;
#  $word =~ s/\N{ARABIC LETTER TEH}(\N{ARABIC FATHA}|\N{ARABIC DAMMA}|\N{ARABIC KASRA})$//;
#  $word =~ s/^\N{ARABIC LETTER TEH}(\N{ARABIC FATHA}|\N{ARABIC DAMMA}|\N{ARABIC KASRA})//;
#  $word =~ s/^\N{ARABIC LETTER BEH}\N{ARABIC KASRA}*//;
#  $word =~ s/\N{ARABIC LETTER KAF}\N{ARABIC FATHA}*$//;
#  $word =~ s/^\N{ARABIC LETTER ALEF WITH HAMZA ABOVE}//;
#  $word =~ s/\N{ARABIC LETTER YEH}$//;
#  $word =~ s/\N{ARABIC LETTER ALEF MAKSURA}$//;
#  print STDERR "Affixes before:$t, after : $word\n";
  $word =~ s/\N{ARABIC SUKUN}$//;
  return $word;
}
###############################################################
# calls lookupWord for each word in the entry
# returns array of matches
###############################################################
sub findLink {
  my $root = shift;
  my $text = shift;
  my @words;
  $text =~ s/^\s+//g;
  $text =~ s/\s+$//g;

  if ($text =~ /\s+/) {
    #   for multiword text we need to reverse the array
    #
    push @words,split /\s+/,$text;
    @words = reverse @words;
  }
  else {
    push @words,$text;
  }
  my @matches;
  my ($linkToId,$linkToRoot,$linkToNode,$linkToWord,$linkType,$linkToPage);
  my $wordMatched;
  # For multiword links:
  #
  # if we assume that the down arrow immediately precedes the linked word
  # then we need only try to find the first word,we can do:
  #  my $max = 1;
  #
  # otherwise we can do:
  #  my $max = $#words;
  #
  #
  my $max = 1;

  for(my $i=0;$i < $max;$i++) {
      my $linkword = $words[$i];
      my $affixmatch = 0;
      ($linkToId,$linkToRoot,$linkToNode,$linkToWord,$linkToPage,$linkType) = lookupWord($root,$linkword);
       if (! $linkToNode ) {
         my $t = remove_affixes($linkword);
         if ($t ne $linkword) {
           $affixmatch = 1;
           ($linkToId,$linkToRoot,$linkToNode,$linkToWord,$linkToPage,$linkType) = lookupWord($root,$t);
         }
          }
      if ($linkToNode) {
#        print sprintf "[%d] Matched word %s to %s, node %s\n",$affixmatch,$linkword,decode("UTF-8",$linkToWord),$linkToNode;
      push @matches,{ node => $linkToNode,
                      id => $linkToId,
                      root => decode("UTF-8",$linkToRoot),
                      matchedword => $linkword,
                      word => decode("UTF-8",$linkToWord),
                      page => $linkToPage,
                      type => $linkType };
      }
      else {
      }
  }
#  print Data::Dumper->Dump([\@matches],[qw(matches)]);
  return @matches;
}
##################################################################
#
# top level routine for setting links
#
##################################################################

sub setLinks {
  my $node = shift;
  my $parser = XML::LibXML->new;
  $parser->set_options("line_numbers" => "parser");
  my $sql;
  my $attrnode;
  my $entrysth;

  my $linkToNode;
  my $updateRequired;
  if (! $node ) {
    $sql = "select id,root,broot,word,bword,nodeid,xml,page from entry where datasource = 1 order by nodenum asc";
    $entrysth = $dbh->prepare($sql);
  } else {
    $sql = "select id,root,broot,word,bword,nodeid,xml,page from entry where datasource = 1 and nodeid = ?";
    $entrysth = $dbh->prepare($sql);
    $entrysth->bind_param(1,$node);
  }
  my $updatesth = $dbh->prepare('update entry set xml = ? where id = ?');
  $baresth = $dbh->prepare("select id,root,word,bword,bareword,nodeid,page from entry where bareword = ? and datasource = 1");

  my $lookupsth = $dbh->prepare("select id,root,bword,nodeid,page from entry where word = ? and datasource = 1");

  my $lastentrysth;
  my @entry;

  $entrysth->execute();
  while (@entry = $entrysth->fetchrow_array()) {
    my ($id, $root,$broot,$word,$bword,$nodeid,$xml,$page) = @entry;
    my $doc = $parser->parse_string($xml);
    $doc->setEncoding("UTF-8");
    # note:
    # node $doc->toString and $node->toString behave differently
    #

    my @orths = $doc->findnodes('//ref');
    my $printHeader=0;
    my $linkId;

    my $orthindex;
    my $pattern;
    my $fixtype;
    $updateRequired = 0;
    $currentRecordId = $id;
    foreach my $node (@orths) {
      my $linktext;
      $#links = -1;             # clear old links
      $linkId = $node->getAttribute("cref");
      $orthindex = $node->getAttribute("n");
      $fixtype = $node->getAttribute("type");
      $pattern = $node->getAttribute("subtype");
        # show node name
      if ($verbose && !$printHeader ) {
        print $logfh $nodeid . "\n";
        $printHeader = 1;
      }
      if ($showXml) {
        print STDERR $node->toString . "\n";
      }
      $arrowsCount++;

      $linktext = $node->getAttribute("target");

      my @matches = findLink(decode("UTF-8",$root),$linktext);
      if ((scalar @matches) > 1) {
        $multiMatches++;
      }
      if ((scalar @matches) > 0) {
        for(my $j=0;$j <= $#matches;$j++) {
          my $m = $matches[$j];
          my ($linkToId,$linkToNode,$linkToWord,$linkType);
          print  $logfh sprintf "‎ %d,%d,%d,%s,%s,%s,%s,%s\n",
            scalar(@matches),
            $linkId,
            $m->{type},
            $linktext,
            $nodeid,
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
          # $node->setAttribute("goto",$m->{id});
          # $node->setAttribute("root",$m->{root});
          # $node->setAttribute("page",$m->{page});
          # $node->setAttribute("vol",getVolForPage($m->{page}));
          # $node->setAttribute("nodeid",$m->{node});
          # $node->setAttribute("matched",$m->{matchedword});
          # $node->setAttribute("linktype",$m->{type});
          $node->setAttribute("select",$linkId);
          $updateRequired = 1;
          if (! $noUpdate && ($linkId != -1)) {
            # update links table
            updateLinkRecord($linkId,$m->{node},$m->{type},$linktext);
          }
          if ($showXml) {
            print $logfh $node->toString . "\n\n";
          }
          $resolvedArrows++;
        } else {

          print STDERR "We should not be here\n";
        }
      } else {
        # do we need to do anything if no match found
        updateLinkRecord($linkId,"",-1,$linktext);
        $updateRequired = 1;
        print $logfh sprintf "0,%d,%s,%s\n",$linkId,$linktext,$nodeid;
      }
    }
    if (! $noUpdate && $updateRequired) {
      my @entryfree = $doc->getElementsByTagName("entryFree");
      my $xml = $entryfree[0]->toString;
      #my $xml = decode("UTF-8",$doc->toString);
      # toString is returning <?xml version="1.0"?>
      # so strip this out.
      # There's probably some setting that stops this
      # but I haven't found it.
      # Added: using $node->toString without the decode and the stripping
#        $xml =~ s/^<?.+?>//;
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
##########################################
# $linksth = $dbh->prepare("update links set tonode = ?, link = ?,matchtype = ? where id = ?");
########################################
sub updateLinkRecord {
  my $id = shift;
  my $toNode = shift;
  my $resolveType = shift;
  my $linktext = shift;


  $linksth->bind_param(1,$toNode);
  $linksth->bind_param(2,$linktext);
  $linksth->bind_param(3,$resolveType);
  $linksth->bind_param(4,$id);
  if ($linksth->execute()) {
    $writeCount++;
  }
}
###########################################################################
# main
#
# Two main functions:
# (1) To set the headword value in 'entry' table
#     Lane often has phrases has headwords i.e. in the original text the
#     first words for the entry are in bold
#     The code tries to find the word based on the current root
#
#
# (2) To set the @golink attribute for <orth type="arrow"> entries
# eg to test the links for a particular node:
#
# perl links.pl --db vanilla.sqlite --links --node n9017
#
# (Will create links.log in current directory.)
#
##########################################################################
GetOptions(
           "db=s" => \$dbName,
           "node=s" => \$nodeName,
           "log-dir=s" => \$logDir,
           "verbose" => \$verbose,
           "fixes=s" => \$headFixesFile,
           "forms=s" => \$verbForms,
           "links" => \$fixLinks,
           "heads" => \$headwords,
           "dry-run" => \$noUpdate,
           "with-xml" => \$showXml,
           "coverage" => \$characterCoverage,
           "help" => \$showHelp
          );
if ($showHelp) {
  print STDERR "--db <name of sqlite file>   use the supplied database\n";
  print STDERR "--node <node number>         do links for only the given node or comma separated nodes\n";
  print STDERR "--log-dir <directory>        write log file to given directory, defaults to current\n";
  print STDERR "--dry-run                    do not update the database\n";
  print STDERR "--with-xml                   print the before/after XML to STDERR\n";
  print STDERR "--fixes <filename>           Name of file with headword manual fixes (default: headword_fixes.csv)\n";
  print STDERR "--heads                      Update the headword entry\n";
  print STDERR "--links                      Update the links\n";
  print STDERR "--coverage                   Report Buckwalter character counts (as part of headwords)\n";
  print STDERR "--help                       print this\n";
  exit 1;

}
if (! $dbName ) {
  print STDERR "No database name given,exiting\n";
  exit 0;
}

openDb($dbName);
if (! $dbh ) {
  print STDERR "Error opening DB $dbName\n";
  exit 0;
}
#
#  if directory is given, use the dbid from the database as a subdirectory. The
#  other log files (created by lane.pl) should be in there.
#
if (! $logDir ) {
  $logDir = ".";
}
else {
  my $sth = $dbh->prepare("select dbid from lexicon");
  $sth->execute;
  my $rec = $sth->fetchrow_hashref;
  if ($rec) {
    $logDir = getLogDirectory($logDir,$rec->{dbid});
  }
  else {
    print STDERR "Could not read DBID\n";
  }
}

if ($headwords) {
  load_manual_fixes($headFixesFile);
  my $logfile = File::Spec->catfile($logDir,"heads.log");
  open($headfh,">:encoding(UTF8)",$logfile) or die "Cannot open logfile $@\n";
  find_headwords($dbName);
}
#
# test code
#
if ($verbForms) {
  my $root = "كتب";
  my $word = "تكاتبا";
  check_verbforms($root,$word);
}
if (! $fixLinks ) {
  exit 0;
}
#
# fixing links requiers parsing xml of each entry record for all <orth type="arrow">
# 1. Getting the linkId attribute for the same node.
# 2. Call findLink to for the text content of the node (and the current root)
# 3. If matching entry is found
# 4.    set @golink attribute for the node and
#       update the link table for the linkId, setting the from_entry and to_entry
# 5. otherwise, add a @nogo attribute for the link
# 6. When all orth/arrow entries have been done, Save the XML for the current record
#
my $linklog = File::Spec->catfile($logDir,"link.log");
open($logfh,">:encoding(UTF8)",$linklog) or die "Cannot open logfile $@\n";

$lookupsth = $dbh->prepare("select id,root,word,bword,nodeid,page from entry where word = ? and datasource = 1");
$itypesth = $dbh->prepare("select id,root,word,bword,nodeid,page from entry where root = ? and itype = ? and datasource = 1");
$baresth = $dbh->prepare("select id,root,word,bword,bareword,nodeid,page from entry where bareword = ? and datasource = 1");
$headsth = $dbh->prepare("select id,root,word,bword,bareword,nodeid,headword,page from entry where headword = ? and datasource = 1");
$linksth = $dbh->prepare("update links set tonode = ?, link = ?,matchtype = ? where id = ?");
$posh = $dbh->prepare("select id,root,headword,nodeid from pos where word = ?");
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
