#!/usr/bin/perl
### Created by Karthikeyan P, Date: 15-April-2024, Version: 1.0, Initial release
### Script Name: get_impact_metrics.pl
### This Script will fetch the Performance KPI's from running instance of Netcool Impact Instance.
### Script Accepts following input parameters.
###  Impact zip package created by $IMPACT_HOME/bin/nci_collect_logs executable

use strict;
use warnings;
use Cwd qw(cwd);
use File::Path qw(rmtree);
use Data::Dumper;
use JSON::PP;

############################
### FUNCTIONS ###
sub extract_impact_pkg {
  my ($impact_pkg, $tempdir) = @_;
  system("unzip $impact_pkg -d $tempdir > /dev/null 2>&1")
}

sub get_impact_version {
  my ($version_out_file) = @_;
  my $version_var;
  open(my $version_out_FH, $version_out_file) || die "Unable to open the file !.";
  my @version_lines = <$version_out_FH>;
  chop(@version_lines);
  foreach my $vline (@version_lines) { ## Extracting only the First Entry.
    $version_var.=$vline;
   }
 chomp($version_var);
 close($version_out_FH);
 #print $version_var;
 my @var_match = $version_var =~ m/Impact Installed Component Version\W+Version:\W(\d+\.\d+\.\d+\.\d+)/; 
 if (length(@var_match) == 1) { ## This Should return only one value.
   return $var_match[0];
   }
 else {
   return "99";
   }
}

sub get_cluster_info {
  my($ns_props) = @_;
  my @cluster_match;
  open(my $cluster_out_FH, $ns_props) || die "Unable to open the file !.";
  my @cluster_lines = <$cluster_out_FH>;
  foreach my $cluster_line(@cluster_lines) {
   if($cluster_line =~ m/impact.nameserver.count/)
     {
      @cluster_match = $cluster_line =~ m/impact.nameserver.count\W(\d+)/;
     }
   }
  close($cluster_out_FH);
  if (length(@cluster_match) == 1) {
    return $cluster_match[0]; ## This Should return only one value.
     }
  else {
    return "99";
    }
}

sub get_cluster_name {
  my($serverdir) = @_;
  opendir(my $server_DH, $serverdir) || die "Cannot open $serverdir: $!";
  my @server_name = grep(!/^\.\.?|^ImpactUI/, readdir $server_DH);
  #print Dumper(\@server_name);
  #print length(@server_name);
  if (length(@server_name) == 1) { 
    return $server_name[0]; ## This Should return only one value.
   }
 else { 
   return "99";
   }
 closedir($server_DH);
}

sub get_policy_opview_count {
  my($policydir) = @_;
  opendir(my $policy_DH, $policydir) || die "Cannot open $policydir: $!";
  my @policy_list = grep(/.*\.ipl$/, readdir $policy_DH);
  my $policy_ctr = @policy_list;
  #print Dumper($policy_ctr); 
  closedir($policy_DH);
  opendir(my $opview_DH, $policydir) || die "Cannot open $policydir: $!";
  my @opview_list = grep(/.*Opview.*\.ipl$/, readdir $opview_DH);
  my $opview_ctr = @opview_list;
  #print Dumper($opview_ctr);
  closedir($opview_DH);
  return $policy_ctr, $opview_ctr;
}

sub get_jvm_params {
  my($jvm_file) = @_;
  my(@xmx_match, @xms_match);
  open(my $jvm_FH, $jvm_file) || die "Unable to open the file !.";
  my @jvm_lines = <$jvm_FH>;
  foreach my $jvm_line (@jvm_lines) { 
    if($jvm_line =~ m/^\-Xmx/) {
      @xmx_match = $jvm_line =~ m/-Xmx(\d+\w)/;
      #print Dumper(\@xmx_match);
      }
   elsif($jvm_line =~ m/^\-Xms/) {
      @xms_match = $jvm_line =~ m/-Xms(\d+\w)/;
      #print Dumper(\@xms_match);
      }
   }
  close($jvm_FH);
  return $xmx_match[0], $xms_match[0];
}  

sub check_auth {
  my($server_xml) = @_;
  my @xml_match;
  open(my $xml_FH, $server_xml) || die "Unable to open the file !.";
  my @xml_lines = <$xml_FH>;
  foreach my $xml_line (@xml_lines) {
    if(($xml_line =~ m/shared\.config\.dir/) && ($xml_line !~ m/features\.xml|httpEndpoints\.xml|guiLibraries\.xml|guiDataSource\.xml/)){
      #print "$xml_line\n";
      @xml_match = $xml_line =~ m/shared\.config\.dir\}\/(.*\.xml)\"/;
      #print Dumper(\@xml_match);
    }
  }
 close($xml_FH);
 if(length(@xml_match) == 1) {
    if($xml_match[0] =~ m/ldapRegistry\.xml/) {
      return "TRUE";
       }
    else {
      return "FALSE";
       }
    }
 else {
   return "99";
   }
}

