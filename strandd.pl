#!/usr/bin/perl
use warnings;
use strict;
no strict 'refs';
use Data::Dumper;
use Carp;

use Date::Manip;
use YAML::Tiny;
use Getopt::Declare;
use DBI;

our %relMap = (); # For randReln and --maptype

sub randNum {
	return int(rand(1024));
}

sub randHtmlText {
	my ($fld, $len) = @_;
	return ipsum($len, $len > 300, 1);
}

sub randText {
	my ($fld, $len, $html) = @_;
	return ipsum($len, $len > 300, $html);
}

sub randReln {
	my ($fld) = @_;
	our $mydb;
	my $tblname = $fld;
	$tblname =~ s/ID$//;
	if ($relMap{$tblname}) {
		$tblname = $relMap{$tblname};
	}
	eval {
		my $img = $mydb->selectrow_hashref(qq{ SELECT ID FROM $tblname ORDER BY RAND() LIMIT 1 });
		return $img->{ID};
	}
}

sub randImage {
	our $mydb;
	my $img = $mydb->selectrow_hashref(q{ SELECT ID FROM File WHERE ClassName='Image' ORDER BY RAND() LIMIT 1 });
	return $img->{ID};
}

sub randDatetime {
	my $nd = int(rand(180)) - 90;
	my $fp = (rand() < 0.5) ? 'ago' : 'future';
	return	UnixDate(ParseDate("$nd days $fp"), '%Y-%m-%d %H:%M:%S');
}
sub randDate {
	my $nd = int(rand(180)) - 90;
	my $fp = (rand() < 0.5) ? 'ago' : 'future';
	return	UnixDate(ParseDate("$nd days $fp"), '%Y-%m-%d');
}
sub randTimestamp {
	my $nd = int(rand(180)) - 90;
	my $fp = (rand() < 0.5) ? 'ago' : 'future';
	return	UnixDate(ParseDate("$nd days $fp"), '%o');
}

