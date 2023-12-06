#!/usr/bin/perl
use strict;
use warnings;
use 5.30.0;
no autovivification;
binmode STDOUT, ":utf8";
use utf8;
use open ':std', ':encoding(UTF-8)';
use Data::Printer;
use Data::Dumper;
use JSON;
use Encode;
use Encode::Unicode;
use Scalar::Util qw(looks_like_number);
use Math::Round qw(nearest);
use Text::CSV qw( csv );
use Statistics::Descriptive;
use Statistics::LineFit;
use FindBin;
use lib "$FindBin::Bin/../../lib";

# Deaths are exported from https://infoshare.stats.govt.nz/default.aspx
# Population -> Deaths - VSD -> Deaths by age and sex (Annual-Dec)
# Filters : All sexes, all Times, Ages by 1 year from Less than one year to 100 years and over
# Populations are exported from the same source
# Population -> Population Estimates - DPE -> Estimated Resident Population by Age and Sex (1991+) (Annual-Dec)
# Filters : Estimate Type "As at", all Population Groups (sexes), all Times, Observations (age) at 0 years => 94 years, and 95 years and Over.

my %deaths      = ();
my %pop         = ();
my %age_groups  = ();
$age_groups{0}  = 'Total';

my %data        = ();

my $deaths_file = 'VSD349204_20231206_025927_97.csv';
my $pop_file    = 'DPE403903_20231206_032556_74.csv';

load_deaths();
load_pop();

open my $out, '>:utf8', 'new_zealand.csv';
say $out "year;age_group;age_group_name;deaths;population;deaths_per_100000;";
for my $year (2000 .. 2022) {
	for my $age_group (sort{$a <=> $b} keys %{$deaths{$year}}) {
		my $age_group_name = $age_groups{$age_group}      // die;
		my $deaths         = $deaths{$year}->{$age_group} // die;
		my $population     = $pop{$year}->{$age_group}    // die;
		my $deaths_per_100000 = $deaths * 100000 / $population;
		say $out "$year;$age_group;$age_group_name;$deaths;$population;$deaths_per_100000;";
		$data{$age_group}->{$year} = $deaths_per_100000;
	}
}
close $out;

for my $age_group (sort{$a <=> $b} keys %data) {
	my $age_group_name = $age_groups{$age_group} // die;

	my @baseline;
	for my $year (sort{$a <=> $b} keys %{$data{$age_group}}) {
		next unless $year >= 2013 && $year <= 2019;
		my $value = $data{$age_group}->{$year} // die;
		push @baseline, $value;
	}
	my $mean     = mean(@baseline);
	my $stat     = Statistics::Descriptive::Full->new();
	$stat->add_data(@baseline);
	my $baseline_stddev = $stat->standard_deviation();

	# Corresponding years
	my @baseline_refnum = (1, 2, 3, 4, 5, 6, 7);

	# Calculate the slope and y-intercept using linear regression
	my $line_fit = Statistics::LineFit->new();
	$line_fit->setData(\@baseline_refnum, \@baseline);
	my ($intercept, $slope) = $line_fit->coefficients();

	# Calculate the Y-axis points for each y_num
	open my $out, '>:utf8', $age_group_name. "_trends.csv";
	say $out "year;deaths_per_100000;lin_trend_y;z_score;yearly_offset;dev_percentage;";
	foreach my $y_num (1 .. 10) {
	    my $lin_trend_y       = nearest(0.01, $slope * $y_num + $intercept);
	    my $year              = 2012   + $y_num;
		my $deaths_per_100000 = $data{$age_group}->{$year} // die;
	    my $dev_percentage    = nearest(0.01, ($deaths_per_100000 - $lin_trend_y) * 100 / $lin_trend_y);

	    # Calculates z-score.
	    my $z_score = nearest(0.001, ($deaths_per_100000 - $mean) / $baseline_stddev);

	    # Calculate percentage of deviation from standard dev.
	    my $yearly_offset    = nearest(0.01, $data{$age_group}->{$year} - $mean);
	    my $dev_to_mean      = nearest(0.1,  $yearly_offset / $mean * 100);

	    say "Z-score for $year              : $z_score";
	    say "Deaths Per 100K                : $deaths_per_100000";
	    say "Deviation percentage for $year : $dev_percentage%";
	    say "Lin Trend Y                    : $lin_trend_y";
		my $line           = "$year;$deaths_per_100000;$lin_trend_y;$z_score;$yearly_offset;$dev_percentage";
		my @elems          = split ';', $line;
		$line              = undef;
		for my $elem (@elems) {
			$elem          =~ s/\./,/ if $elem =~ /\./;
			$line          .= ";$elem" if $line;
			$line          = $elem unless $line;
		}
		say $out $line;
	}
	close $out;

	sub mean {
	    my @data = @_;
	    my $total = 0;
	    $total += $_ for @data;
	    return $total / @data;
	}
}

