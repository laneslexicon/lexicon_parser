#!/usr/bin/perl
use strict;
use warnings;
use File::Find;
use English;
use FileHandle;
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
##################################################################################
# return list of log files in the given directory
###################################################################################
sub readLogDirectory {
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
  my $fileprefix = shift;
  my $filedir = shift;
  my ($xml,$lineno,$root,$word,$vol,$text,$node,$errChar,$position,$page);
  my ($fh,$outf,$out4f,$out5f);
  my @words;
  my $count = 0;
  my ($day,$month,$year) = (localtime)[3,4,5];
  my $rundate = sprintf "%04d-%02d-%02d",$year+1900,$month+1,$day;

  format TYPE4_TOP =
@<<<<<<<<<                                    Type 4 Error Report                                                                                                Page @<<<<
$rundate,                                                                                                                                                                $%

File       Line No    Root            Word                               Node         Vol/Page   Text
----------------------------------------------------------------------------------------------------------------------------------------------------------------------------
.

  format TYPE4 =
@<<<<<<<<<<@<<<<<<<<<<@<<<<<<<<<<<<<<<@<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<@<<<<<<<<<<<<@<<<<<<<<<<@<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<
$xml,$lineno,$root,$word,$node,$vol,$text
.

 format TYPE5_TOP =

@<<<<<<<<<                                                 Type 5 Error Report                                                                                     Page @<<<<
$rundate,                                                                                                                                            $%


File       Line No   Root            Word                               Node        Vol/Page    Char   Pos  Text
-----------------------------------------------------------------------------------------------------------------------------------------------------------------------------
.

  format TYPE5 =
@<<<<<<<<<<@<<<<<<<<<@<<<<<<<<<<<<<<<@<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<@<<<<<<<<<<<@<<<<<<<<<<@<<<<<<@<<<<@<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<
$xml,$lineno,$root,$word,$node,$vol,$errChar,$position,$text
.
  my @xmlfiles = qw(_A0 b0 t0 v0 j0 _H0 x0 d0 _0 r0 z0 s0 $0 _S0 _D0 _T0 _Z0 _E0 g0 f0 q0 k0 l0 m0 n0 h0 w0 _Y0 q1 k1 l1 m1 n1 h1 w1 _Y1);


  open $out4f, ">:encoding(UTF8)", "error_type4.txt";
  open $out5f, ">:encoding(UTF8)", "error_type5.txt";
  $out4f->format_name("TYPE4");
  $out4f->format_top_name("TYPE4_TOP");
  $out5f->format_name("TYPE5");
  $out5f->format_top_name("TYPE5_TOP");


  if ($filedir =~ /\/$/) {
    chop $filedir;
  }

  foreach my $logfile (@xmlfiles) {
    my $file = sprintf "%s/%s_%s_conv.log",$filedir,$fileprefix,$logfile;
    if (! -e $file ) {
      print STDERR "Could not find file $file\n";
      next;
    }
#    $fileName = $1;
#    $fileName =~ /\/([^.\/])+.xml$/;
    $xml = sprintf "%s.xml",$logfile;
    open $fh, "<",$file || return;
    <$fh>;
    while (<$fh>) {
      chomp;
      /^(\d+),/;
      if ($1 == 4) {
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
        write $out4f;
        # if (($out4f->format_lines_left == 0) && ($count > 0)) {
        #   my $x = $out4f;
        #   print $x sprintf "Total: %d",$count;
        # }
        $count++;
      }
      if ($1 == 5) {
        @words = split ",",$_;
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
  my $fileprefix = shift;
  my $filedir = shift;
  my @xmlfiles = qw(_A0 b0 t0 v0 j0 _H0 x0 d0 _0 r0 z0 s0 $0 _S0 _D0 _T0 _Z0 _E0 g0 f0 q0 k0 l0 m0 n0 h0 w0 _Y0 q1 k1 l1 m1 n1 h1 w1 _Y1);

  my $pattern = "lexicon[^\.]+conv.log\$";
  my ($filename,$type2,$type3,$type4,$type5,$type6,$typeother);
  my ($fh,$outf);
  my ($day,$month,$year) = (localtime)[3,4,5];
  my $rundate = sprintf "%04d-%02d-%02d",$year+1900,$month+1,$day;
  my @convfile =  readLogDirectory("/home/andrewsg/parse",$pattern);
  format SUMMARY_TOP =
   @<<<<<<<<<                           Error Summary                              Page @<<
$rundate,$%

   File       Double ?? (2)   Ampersand (3)   A-hat (4)   Non Buck (5)    A_ (6)     Other
   ----------------------------------------------------------------------------------------
.
  format SUMMARY =
   @<<<<<<<<<<@<<<<<<<<<<<<<<<@<<<<<<<<<<<<<<<@<<<<<<<<<<<@<<<<<<<<<<<<<<<@<<<<<<<<<<@<<<<<
$filename,$type2,$type3,$type4,$type5,$type6,$typeother
.
  open $outf, ">:encoding(UTF8)", "error_summary.txt";
  $outf->format_name("SUMMARY");
  $outf->format_top_name("SUMMARY_TOP");
  if ($filedir =~ /\/$/) {
    chop $filedir;
  }

  foreach my $logfile (@xmlfiles) {
    my $file = sprintf "%s/%s_%s_conv.log",$filedir,$fileprefix,$logfile;
    if (! -e $file ) {
      print STDERR "Could not find file $file\n";
      next;
    }
   $type2 = $type3 = $type4 = $type5 = $type6 = $typeother = 0;
   if ($file =~ /\w_([\w_\$]+)_conv.log/) {
     $filename = sprintf "%s.xml",$1;
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
       elsif (/^6/) {
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

summaryStats("lexicon","/home/andrewsg/parse");
convErrors("lexicon","/home/andrewsg/parse");
