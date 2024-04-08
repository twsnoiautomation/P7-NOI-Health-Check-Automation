#!/usr/bin/perl
## Created by Karthikeyan P, Date: 05-April-2024, Version: 1.0, Initial release
## Script Name: get_nco_metrics.pl
## This Script will fetch the Performance KPI's from running instance of Netcool Omnibus ObjectServer.
## Script Accepts following input parameters.
## Netcool Home directory $NCHOME = $ARGV[0]
## ObjectServer Name $OSNAME = $ARGV[1]
## ObjectServer SQL UserName $os_user = $ARGV[2]
## ObjectServer SQL User Password $os_pwd = $ARGV[3]

use strict;
use warnings;
use Cwd qw(cwd);
use File::Path qw(rmtree);
use Data::Dumper;

#### FUNCTIONS ####
sub set_env {
  my ($nchome) = @_;
  if (not defined $nchome) {
    die "Enter the PATH of NCHOME";
   }
  else {
    chomp($nchome);
    my $omnihome = "$nchome/omnibus";
    my $omnilog = "$omnihome/log";
    return  $omnihome, $omnilog;
   }
}

sub exec_nco_version {
  my ($omnihome, $tempdir) = @_;
  my $nco_out_file = "$tempdir/nco_version.out";
  open(my $version_FH, ">", $nco_out_file) || die "Unable to open the file !.";
  system("$omnihome/bin/nco_id -s > $nco_out_file"); 
  close $version_FH;
  return $nco_out_file;
}

sub extract_nco_pkg {
  my ($nco_pkg, $tempdir) = @_;
  system("unzip $nco_pkg -d $tempdir > /dev/null 2>&1")
}

sub get_nco_version {
  my ($version_out_file) = @_;
  open(my $version_out_FH, $version_out_file) || die "Unable to open the file !.";
  my @version_lines = <$version_out_FH>;
  foreach my $vline (@version_lines) { ## Extracting only the First Entry.
    next if($vline !~ m/IBM_Tivoli_Netcool_OMNIbus/);
    return "$vline";
    last if($vline =~ m/IBM_Tivoli_Netcool_OMNIbus/);
   }
}

sub get_os_profiling {
  my ($os_etc_file) = @_;
  open(my $etc_FH, $os_etc_file) || die "Unable to open the file !.";
    my @etc_lines = <$etc_FH>;
    foreach my $etc_prop(@etc_lines) {
       if($etc_prop =~ m/^Profile:\W\w+/) {
         #print $etc_prop;
         return $etc_prop;
        }
      }
   close($etc_FH);
}

sub get_os_profiling_stats {
  my($os_profiling_log) = @_;
  open(my $profile_FH, $os_profiling_log) || die "Unable to open the file !.";
     my @profile_lines = <$profile_FH>;
     foreach (reverse(@profile_lines)) {
       if(m/.*Total time in the report period.*:\W(.*)/) {
         #print $_;
         return $_;
        }
      last if(m/.*Total time in the report period.*:\W(.*)/);
      }
  close($profile_FH);
}

sub get_trigger_stats {
  my($trigger_stats_log) = @_;
  open(my $trigger_FH, $trigger_stats_log) || die "Unable to open the file !.";
    my @trigger_lines = <$trigger_FH>;
  foreach (reverse(@trigger_lines)) {
    if(m/.*Time for all triggers in report period.*/) {
      #print $_;
      return $_;
     }
    last if(m/.*Time for all triggers in report period.*/);
   }
  close($trigger_FH);
}

sub create_trigger_sql {
  my($my_sql_file) = @_;
  open(my $SQL_FH, ">$my_sql_file") || die "Unable to open the file for writing!.";
    print $SQL_FH "select count(*) as Triggers from catalog.triggers;\n";
    print $SQL_FH "go\n";
 close($SQL_FH); 
}

sub create_procedure_sql {
  my($my_sql_file) = @_;
  open(my $SQL_FH, ">$my_sql_file") || die "Unable to open the file for writing!.";
    print $SQL_FH "select count(*) as procedures from catalog.procedures;\n";
    print $SQL_FH "go\n";
  close($SQL_FH);
  }

sub create_rfilters_sql {
  my($my_sql_file) = @_;
  open(my $SQL_FH, ">$my_sql_file") || die "Unable to open the file for writing!.";
    print $SQL_FH "select count(*) as r_filters from security.restriction_filters;\n";
    print $SQL_FH "go\n";
  close($SQL_FH);
 }

sub create_status_count_sql {
  my($my_sql_file) = @_;
  open(my $SQL_FH, ">$my_sql_file") || die "Unable to open the file for writing!.";
    print $SQL_FH "select StatusInserts as status from master.stats where StatTime in (select max(StatTime) from master.stats);\n";
    print $SQL_FH "go\n";
  close($SQL_FH);
}