sub load_deaths {
	my %headers = ();
	open my $in, '<:utf8', $deaths_file;
	while (<$in>) {
		chomp $_;
		$_ =~ s/\"//g;
		my ($year) = split ',', $_;
		next unless defined $year;
		if ($year eq ' ') {
			my @headers = split ",", $_;
			my $scope   = (scalar @headers - 1) / 3;
			my $from    = scalar @headers - $scope;
			for my $header_ref ($from .. scalar @headers - 1) {
				my $header = $headers[$header_ref] // die;
				$headers{$header_ref} = $header;
			}
		} else {
			next unless keys %headers;
			next unless looks_like_number($year);
			my %values = ();
			my @values = split ',', $_;
			my $scope   = (scalar @values - 1) / 3;
			my $from    = scalar @values - $scope;
			for my $value_ref ($from .. scalar @values - 1) {
				my $value  = $values[$value_ref]  // die;
				my $header = $headers{$value_ref} // die;
				# my ($age_group, $age_group_name) = age_group_5_from_header($header);
				my ($age_group, $age_group_name) = age_group_10_from_header($header);
				$deaths{$year}->{$age_group} += $value;
				$deaths{$year}->{'0'} += $value;
			}
		}
	}
	close $in;
}

sub load_pop {
	my %headers = ();
	open my $in, '<:utf8', $pop_file;
	while (<$in>) {
		chomp $_;
		$_ =~ s/\"//g;
		my ($year) = split ',', $_;
		next unless defined $year;
		if ($year eq ' ') {
			my @headers = split ",", $_;
			my $scope   = (scalar @headers - 2) / 3;
			my $from    = scalar @headers - $scope;
			for my $header_ref ($from .. scalar @headers - 1) {
				my $header = $headers[$header_ref] // die;
				$headers{$header_ref} = $header;
			}
		} else {
			next unless keys %headers;
			next unless looks_like_number($year);
			my %values = ();
			my @values = split ',', $_;
			my $scope   = (scalar @values - 2) / 3;
			my $from    = scalar @values - $scope;
			for my $value_ref ($from .. scalar @values - 1) {
				my $value  = $values[$value_ref]  // die;
				my $header = $headers{$value_ref} // die;
				# my ($age_group, $age_group_name) = age_group_5_from_header($header);
				my ($age_group, $age_group_name) = age_group_10_from_header($header);
				next unless looks_like_number $value;
				$pop{$year}->{$age_group} += $value;
				$pop{$year}->{'0'} += $value;
			}
		}
	}
	close $in;
}