sub get_eventproc_threads {
  my($event_pfile) = @_;
  my(@max_threads, @min_threads);
  open(my $event_FH, $event_pfile) || die "Unable to open the file !.";
  my @event_lines = <$event_FH>;
  foreach my $event_line(@event_lines) {
     chop($event_line);
     if($event_line =~ m/impact\.eventprocessor\.maxnumthreads/) {
        @max_threads = $event_line =~ m/impact\.eventprocessor\.maxnumthreads=(\d+)/;
         }
     elsif($event_line =~ m/impact\.eventprocessor\.minnumthreads/) {
        @min_threads = $event_line =~ m/impact\.eventprocessor\.minnumthreads=(\d+)/;
         }
     }
  close($event_FH);
  return $max_threads[0], $min_threads[0];
}
#################

### MAIN ###
my $script_dir = cwd;
my %out = ();
my $script_name = "get_impact_metrics.pl";
my $impact_kpi_file = "$script_dir/impact_kpi.out";
my $temp_dir = "$script_dir/temp";
if ( -d  $temp_dir) {
   rmtree("$temp_dir");
}
mkdir $temp_dir, 0755 or die "Failed to create directory: $!";
my($impact_package) = @ARGV;
extract_impact_pkg($impact_package, $temp_dir);
my $version_output_file = "$temp_dir/versioninfo.log" ;
my $impact_version = get_impact_version($version_output_file);
$out{"ImpactVersion"} = $impact_version;
my $nameserver_props = "$temp_dir/etc/nameserver.props";
my $nameserver_count = get_cluster_info($nameserver_props);
$out{"ImpactServerCount"} = $nameserver_count;
my $wlp_server_dir = "$temp_dir/wlp/usr/servers";
my $nci_server = get_cluster_name($wlp_server_dir);
$out{"ImpactServerName"} = $nci_server;
if ($nci_server =~ m/99/) { 
   print "Multiple Impact Servers are Found, Unable to continue";
   exit;
  }
my $policy_dir = "$temp_dir/policy";
my @policy_count = get_policy_opview_count($policy_dir);
#print Dumper(\@policy_count);
my $p_ctr = @policy_count; 
#print "$p_ctr\n";
if ($p_ctr == 2) { ## policy_count Array should contain only 2 values.
  $out{"PoliciesCount"} = $policy_count[0]; ## First Value in Array is Policy Count.
  $out{"OpViewsCount"} = $policy_count[1]; ## Second Value in Array is Operator Views Count.
    }
else {
  print "Unable to get the Count of Policies & Opviews, Exit";
  exit;
    }
my $jvm_param_file = "$temp_dir/wlp/usr/servers/ImpactUI/jvm.options";
my @jvm_values = get_jvm_params($jvm_param_file);
#print Dumper(\@jvm_values);
my $jvm_ctr = @jvm_values;
if ($jvm_ctr == 2) { ## jvm_values Array should contain only 2 values.
  $out{"Xmx"} = $jvm_values[0]; ## First Value in Array is Max Java Memory Heap Size.
  $out{"Xms"} = $jvm_values[1]; ## Second Value in Array is Min Java Memory Heap Size.
    }
else {
  print "Unable to get the JVM Memory Heap Size Values, Exit";
  exit;
    }
my $server_xml_file = "$temp_dir/wlp/usr/servers/ImpactUI/server.xml";
my $ldap_flag = check_auth($server_xml_file);
$out{"LDAPIntegration"} = $ldap_flag;
my $eventproc_props = "$temp_dir/etc/$nci_server\_eventprocessor.props";
my @event_proc_threads = get_eventproc_threads($eventproc_props);
#print Dumper(\@event_proc_threads);
my $eventthread_ctr = @event_proc_threads;
if ($eventthread_ctr == 2) { ## jvm_values Array should contain only 2 values.
  $event_proc_threads[0] =~ s/\=/:\ /g;
  $out{"EventProcessorMaxThreads"} = $event_proc_threads[0]; ## First Value in Array is Event Processor Max Number of Threads.
  $event_proc_threads[1] =~ s/\=/:\ /g;
  $out{"EventProcessorMinThreads"} = $event_proc_threads[1]; ## Second Value in Array is Event Processor Min Number of Threads..
    }
else {
  print "Unable to get the Event Processor Max/Min Number of ThreadsValues, Exit";
  exit;
   }

my $json =  encode_json(\%out);
open(my $KPI_FH, ">$impact_kpi_file") || die "Unable to open the file for writing!.";
  print $KPI_FH "$json\n";
close($KPI_FH);