sub create_journal_count_sql {
  my($my_sql_file) = @_;
  open(my $SQL_FH, ">$my_sql_file") || die "Unable to open the file for writing!.";
    print $SQL_FH "select JournalInserts as journal from master.stats where StatTime in (select max(StatTime) from master.stats);\n";
    print $SQL_FH "go\n";
  close($SQL_FH);
}

sub exec_os_sql {
  my($omnihome, $os_name, $user, $pwd, $cmd_file, $sql_out) = @_;
  system("$omnihome\/bin\/nco_sql \-server $os_name \-username $user \-password $pwd \< $cmd_file \> $sql_out");
}

sub process_trigger_out {
  my($sql_output_file) = @_;
  my(@trigg_ctr);
  open(my $sqlout_FH, $sql_output_file) || die "Unable to open the file !.";
  my @trigger_out = <$sqlout_FH>;
  foreach my $t_outline(@trigger_out) {
    if(($t_outline =~ m/Triggers|\d+/) && !($t_outline =~ m/row affected/)){
      chomp($t_outline);
      push(@trigg_ctr, $t_outline);
    }
  }
  #print "@trigg_ctr\n";
  return @trigg_ctr;
  close($sqlout_FH);
}

sub process_procedure_out {
  my($proc_output_file) = @_;
  my(@proc_ctr);
  open(my $procout_FH, $proc_output_file) || die "Unable to open the file !.";
  my @procedure_out = <$procout_FH>;
  foreach my $p_outline(@procedure_out) {
    if(($p_outline =~ m/procedures|\d+/) && !($p_outline =~ m/row affected/)){
      chomp($p_outline);
      push(@proc_ctr, $p_outline);
    }
  }
  #print "@proc_ctr\n";
  return @proc_ctr;
  close($procout_FH);
}

sub process_rfilters_out {
  my($rfilters_output_file) = @_;
  my(@rfilter_ctr);
  open(my $rfilters_FH, $rfilters_output_file) || die "Unable to open the file !.";
  my @rfilters_out = <$rfilters_FH>;
  foreach my $rf_outline(@rfilters_out) {
    if(($rf_outline =~ m/r_filters|\d+/) && !($rf_outline =~ m/row affected/)){
      chomp($rf_outline);
      push(@rfilter_ctr, $rf_outline);
     }
  }
  #print "@rfilter_ctr\n";
  return @rfilter_ctr;
  close($rfilters_FH);
}

sub process_status_out {
  my($status_output_file) = @_;
  my(@status_ctr);
  open(my $status_FH, $status_output_file) || die "Unable to open the file !.";
  my @status_out = <$status_FH>;
  #print "Dumper(\@status_out)";
  foreach my $status_outline(@status_out) {
    if(($status_outline =~ m/status|\d+/) && !($status_outline =~ m/row affected/)){
      chomp($status_outline);
      push(@status_ctr, $status_outline);
     }
  }
  #print "@status_ctr\n";
  return @status_ctr;
  close($status_FH);
}

sub process_journal_out  {
  my($journal_output_file) = @_;
  my(@journal_ctr);
  open(my $journal_FH, $journal_output_file) || die "Unable to open the file !.";
  my @journal_out = <$journal_FH>;
  foreach my $journal_outline(@journal_out) {
  if(($journal_outline =~ m/journal|\d+/) && !($journal_outline =~ m/row affected/)){
    chomp($journal_outline);
    push(@journal_ctr, $journal_outline);
     }
       }
  #print "@journal_ctr\n";
  return @journal_ctr;
  close($journal_FH);
}

###### MAIN #######
#my $script_dir = "/home/netcool/tws_script/NOI";
my $script_dir = cwd;
my $script_name = "get_nco_metrics.pl";
my $nco_kpi_file = "$script_dir/nco_kpi.out";
my $temp_dir = "$script_dir/temp";
if ( -d  $temp_dir) {
   rmtree("$temp_dir"); 
} 
mkdir $temp_dir, 0755 or die "Failed to create directory: $!";
my $output_file = "$temp_dir/nco_output.txt";

my $num_args = $#ARGV + 1;
#print "$num_args\n";
if ($num_args != 4) { 
  print "Script needs 4 parameters as input\n";
  print "Provide the NCHOME, ObjectServerName, ObjectServerSQLUser, ObjectServerSQLUserPassword\n";
  print "Exit the Script\n";
  exit();
 }
#my($NCHOME, $OSNAME) = @ARGV;
my $NCHOME = $ARGV[0];
my $OSNAME = $ARGV[1];
my $os_user = $ARGV[2];
my $os_pwd = $ARGV[3];
#print "PATH of NCHOME: $nchome\n";