sub age_group_10_from_header {
	my $header = shift;
	$header =~ s/Less than 1 year/0/;
	$header =~ s/ years and over//;
	$header =~ s/ years//;
	$header =~ s/ year//;
	$header =~ s/ Years and Over//;
	$header =~ s/ Years//;
	$header =~ s/ Year//;
	my ($age_group, $age_group_name);
	if ($header >= 0 && $header < 1) {
		$age_group = '1';
		$age_group_name = 'Under 1 year';
	} elsif ($header >= 1 && $header < 10) {
		$age_group = '2';
		$age_group_name = '1 - 9 years';
	} elsif ($header >= 10 && $header < 20) {
		$age_group = '3';
		$age_group_name = '10 - 19 years';
	} elsif ($header >= 20 && $header < 30) {
		$age_group = '4';
		$age_group_name = '20 - 29 years';
	} elsif ($header >= 30 && $header < 40) {
		$age_group = '5';
		$age_group_name = '30 - 39 years';
	} elsif ($header >= 40 && $header < 50) {
		$age_group = '6';
		$age_group_name = '40 - 49 years';
	} elsif ($header >= 50 && $header < 60) {
		$age_group = '7';
		$age_group_name = '50 - 59 years';
	} elsif ($header >= 60 && $header < 70) {
		$age_group = '8';
		$age_group_name = '60 - 69 years';
	} elsif ($header >= 70 && $header < 80) {
		$age_group = '9';
		$age_group_name = '70 - 79 years';
	} elsif ($header >= 80 && $header < 90) {
		$age_group = '10';
		$age_group_name = '80 - 89 years';
	} elsif ($header >= 90) {
		$age_group = '11';
		$age_group_name = '90+ years old'
	} else {
		die "header : $header";
	}
	$age_groups{$age_group} = $age_group_name;
	return ($age_group, $age_group_name);
}

sub age_group_5_from_header {
	my $header = shift;
	$header =~ s/Less than 1 year/0/;
	$header =~ s/ years and over//;
	$header =~ s/ years//;
	$header =~ s/ year//;
	$header =~ s/ Years and Over//;
	$header =~ s/ Years//;
	$header =~ s/ Year//;
	my ($age_group, $age_group_name);
	if ($header >= 0 && $header < 1) {
		$age_group = '1';
		$age_group_name = 'Under 1 year';
	} elsif ($header >= 1 && $header < 5) {
		$age_group = '2';
		$age_group_name = '1 - 4 years';
	} elsif ($header >= 5 && $header < 10) {
		$age_group = '3';
		$age_group_name = '5 - 9 years';
	} elsif ($header >= 10 && $header < 15) {
		$age_group = '4';
		$age_group_name = '10 - 14 years';
	} elsif ($header >= 15 && $header < 20) {
		$age_group = '5';
		$age_group_name = '15 - 19 years';
	} elsif ($header >= 20 && $header < 25) {
		$age_group = '6';
		$age_group_name = '20 - 24 years';
	} elsif ($header >= 25 && $header < 30) {
		$age_group = '7';
		$age_group_name = '25 - 29 years';
	} elsif ($header >= 30 && $header < 35) {
		$age_group = '8';
		$age_group_name = '30 - 35 years';
	} elsif ($header >= 35 && $header < 40) {
		$age_group = '9';
		$age_group_name = '35 - 39 years';
	} elsif ($header >= 40 && $header < 45) {
		$age_group = '10';
		$age_group_name = '40 - 44 years';
	} elsif ($header >= 45 && $header < 50) {
		$age_group = '11';
		$age_group_name = '45 - 49 years';
	} elsif ($header >= 50 && $header < 55) {
		$age_group = '12';
		$age_group_name = '50 - 54 years';
	} elsif ($header >= 55 && $header < 60) {
		$age_group = '12';
		$age_group_name = '55 - 60 years';
	} elsif ($header >= 60 && $header < 65) {
		$age_group = '13';
		$age_group_name = '60 - 64 years';
	} elsif ($header >= 65 && $header < 70) {
		$age_group = '14';
		$age_group_name = '65 - 69 years';
	} elsif ($header >= 70 && $header < 75) {
		$age_group = '15';
		$age_group_name = '70 - 74 years';
	} elsif ($header >= 75 && $header < 80) {
		$age_group = '16';
		$age_group_name = '75 - 79 years';
	} elsif ($header >= 80 && $header < 85) {
		$age_group = '17';
		$age_group_name = '80 - 84 years';
	} elsif ($header >= 85 && $header < 90) {
		$age_group = '18';
		$age_group_name = '85 - 89 years';
	} elsif ($header >= 90) {
		$age_group = '19';
		$age_group_name = '90+ years old'
	} else {
		die "header : $header";
	}
	$age_groups{$age_group} = $age_group_name;
	return ($age_group, $age_group_name);
}