our $opt = Getopt::Declare->new(q'[strict]
	--class <CLASS>			Specify class to create (default Page)
							[required]

	--num <NUM>				How many objects to create.
							[required]

	--db <DBNAME>			Specify DB name (used to find field names & types)
	--user <DBUSER>			DB username
	--pass <DBPASS>			DB pass

	--columns <COLSPEC>		Add extra (text for now) columns (these are comma-separated names, with optional :Type eg  Created:Datetime, Content:Text, ...).

	--skipcol <COLSPEC>		Skip these columns from the output

	--maptype <TMAP>		Map types for relations,  form is  FieldName:DBTable  eg  Author:Member

	--dir <DIR>				Specify out-dir
');

croak unless $opt;

our $mydb = DBI->connect("DBI:mysql:host=localhost;database=$opt->{'--db'}",
		$opt->{'--user'}, $opt->{'--pass'},
		{RaiseError=>1, PrintError=>1}
	) or croak;


my $class = $opt->{'--class'};
my $tbl = $mydb->selectall_hashref(qq{ DESC $class }, 'Field');

my $out = {
	$class => []
};

my @keys = sort keys %$tbl;
if ($opt->{'--columns'}) {
	my @col = split(',', $opt->{'--columns'});
	for my $c (@col) {
		my ($cn, $ct, $len) = split(':', $c);
		if ($ct) {
			$tbl->{$cn} = { 'UserType' => $ct };
		}
		if ($len) {
			$tbl->{$cn} = { 'UserLen' => $len };
		}
		push @keys, $cn;
	}
}

if ($opt->{'--skipcol'}) {
	my %col = map { $_ => 1 } split(',', $opt->{'--skipcol'});
	@keys = grep { !$col{$_} } @keys;
}

if ($opt->{'--maptype'}) {
	my @col = split(',', $opt->{'--maptype'});
	for my $c (@col) {
		my ($fld, $type) = split(':', $c);
		$relMap{$fld} = $type;
	}
}

print STDERR Dumper(\$tbl);

for(my $i=0; $i < $opt->{'--num'}; $i++) {
	my $obj = {};
FIELD: for my $f (@keys) {
		if ($f =~ /Image.*ID$/) {
			$obj->{$f} = randImage($f);
			next FIELD;
		} elsif ($f =~ /.+ID$/) {
			$obj->{$f} = randReln($f);
			next FIELD;
		} elsif ($f =~ /ID$/) {
			next FIELD;
		}
		my $fn = 'rand' . fieldType($tbl, $f);
		#print $f, ' ', $fn . "\n";
		my $val = eval { &$fn($f, fieldLen($tbl, $f)) };
		#print " => $val\n";
		$obj->{$f} = $val;
	}
	push @{$out->{$class}}, $obj;
}

print Dump($out);
$mydb->disconnect();

#print "Done.\n";

sub fieldType {
	my ($tbl, $fld) = @_;
	if ($tbl->{$fld}) {
		if ($tbl->{$fld}->{UserType}) {
			return $tbl->{$fld}->{UserType};
		}
		# Spec cases.
		for($fld) {
			/^Content$/ && do { return 'HtmlText' };
		}
		unless ($tbl->{$fld}->{Type}) {
			return 'Text';
		}

		for($tbl->{$fld}->{Type}) {
			/^int/ && do { return 'Num'; };
			/^(varchar|text|mediumtext|char)/ && do { return 'Text'; };
			/^datetime$/ && do { return 'Datetime'; };
			/^date/ && do { return 'Time'; };
			/^timestamp/ && do { return 'Timestamp'; };
		}
	}
	return 'Text';
}

sub fieldLen {
	my ($tbl, $fld) = @_;
	for($fld) { # Special cases
		/^Title$/ && do { return 30; };
		/^MenuTitle$/ && do { return 30; };
		/^URLSegment$/ && do { return 16; };
	}
	if ($tbl->{$fld}->{UserLen}) {
		return $tbl->{$fld}->{UserLen};
	}
	unless($tbl->{$fld} && $tbl->{$fld}->{Type}) {
		return 512;
	}
	if ($tbl->{$fld}->{Type} =~ /^\w+\((\d+)\)/) {
		return $1;
	}
	return 1024; # rand
}

sub ipsum {
	my ($len, $breaks, $html) = @_;
	$html ||= 0;
	$breaks ||= 1;
	# Load lorem text
	our $lorem;
	unless($lorem) {
		local $/;
		$lorem = <DATA>;
		$lorem =~ s/\n+//g;
	}
	my @sentences = split(/[,.]\s+/, $lorem);
	my $idx = int(rand((scalar @sentences)/2));
	my $text = '';
	while(length($text) < $len && $idx < scalar @sentences) {
		my $line = $sentences[$idx];
		if (length($text) + length($line) < $len) {
			if ($breaks && (rand() < 0.3)) {
				$text .= ($html ? '</p><p>' : "\n\n");
			}
			$text .= ucfirst($line);
		}
		++$idx;
	}
	return ($html) ? '<p>' . $text . '</p>' : $text;
}

__END__
Lorem ipsum dolor sit amet, consectetur adipisicing elit, impedit voluptate
deserunt blanditiis eligendi eos mollit, quis eu excepteur at, aliquam atque
impedit aliquam pariatur accusamus. aliquam dolor occaecat tempor eveniet magna
incidunt dolores tempor quas excepturi. blanditiis magna commodo saepe pariatur
deleniti nihil dolor nostrum tempora nobis pariatur eligendi incididunt minima
labore molestias commodi assumenda. voluptas commodo excepteur asperiores
tempora elit minima repudiandae accusamus, in corporis corrupti, minima
temporibus temporibus cupiditate dolorem quia. hic omnis reprehenderit
adipisicing aliqua iusto aute fuga maxime fugiat necessitatibus officia
obcaecati nihil voluptates. eiusmod, voluptate eius laboris facilis nisi
exercitationem voluptates repellendus et nihil earum.  Molestiae aut nulla
voluptate, dolorum sunt exercitationem. Quos reiciendis laborum, soluta dolore
quia, debitis. Ullamco culpa iusto laboriosam ad vel nihil repudiandae
assumenda nihil ut facilis proident cupiditate animi eveniet quia. Odio duis
minima ad repellendus eveniet excepteur dolor praesentium, repellat similique.
Recusandae mollitia alias alias facere asperiores duis occaecat labore aliquam
pariatur nostrud. Optio dignissimos ex similique iusto pariatur aut eu a,
nostrum do officia excepturi. Duis cupidatat quidem assumenda deleniti
adipisicing ad dolore hic esse quaerat, voluptate.  Dolores molestiae earum
molestiae ut minus soluta pariatur consequatur facere libero eiusmod magna
repellat suscipit cupidatat. Alias, commodo corporis consequatur quas
reiciendis aute. Vel, laboriosam dolor molestias sed impedit nostrum at soluta
nobis corrupti laboris velit.  Ea cumque eum quod aliqua itaque repudiandae
facere deleniti laborum facilis voluptatibus molestiae, aliquip aliquid
blanditiis modi dignissimos. Enim nihil, consectetur laboriosam sed tempor quod
itaque aute, facere odio optio molestias deserunt voluptatibus at. Ullamco
aliqua nihil minus omnis qui repellat illum recusandae. Enim doloribus aliqua
adipisicing omnis.  Minus minim reprehenderit tempore voluptatibus proident
occaecat. Et non voluptas aliquam vel sapiente exercitation fuga. Distinctio
eligendi aut impedit quam aut excepturi incididunt in quis quos minus tempora
nisi consequatur aliquid occaecat excepteur. Anim consectetur, fuga commodo
recusandae maiores temporibus optio.  Quam voluptatem proident cupidatat a,
earum tempore labore commodo debitis sed expedita culpa fugiat excepturi
impedit qui. Odio asperiores sapiente alias illum iure, praesentium incidunt
tempora, aliquip eu repellat, possimus aliqua in perferendis modi optio
suscipit. Possimus voluptas minus in vero rerum. Temporibus corrupti eos
ducimus alias consectetur.  Fugiat temporibus voluptates aute molestiae minus
ex veniam quaerat commodi. Deserunt reiciendis consectetur quos alias autem,
dolore minim dignissimos magnam incidunt maxime mollitia. Nulla quidem, minim,
consequat elit. Odio id minima exercitationem sunt reprehenderit iure magnam eu
atque dolore anim. Provident dignissimos vero asperiores pariatur fuga eveniet
repudiandae nulla cum cum iusto eveniet quam dolore anim occaecat incidunt
modi. Minima officia soluta et repudiandae minima maiores culpa. Ut placeat
molestias praesentium nisi voluptatibus dolorem, corrupti aliqua mollitia elit
facere pariatur repellendus saepe.