my($OMNIHOME, $OMNILOG) = set_env($NCHOME);
chomp($OMNIHOME, $OMNILOG);
my $version_output_file = exec_nco_version($OMNIHOME, $temp_dir);
my $nco_version = get_nco_version($version_output_file);
$nco_version =~ s/\s//g;;
#print "$nco_version\n";
#my($nco_package) = @ARGV;
#extract_nco_pkg($nco_package, $temp_dir);
#my $version_output_file = "$temp_dir/netcool/nco_id.stdout";
#my $nco_version = get_nco_version($version_output_file);
#print "$nco_version\n";

my $omni_etc = "$OMNIHOME/etc/$OSNAME\.props";
my $profile_flag = get_os_profiling($omni_etc);

my $profiler_log = "$OMNILOG/$OSNAME\_profiler_report.log1";
my $profile_stats = get_os_profiling_stats($profiler_log);

my $trigger_log = "$OMNILOG/$OSNAME\_trigger_stats.log1";
my $trigger_stats = get_trigger_stats($trigger_log);

my $trigger_sql_file = "$temp_dir/triggers.sql";
create_trigger_sql($trigger_sql_file);
my $trigger_out_file = "$temp_dir/trigger_out.txt";
exec_os_sql($OMNIHOME, $OSNAME, $os_user, $os_pwd, $trigger_sql_file, $trigger_out_file);
my @triggers = process_trigger_out($trigger_out_file);

my $procedure_sql_file = "$temp_dir/procedures.sql";
create_procedure_sql($procedure_sql_file);
my $procedure_out_file = "$temp_dir/procedure_out.txt";
exec_os_sql($OMNIHOME, $OSNAME, $os_user, $os_pwd, $procedure_sql_file, $procedure_out_file);
my @procedures = process_procedure_out($procedure_out_file);

my $rfilters_sql_file = "$temp_dir/rfilters.sql";
create_rfilters_sql($rfilters_sql_file);
my $rfilters_out_file = "$temp_dir/rfilters_out.txt";
exec_os_sql($OMNIHOME, $OSNAME, $os_user, $os_pwd, $rfilters_sql_file, $rfilters_out_file);
my @rfilters = process_rfilters_out($rfilters_out_file);

my $status_count_sql_file = "$temp_dir/status_count.sql";
create_status_count_sql($status_count_sql_file);
my $status_count_out_file = "$temp_dir/status_count_out.txt";
exec_os_sql($OMNIHOME, $OSNAME, $os_user, $os_pwd, $status_count_sql_file, $status_count_out_file);
my @status_stats = process_status_out($status_count_out_file);

my $journal_count_sql_file = "$temp_dir/journal_count.sql";
create_journal_count_sql($journal_count_sql_file);
my $journal_count_out_file = "$temp_dir/journal_count_out.txt";
exec_os_sql($OMNIHOME, $OSNAME, $os_user, $os_pwd, $journal_count_sql_file, $journal_count_out_file);
my @journal_stats = process_journal_out($journal_count_out_file);

open(my $nco_FH, ">$output_file") || die "Unable to open the file for writing!.";
  print $nco_FH "$nco_version\n";
  print $nco_FH "$profile_flag";
  print $nco_FH "$profile_stats";
  print $nco_FH "$trigger_stats";
  print $nco_FH "@triggers\n";
  print $nco_FH "@procedures\n";
  print $nco_FH "@rfilters\n";
  print $nco_FH "@status_stats\n";
  print $nco_FH "@journal_stats\n";
close($nco_FH);


open(my $KPI_FH, ">$nco_kpi_file") || die "Unable to open the file for writing!.";

 open(my $outputfile_FH, $output_file) || die "Unable to open the file !.";
   my @output_lines = <$outputfile_FH>;

    foreach my $output_line(@output_lines) {
      if($output_line =~ m/IBM_Tivoli_Netcool_OMNIbus/) {
        $output_line =~ s/IBM_Tivoli_Netcool_OMNIbus-/IBM_Tivoli_Netcool_OMNIbus:\ /;
        }
      elsif($output_line =~ m/Triggers/) {
        $output_line =~ s/Triggers/Triggers:\ /;
       }
      elsif($output_line =~ m/procedures/) {
        $output_line =~ s/procedures/procedures:\ /;
       }
      elsif($output_line =~ m/r_filters/) {
        $output_line =~ s/r_filters/r_filters:\ /;
       }
      elsif($output_line =~ m/status/) {
        $output_line =~ s/status/status:\ /;
       }
      elsif($output_line =~ m/journal/) {
        $output_line =~ s/journal/journal:\ /;
       }
     elsif($output_line =~ m/Total time in the report period/) {
       $output_line = substr($output_line,26);
       }
     elsif($output_line =~ m/Time for all triggers in report period/) {
       $output_line = substr($output_line,26);
       }
   $output_line =~ s/^\s+//g;
   print $KPI_FH "$output_line";
     #print "$output_line";
     }
 close($outputfile_FH);

close($KPI_FH);
