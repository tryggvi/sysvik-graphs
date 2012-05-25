#!/usr/bin/perl
# Varnish graph plugin for Sysvik - www.sysvik.com
#
# Put this file into /etc/sysvik/custom.d ; chmod 755 /etc/sysvik/custom.d/varnish.pl
#
# v1.0 (2012-05-25)
#
# Author: Tryggvi Farestveit <tryggvi@ok.is>
# License: GPLv2
# https://github.com/tryggvi/sysvik-graphs
#
# Requires: 
#	yum install -y perl-XML-Simple
#
use strict;
use File::Basename;
use XML::Simple;

# Path to varnishstat
my $varnishstat = "/usr/bin/varnishstat";

# Fields to monitor and graph
# 	The uptime is required
my @fields = (
	"uptime",
	"client_conn",
	"client_req",
	"backend_fail",
	"cache_hit",
	"cache_miss",
	"cache_hitpass"
);

# Print out debug information
my $verbose = 0;

### No need to edit below
my $workfile = "/var/lib/sysvik/custom/varnish.dat";
my $workdir = dirname($workfile);

if(!-e $workdir){
	# Create dir if it does not exists
	system("/bin/mkdir -p $workdir");
	print "Creating $workdir\n" if $verbose;
}

sub GetStats($){
	my ($fields) = @_;

	my $cmd = "$varnishstat -f $fields -1 -x";
	print "Running $cmd\n" if $verbose;
	my $raw = `$cmd`;

	return $raw;
}

sub SaveStats($){
	my ($raw) = @_;

	print "Saving to $workfile\n" if $verbose;
	open(F, ">$workfile");
	print F $raw;
	close(F);
}

sub CalcAvg($$$){
	my ($secs, $current, $last) = @_;

	if($secs > 0){
		my $diff = int(($current - $last)/$secs);
		return $diff;
	} else {
		return 0;
	}
}

sub SysvikGauge($$$){
	my ($key, $description, $value) = @_;
	print "gauge $key=$value $description\n";
}

sub SysvikGraph($$$$){
	my ($name, $ds, $title, $vertical_label) = @_;
	print "graph $name $ds $title;;$vertical_label\n";
}

# Combine fields to string
my $s_fields = join(",", @fields);

# Get current data
my $raw = GetStats($s_fields);
my $xml = new XML::Simple;
my $current = $xml->XMLin($raw);


my $last;
my $xml2;
if(-e $workfile){
	# Get last saved data
	$xml2 = new XML::Simple;
	$last = $xml2->XMLin($workfile);
}

my $secs_current = $current->{stat}->{uptime}->{value};
my $secs_last = $last->{stat}->{uptime}->{value};
my $secs = $secs_current - $secs_last;

if($secs_current eq $secs_last){
	# Ignore - Varnish is not running
	print "Stats not updating. Is varnish runnning?\n" if $verbose;
} elsif($secs_current < $secs_last ){
	print "Counter reset. Ignoring\n" if $verbose;
} else {
	print "Last run $secs ago\n" if $verbose;
	foreach(@fields){
		my $field = $_;
		if($field ne "uptime"){
			my $c_value = $current->{stat}->{$field}->{value};
			my $l_value = $last->{stat}->{$field}->{value};

			if(!defined($l_value)){
				print "$field: New data. Ignoring this round.\n" if $verbose;
				next;
			} else {
				my $description = $current->{stat}->{$field}->{description};

				my $avg = CalcAvg($secs, $c_value, $l_value);

				SysvikGauge($field, $description, $avg);
				SysvikGraph($field, $field, $description, "Secs");


				print "$field: $c_value -> $l_value / AVG: $avg /secs\n" if $verbose;
			}
		}
	}
}

# Save current XML data to 
SaveStats($raw);


