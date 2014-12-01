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
binmode STDERR, ":encoding(UTF-8)";
binmode STDOUT, ":encoding(UTF-8)";
sub convertString {
  my $t = shift;
  my $s = $t;



  $t =~ s/^\s+//;
  $t =~ s/\s+$//;
  # so we don't report this type of stuff:
  # <entryFree id="n6619" key="10" type="main">
  #             <form>
  #                <itype>10</itype>
  #                <orth orig="" extent="full" lang="ar">AstjAb</orth>
  #                <orth extent="full" lang="ar">10</orth> and
  # <orth orig="" extent="full" lang="ar">Aisotajowaba</orth>
  #             </form>, inf. n. <fo
  #
  # which should be fixed by the itype promotion routines
  #
  if ($t =~ /^\d+$/) {
    return $t;
  }


    # convert all A@ to L
    if ($t =~ /A@/) {
      $t =~ s/A@/L/g;
    }
    # get rid of the &,
    # this might need fixing properly
    # may when proctype = "word" or "root" we can strip it out
    #

    if ($t =~ /&/) {
        $t =~ s/&c\.*/ /g;
      }
  #  $t =~ s/&amp;c/ /g);
  my $c = 0;
  $c += ($t =~ tr/'|OWI}A/\x{621}\x{622}\x{623}\x{624}\x{625}\x{626}\x{627}/);
  $c += ($t =~ tr/bptvjHx/\x{628}\x{629}\x{62a}\x{62b}\x{62c}\x{62d}\x{62e}/);
  $c += ($t =~ tr/d*rzs$S/\x{62f}\x{630}\x{631}\x{632}\x{633}\x{634}\x{635}/);
  $c += ($t =~ tr/DTZEg\-f/\x{636}\x{637}\x{638}\x{639}\x{63a}\x{640}\x{641}/);
  $c += ($t =~ tr/qklmnhw/\x{642}\x{643}\x{644}\x{645}\x{646}\x{647}\x{648}/);
  $c += ($t =~ tr/YyFNKau/\x{649}\x{64a}\x{64b}\x{64c}\x{64d}\x{64e}\x{64f}/);
  # check ` for alef wasla - is this right
  $c += ($t =~ tr/i~o`{/\x{650}\x{651}\x{652}\x{670}\x{671}/);


  # ^ as hamza above
  # = alef with madda above (in buckwalter docs is |)
  # _ tatweel , also - above
  # L alef wasla
  $c += ($t =~ tr/^=_L/\x{654}\x{622}\x{640}\x{0671}/);

  # count the spaces etc


  return $t;
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
sub getLogDirectory {
  my $base = shift;
  my $dbid = shift;

  # check the base exists or can be created
  if (! $base ) {
      $base = dirname(tempdir());
  }
  my $n = catfile($base,$dbid);
  if (-d $n ) {
    return $n;
  }
  if ( -d $base ) {
  }
  else {
    if (! mkdir $base) {
      $base = dirname(tempdir());
    }
  }
  # try to create the subdirectory
  my $logdir = catfile($base,$dbid);
  if ( mkdir $logdir) {
    return $logdir;
  }
  # couldn't create, so try create as subdirectory of current
  $logdir = catfile(getcwd(),$dbid);
  if (-d $logdir ) {
    return $logdir;
  }
  elsif ( mkdir $logdir) {
    return $logdir;
  }
  # couldn't do that either, so use the temporary directory
  # or the current working directory ignore the $dbid
  $logdir = catfile(dirname(tempdir()),$dbid);
  if (-d $logdir ) {
    return $logdir;
  }
  elsif ( mkdir $logdir) {
    return $logdir;
  }
  return getcwd();
}
##################################################################################
# return list of log files in the given directory
###################################################################################
sub readDirectory {
  my $d = shift;
  my $pattern = shift;
  my @arr;
  if (! -d $d ) {
    print STDERR "No such directory:[$d]\n";
    return @arr;
  }
  my @totals;
  eval {
    find sub { if ((-f $_) && ($File::Find::name =~ /$pattern/))  {  push @arr,$File::Find::name; } }, $d;
  };

  if ($@) {
    print STDERR "File::Find error opening directory:[$d]\n";
    return @arr;
  }
  return sort @arr;
}
###################################################
#
###################################################
sub convErrors {
  my $logdir = shift;
  my $dbId = shift;
  my ($xml,$lineno,$root,$word,$vol,$text,$node,$errChar,$position,$page);
  my ($fh,$outf,$out4f,$out5f,$out6f);
  my @words;
  my $count = 0;
  my ($day,$month,$year) = (localtime)[3,4,5];
  my $rundate = sprintf "%04d-%02d-%02d",$year+1900,$month+1,$day;

  format TYPE4_TOP =
@<<<<<<<<<                                    Type 4 Error Report (@<<<<<<<<<<<<<<<)                                                                             Page @<<<<
$rundate,$dbId,$%

File       Line No    Root            Word                               Node         Vol/Page   Text
----------------------------------------------------------------------------------------------------------------------------------------------------------------------------
.

  format TYPE4 =
@<<<<<<<<<<@<<<<<<<<<<@<<<<<<<<<<<<<<<@<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<@<<<<<<<<<<<<@<<<<<<<<<<@<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<
$xml,$lineno,$root,$word,$node,$vol,$text
.

 format TYPE5_TOP =

@<<<<<<<<<                                                 Type 5 Error Report (@<<<<<<<<<<<<<<<)                                                                Page @<<<<
$rundate,$dbId,$%


File       Line No   Root            Word                               Node        Vol/Page    Char   Pos  Text
-----------------------------------------------------------------------------------------------------------------------------------------------------------------------------
.

  format TYPE5 =
@<<<<<<<<<<@<<<<<<<<<@<<<<<<<<<<<<<<<@<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<@<<<<<<<<<<<@<<<<<<<<<<@<<<<<<@<<<<@<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<
$xml,$lineno,$root,$word,$node,$vol,$errChar,$position,$text
.

  format TYPE6_TOP =
@<<<<<<<<<                                  Type 6-9 Error Report (@<<<<<<<<<<<<<<<)                                                                             Page @<<<<
$rundate,$dbId,$%

File       Line No    Root            Word                               Node         Vol/Page   Text
----------------------------------------------------------------------------------------------------------------------------------------------------------------------------
.

  format TYPE6 =
@<<<<<<<<<<@<<<<<<<<<<@<<<<<<<<<<<<<<<@<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<@<<<<<<<<<<<<@<<<<<<<<<<@<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<
$xml,$lineno,$root,$word,$node,$vol,$text
.



  my @xmlfiles = qw(_A0 b0 t0 v0 j0 _H0 x0 d0 _0 r0 z0 s0 $0 _S0 _D0 _T0 _Z0 _E0 g0 f0 q0 k0 l0 m0 n0 h0 w0 _Y0 q1 k1 l1 m1 n1 h1 w1 _Y1);


  open $out4f, ">:encoding(UTF8)", catfile($logDir,"error_type4.txt");
  open $out5f, ">:encoding(UTF8)", catfile($logDir,"error_type5.txt");
  open $out6f, ">:encoding(UTF8)", catfile($logDir,"error_type6.txt");
  $out4f->format_name("TYPE4");
  $out4f->format_top_name("TYPE4_TOP");
  $out5f->format_name("TYPE5");
  $out5f->format_top_name("TYPE5_TOP");
  $out6f->format_name("TYPE6");
  $out6f->format_top_name("TYPE6_TOP");


  if ($logdir =~ /\/$/) {
    chop $logdir;
  }

  foreach my $logfile (@xmlfiles) {
    my $file = catfile($logdir,sprintf "%s-conv.log",$logfile);
    if (! -e $file ) {
      print STDERR "Could not find file $file\n";
      next;
    }
#    $fileName = $1;
#    $fileName =~ /\/([^.\/])+.xml$/;
    $xml = sprintf "%s.xml",$logfile;
    open $fh, "<",$file || return;
    <$fh>;
    my $errType;
    while (<$fh>) {
      chomp;
      /^(\d+),/;
      $errType = $1;
      if (($errType == 4) || (($errType >= 6) && ($errType <= 9))) {
        @words = split ",",$_;
        $root = $words[2];
        if (length $words[3] > 30) {
          $word = substr $words[3],0,30;
        } else {
          $word = $words[3];
        }
        $node = $words[4];
        $text = $words[5];
        $vol  = $words[6];
        if ($#words == 7) {
          $lineno = $words[7];
        } else {
          $lineno = "";
        }
        if ($errType == 4) {
        write $out4f;
      }
        if (($errType >= 6) && ($errType <= 9)) {
          write $out6f;
      }
        # if (($out4f->format_lines_left == 0) && ($count > 0)) {
        #   my $x = $out4f;
        #   print $x sprintf "Total: %d",$count;
        # }
        $count++;
      }
      if ($errType == 5) {
        @words = split ",",$_;
        if (scalar(@words) < 15) {
#          print STDERR $_;
        }
        else {
        $errChar = $words[4];
        $node = $words[5];
        $root = $words[6];
        if (length $words[7] > 30) {
          $word = substr $words[7],0,30;
        } else {
          $word = $words[7];
        }
        $position = $words[10];
        $text = $words[11];
        $vol = $words[13];
        $page = $words[14];
        $vol =  sprintf "%s/%s",$vol,$page;
        if ($#words == 15) {
          $lineno = $words[15];
        } else {
          $lineno = "";
        }
        write $out5f;
      }
      }
    }
    close $fh;
  }
}
########################################################################
#   2:  double question mark
#   3:  ampersand
#   4:  A@ converted to L
#   5:  non Buckwalter character (that is not punctuation or space)
#   6:  A_ converted to I
#######################################################################
sub summaryStats {
  my $logdir = shift;
  my $dbId = shift;
  my @xmlfiles = qw(_A0 b0 t0 v0 j0 _H0 x0 d0 _0 r0 z0 s0 $0 _S0 _D0 _T0 _Z0 _E0 g0 f0 q0 k0 l0 m0 n0 h0 w0 _Y0 q1 k1 l1 m1 n1 h1 w1 _Y1);

  my $pattern = "conv.log\$";#,$fileprefix,$dbId;

  my ($filename,$type2,$type3,$type4,$type5,$type6,$typeother);
  my ($fh,$outf);
  my ($day,$month,$year) = (localtime)[3,4,5];
  my $rundate = sprintf "%04d-%02d-%02d",$year+1900,$month+1,$day;

  format SUMMARY_TOP =
   @<<<<<<<<<                           Error Summary (@<<<<<<<<<<<<<<<)             Page @<<
$rundate,$dbId,$%

   File       Double ?? (2)   Ampersand (3)   A-hat (4)   Non Buck (5)    A_ (6)     Other
   ----------------------------------------------------------------------------------------
.
  format SUMMARY =
   @<<<<<<<<<<@<<<<<<<<<<<<<<<@<<<<<<<<<<<<<<<@<<<<<<<<<<<@<<<<<<<<<<<<<<<@<<<<<<<<<<@<<<<<
$filename,$type2,$type3,$type4,$type5,$type6,$typeother
.
  open $outf, ">:encoding(UTF8)", catfile($logDir,"error_summary.txt");
  $outf->format_name("SUMMARY");
  $outf->format_top_name("SUMMARY_TOP");
  if ($logdir =~ /\/$/) {
    chop $logdir;
  }

  foreach my $logfile (@xmlfiles) {
    my $file = catfile($logdir,sprintf  "%s-conv.log",$logfile);
    if (! -e $file ) {
      print STDERR "Could not find file $file\n";
      next;
    }
   $type2 = $type3 = $type4 = $type5 = $type6 = $typeother = 0;
   if ($file =~ /([^-]+)-conv.log/) {
     $filename = $logfile;#sprintf "%s.xml",$1;
     open $fh, "<",$file || die $@;
     # skip the header
     <$fh>;
     while(<$fh>) {
       if (/^2/) {
         $type2++;
       }
       elsif (/^3/) {
         $type3++;
       }
       elsif (/^4/) {
         $type4++;
       }
       elsif (/^5/) {
         $type5++;
       }
       elsif (/^(6|7|8|9)/) {
         $type6++;
       }
       else {
         $typeother++;
         print STDERR $_;
       }

     }
     close $fh;
     write $outf;

   }

 }
}
#############################################
# prints out double question marks
#############################################
sub get_dqs {
  my $f = shift;
  my $dqh = shift;
  my $sth = shift;
  my $parser = XML::LibXML->new;
  $parser->set_options("line_numbers" => "parser");
  #  my $parser = new XML::DOM::Parser;
  my $doc = $parser->parse_file($f);
  $doc->setEncoding("UTF-8");
  my $nodes = $doc->getElementsByTagName ("entryFree");
  my $n = $nodes->size();
  my ($id,$word,$pos,$nodeId);
  my $margin = 60;
  my $totalCount = 0;
  my $page;
  for (my $i=0;$i < $n;$i++) {
    my $node = $nodes->item($i);
    if ($node->textContent && ($node->textContent =~ /see\s+supplement/i)) {
      next;
    }
    my $keyAttr = $node->getAttributeNode("key");

    if ($keyAttr) {
      $word = convertString($keyAttr->value);
    }
    else {
      $word = "";
    }
    $id = $node->getAttributeNode("id");
    if ($id) {
      $nodeId = $id->value;
      if ($sth) {
        $sth->bind_param(1,$nodeId)  ;
        $sth->execute();
        $page = $sth->fetchrow_array;
      }
    } else {
      $nodeId = "<NO NODEID>";
      my $t = $node->textContent;
      my @kids = $node->nonBlankChildNodes();
      my $form = $kids[0];
      if ($form) {
        my @gkids = $form->nonBlankChildNodes();
        my $itype = $gkids[0];
        if ($itype) {
          $t = $itype->nodeName;
        }
      }
      if ($t ne "itype") {
        print $dqh sprintf "WARNING %6d No node id (%s), V%s/%s\n",$node->line_number(),$t,getVolForPage($page),$page;
      }
    }

    my $txt = $node->toString();

    my $count = 0;
    while($txt =~ /(\?\?)/g) {
      $count++;
      if ($count == 1) {
        print $dqh sprintf "%-6d %8s %s V%s/%s\n",$node->line_number(),$nodeId , $word,getVolForPage($page),$page;
      }
      $pos =  pos($txt) - length $1;
      my $start = 0;
      my $end = length $txt;
      if ($pos > $margin) {
        $start = $pos - $margin;
      }
      if (($pos + (length $1) + $margin) < $end) {
        $end = $pos + (length $1) + $margin;
      }
      print $dqh substr $txt,$start, $end - $start;
      print $dqh "\n";
    }
    $totalCount += $count;
  }
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

######################################################
#
#  looks for ?? in XML
#
######################################################
sub check_double_questions {
  my $xmldir = shift;
  my $dbname = shift;
  my $sth;
  my @xml = readDirectory($xmldir,"xml\$");

  my $dqh;
  my $filename = catfile($logDir,"double_questions.txt");
  open ($dqh,">:encoding(UTF8)",$filename) or die $@;
  if ($dbname) {
    openDb($dbname);
    if ($dbh) {
      $sth = $dbh->prepare("select page from entry where nodeId = ?");
    }
  }
  foreach my $f (@xml) {
      print $dqh "\n$f\n";
      for(my $i=0;$i < length $f;$i++) {
        print $dqh "=";
      }
      print $dqh "\n";
      get_dqs($f,$dqh,$sth);
  }
   close $dqh;
}
sub wrong_letter {
  my $db = shift;
  my $dbid = shift;
  openDb($db);
  my $sth = $dbh->prepare("select id,word,bword,letter,bletter,supplement,page from root");
  $sth->execute();
  my $word;
  my $bword;
  my $letter;
  my $rootrec;
  my $id;
  my $page;
  my $vol;
  format LETTER_TOP =
@<<<<<<<<<<<<<<<<  Wrong letter report                     Page @>>>
$dbid,                                                          $%
                   ===================
Id              Letter          Root                        Vol/Page
-------------------------------------------------------------------
.
  format LETTER =
@<<<<<<<<<<<<<<<@<<<<<<<<<<<<<<<@<<<<<<<<<<<<<<<<<<<<<<<<<<<V@/@<<<
$id,            $letter,        $word,                       $vol,$page
.
  my $fh;
  open($fh,">:encoding(UTF8)",catfile($logDir,"wrong_letter.txt"));
  $fh->format_name("LETTER");
  $fh->format_top_name("LETTER_TOP");
  while ($rootrec = $sth->fetchrow_arrayref) {
    $bword = $rootrec->[2];
    $word = decode("UTF-8",$rootrec->[1]);
    $letter = decode("UTF-8",$rootrec->[3]);
    $page = $rootrec->[6];
    $vol = getVolForPage($page);
    $id = $rootrec->[0];

    if ((substr $word,0,1) ne $letter) {
#      print STDOUTDERR sprintf "%d %s %s (%d,%d)\n",$rootrec->[0],$letter,$word,
#        $rootrec->[5],$rootrec->[6];
#      print STDOUT $id,$letter,$word,$page;
      write $fh;
    }
  }
  $fh->close;
}
sub check_long_roots {
  my $db = shift;
  my $dbid = shift;
  openDb($db);
  my $sth = $dbh->prepare("select id,word,bword,letter,bletter,supplement,page,xml from root where length(bword) > 1 order by page");
  $sth->execute();
  my $word;
  my $bword;
  my $letter;
  my $rootrec;
  my $id;
  my $page;
  my $vol;
  my $xml;
  format LONG_ROOT_TOP =
@<<<<<<<<<<<<<<<<  Long Roots Report                                Page @>>>
$dbid,                                                                  $%
                   =================
Id              Letter          Root                        Vol/Page     File
-----------------------------------------------------------------------------
.
  format LONG_ROOT =
@<<<<<<<<<<<<<<<@<<<<<<<<<<<@<<<<<<<<<<<<<@<<<<<<<<<<<<<<<<<<<V@/@<<<<<<<<<@<<<
$id,            $letter,        $word, $bword ,                  $vol,$page,$xml
.
  my $fh;
  my $csv;
  my $tex;

  open($fh,">:encoding(UTF8)",catfile($logDir,"long_roots.txt"));
  open($csv,">:encoding(UTF8)",catfile($logDir,"long_roots.csv"));
  open($tex,">:encoding(UTF8)",catfile($logDir,"long_roots.tex"));
  $fh->format_name("LONG_ROOT");
  $fh->format_top_name("LONG_ROOT_TOP");
  print $tex get_tex_header();
  print $tex "\\hline\n";
  print $tex "Id & Letter & Root & Buckwalter & Vol & Page & File \\\\\n";
  print $tex "\\hline\n";
  print $tex "\\endhead\n";
  my $linecount = 0;
  my $lastvol = 1;
  while ($rootrec = $sth->fetchrow_arrayref) {
    if ($linecount > 0) {
      ## print the end of line
      print $tex " \\\\\n";
    }
    $bword = $rootrec->[2];
    $word = decode("UTF-8",$rootrec->[1]);
    $letter = decode("UTF-8",$rootrec->[3]);
    $page = $rootrec->[6];
    $vol = getVolForPage($page);
    $bword = $rootrec->[2];
    $xml = $rootrec->[7];

    $id = $rootrec->[0];
    write $fh;
    print $csv sprintf "%s,%s,%s,%s,%s,%s,%s\n",$id,$letter,$word,$bword,$vol,$page,$xml;
    $bword =~ s/~/\\~{}/g;
    $bword =~ s/\^/\\^{}/g;
    $bword =~ s/\$/\\\$/g;
    $xml =~ s/_/\\_/g;
    $xml =~ s/\$/\\\$/g;
    if ($lastvol != $vol) {
      print $tex "\\pagebreak\n";
      $lastvol = $vol;
    }
    print $tex sprintf "%s & \\textarabic{%s} & \\textarabic{%s} &  %s & %s & %s &  %s",$id,$letter,$word,$bword,$vol,$page,$xml;
    $linecount++;
  }
  print $tex "\n";
  print $tex get_tex_footer();
  $fh->close;
  $csv->close;
  $tex->close;
}
sub tex_escape {
  my $word = shift;

  my @ec = split //,$word;
  my $o = "";

  foreach my $c (@ec) {
    if ($c =~ /[\\{}_^#&\$%~]/) {
      $o .= "\\";
    }
    $o .= $c;
  }
  return $o;
}
sub headwords {
  my $dbid = shift;

  my $tex;
  my $csv;
  my $fh;


  my $filename = catfile($logDir,"heads.log");
  if ( ! -e $filename ) {
    print STDERR "Cannot find required log file : $filename\n";
    return;
  }
  open($fh,"<:encoding(UTF8)",$filename);
  open($tex,">:encoding(UTF8)",catfile($logDir,"heads.tex"));
  open($csv,">:encoding(UTF8)",catfile($logDir,"heads.csv"));
  print $tex get_tex_header_headwords();
  print $tex "\\hline\n";
  print $tex "Node & Root & Headword & Buck root &  Index & Buck Head \\\\\n";
  print $csv "Node,Root,Headword,Buck root,Index,Buck Head\n";
  print $tex "\\hline\n";
  print $tex "\\endhead\n";

  my $linecount = 0;
  my @ar;
  my $show;
  while (<$fh>) {
    $show = 1;
    @ar = split /\|/,$_;
    if ($#ar == 5){
      if ($unmatchedOnly && ($ar[0] != -1)) {
        $show = 0;
      }
      if ($show) {
        print $tex sprintf "%s & \\textarabic{%s} & \\textarabic{%s} & %s  & %d & %s",
          $ar[1],$ar[2],$ar[4],tex_escape($ar[3]),$ar[0],tex_escape($ar[5]);
        print $tex " \\\\\n";
        print $csv sprintf "%s,%s,%s,%s,%d,%s\n",
          $ar[1],$ar[2],$ar[4],$ar[3],$ar[0],$ar[5];
      }
    }
  }
  print $tex "\n";
  print $tex get_tex_footer();
  $fh->close;
  $tex->close;
  $csv->close;
}
sub get_tex_header_headwords {
  my $t = <<'EOT';
\documentclass{book}
\usepackage{array}
\usepackage{longtable}
\usepackage{setspace}
\usepackage{fontspec}
\usepackage{polyglossia}
\usepackage{lastpage}
\usepackage{fancyhdr}
\usepackage[hmargin=1cm,vmargin=3cm]{geometry}
\setmainlanguage{english}
\setotherlanguages{arabic,greek}
\newfontfamily\arabicfont[Script=Arabic,Scale=0.9]{Droid Arabic Naskh}
%\newfontfamily\arabicfont[Script=Arabic,Scale=2.0]{Amiri}
%\newfontfamily\greekfont[Script=Greek,Scale=1.1]{Galatia SIL}
\newfontfamily\englishfont[Script=Latin,Scale=0.8]{Droid Sans}

\pagestyle{fancy}
\fancyhf{}
\lhead{Head Words}
\rhead{}
\lfoot{\today}
\rfoot{Page \thepage/\pageref{LastPage}}
\begin{document}
\setlength{\tabcolsep}{1mm}
\setlength{\parindent}{0mm}
%\begin{center}
\begin{longtable}{cccccc}
EOT
  return $t;
}




sub get_tex_header {
  my $t = <<'EOT';
\documentclass{book}
\usepackage{array}
\usepackage{longtable}
\usepackage{setspace}
\usepackage{fontspec}
\usepackage{polyglossia}
\usepackage{lastpage}
\usepackage{fancyhdr}
\usepackage[hmargin=1cm,vmargin=3cm]{geometry}
\setmainlanguage{english}
\setotherlanguages{arabic,greek}
\newfontfamily\arabicfont[Script=Arabic,Scale=1.5]{Droid Arabic Naskh}
%\newfontfamily\arabicfont[Script=Arabic,Scale=2.0]{Amiri}
%\newfontfamily\greekfont[Script=Greek,Scale=1.1]{Galatia SIL}
\newfontfamily\englishfont[Script=Latin,Scale=1.1]{Droid Sans}

\pagestyle{fancy}
\fancyhf{}
\lhead{Long Roots}
\rhead{}
\lfoot{\today}
\rfoot{Page \thepage/\pageref{LastPage}}
\begin{document}
\setlength{\tabcolsep}{5mm}
\setlength{\parindent}{0mm}
%\begin{center}
\begin{longtable}{ccccccc}
EOT
  return $t;
}
#
#
#
sub get_tex_footer {
  my $t = <<'EOT';
\end{longtable}
\end{document}
EOT
  return $t;
}
###########################################################################
# main
#
# eg perl links.pl --db vanilla.sqlite --node n9017
##########################################################################
GetOptions (
            "log-dir=s" => \$logDir,
            "dbid=s" => \$dbid,
            "db=s" => \$dbname,
            "dir=s" => \$xmlDir,
            "summary" => \$doSummary,
            "conv" => \$doConversionErrors,
            "long-roots" => \$doLongRoots,
            "wrong-letter" => \$doWrongLetter,
            "headwords" => \$doHeadWords,
            "unmatched" => \$unmatchedOnly,
            "questionmarks" => \$doDoubleQuestions,
            "all" => \$doAll
           )
  or die("Error in command line arguments");

$logDir = getLogDirectory($logDir,$dbid);
if (! $dbid ) {
  print STDERR "No run ID specified, exiting\n";
  exit 1;
}
if ($doAll) {
 $doSummary=1;
 $doConversionErrors=1;
 $doLongRoots=1;
 $doWrongLetter=1;
 $doHeadWords=1;
 $doDoubleQuestions=1;
}
if ($doDoubleQuestions && $xmlDir) {
  check_double_questions($xmlDir,$dbname);
}
summaryStats($logDir,$dbid)     unless ! $doSummary;
convErrors($logDir,$dbid)       unless ! $doConversionErrors;
wrong_letter($dbname,$dbid)     unless ! $doWrongLetter;
check_long_roots($dbname,$dbid) unless ! $doLongRoots;
headwords($dbid)               unless ! $doHeadWords;
