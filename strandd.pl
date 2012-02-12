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

our $opt = Getopt::Declare->new(q'[strict]
	Database connection parameters (required)

	--db <DBNAME>			Specify DB name (used to find field names & types)
							[required]

	--user <DBUSER>			DB username
							[required]

	--pass <DBPASS>			DB pass
							[required]


	Field control options

	--columns <COLSPEC>		Add extra (or override) columns
							These are comma-separated fields in the format  NAME[:TYPE:LENGTH]
							E.G Created:Datetime,Content:HtmlText,Name:Text:30
							Length is in chars, or is INT length otherwise (latter not impl.)
							Column Type is one of:
								Num - Int
								HtmlText - Lorem ipsum with <p> tags
								Text - Lorem ipsum with \n
								Phrase - Words from /etc/dictionaries-common/words combined by spaces
								Email - Words from same file, made into email
								Reln -- Random relation ID from DB table.  See also --maptable
								Image -- Random image from File table
								Datetime
								Date
								Timestamp
								Enum -- Random option from Enum def.  This requires the field to be defined in the table..

	--exclude <COLSPEC>		Skip these columns from the output

	--include <COLSPEC>		Only include these columns in the output

	--maptable <TMAP>		Map relation to table. form is  FieldName:DBTable  eg  Author:Member, or Page:SiteTree


	Miscellaneous options

	--dir <DIR>				Specify out-dir

	--verbose				The usual!  Output to STDERR

	REQUIRED VALUES

	<CLASS>					Specify class to create (default Page)
							[required]

	<NUM>					How many objects to create.
							[required]

');

croak unless $opt;

# Connect to DB
our $mydb = DBI->connect("DBI:mysql:host=localhost;database=$opt->{'--db'}",
		$opt->{'--user'}, $opt->{'--pass'},
		{RaiseError=>0, PrintError=>1}
	) or croak;

our $class = $opt->{'<CLASS>'};
our $fieldDef = $mydb->selectall_hashref(qq{ DESC $class }, 'Field');

our $out = {
	$class => []
};

our $VERBOSE = $opt->{'--verbose'};

=pod

Sort out columns which we will output

=cut

my %kDefined = map { $_ => 1 } keys %$fieldDef;

if ($opt->{'--columns'}) {
	my @col = split(',', $opt->{'--columns'});
	for my $c (@col) {
		my ($cn, $ct, $len) = split(':', $c);
		$fieldDef->{$cn} ||= {};
		if ($ct) {
			$fieldDef->{$cn}->{'UserType'} = $ct;
		}
		if ($len) {
			$fieldDef->{$cn}->{'UserLen'} = $len;
		}
		$kDefined{$cn} = 1;
	}
}
delete $kDefined{ID};
my @keys = sort keys %kDefined;

if ($opt->{'--include'}) {
	my %col = map { $_ => 1 } split(',', $opt->{'--include'});
	@keys = grep { $col{$_} } @keys;
}
if ($opt->{'--exclude'}) {
	my %col = map { $_ => 1 } split(',', $opt->{'--exclude'});
	@keys = grep { !$col{$_} } @keys;
}

if ($opt->{'--maptable'}) {
	my @col = split(',', $opt->{'--maptable'});
	for my $c (@col) {
		my ($fld, $type) = split(':', $c);
		$relMap{$fld} = $type;
	}
}

print STDERR Dumper(\$fieldDef) if $VERBOSE;
print STDERR Dumper(\@keys) if $VERBOSE;

for(my $i=0; $i < $opt->{'<NUM>'}; $i++) {
	my $obj = {};
FIELD: for my $field (@keys) {
		my $func = 'rand' . fieldType($fieldDef, $field);
		printf STDERR ("[%20s] (%s)\n", $field, $func) if $VERBOSE;
		my $val = eval { &$func($field, fieldLen($fieldDef, $field)) };
		$obj->{$field} = $val;
	}
	push @{$out->{$class}}, $obj;
}

print Dump($out);
$mydb->disconnect();

#print "Done.\n";

sub fieldType {
	my ($fieldDef, $fld) = @_;
	if ($fieldDef->{$fld}) {
		if ($fieldDef->{$fld}->{UserType}) {
			return $fieldDef->{$fld}->{UserType};
		}
		# Spec cases.
		for($fld) {
			/^Content$/ && do { return 'HtmlText' };
			/^Email$/ && do { return 'Email' };
			/^Title$/ && do { return 'Phrase' };
			/Name/i && do { return 'Name'; };
			/Image.*ID$/ && do { return 'Image'; };
			/ID$/ && do { return 'Reln'; };
		}

		unless ($fieldDef->{$fld}->{Type}) {
			return 'Text';
		}

		for($fieldDef->{$fld}->{Type}) {
			/^enum/ && do { return 'Enum'; };
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
	my ($fieldDef, $fld) = @_;
	if ($fieldDef->{$fld}->{UserLen}) {
		return $fieldDef->{$fld}->{UserLen};
	}
	for($fld) { # Special cases
		/^Title$/ && do { return 30; };
		/^MenuTitle$/ && do { return 30; };
		/^URLSegment$/ && do { return 16; };
	}
	unless($fieldDef->{$fld} && $fieldDef->{$fld}->{Type}) {
		return 512;
	}
	if ($fieldDef->{$fld}->{Type} =~ /^\w+\((\d+)\)/) {
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


our @words;

sub getWords {
	our @words;
	unless(@words) {
		open (my $fh, '<', '/etc/dictionaries-common/words')
			or croak $!;
		local $/;
		@words = split("\n", <$fh>);
		close $fh;
	}
	return $words[int(rand(@words))];
}

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

sub randName {
	my ($fld, $chars, $words) = @_;
	$chars ||= 30;
	$words ||= $chars / 5;
	my $text = '';
	for(my $i=0; length($text) < $chars && $i < $words; $i++) {
		$text .= ' ' . ucfirst(getWords());
	}
	$text =~ s/[^\w\s]//g;
	$text =~ s/^\s+|\s+$//;
	return $text;
}

sub randPhrase {
	my ($fld, $chars) = @_;
	$chars ||= 30;
	my $text = '';
	for(my $i=0; length($text) < $chars; $i++) {
		$text .= ' ' . getWords();
	}
	$text =~ s/^\s+|\s+$//;
	return ucfirst $text;
}

sub randEmail {
	my ($fld, $chars) = @_;
	$chars ||= 30;
	my $text = getWords();
	$text .= '@' . getWords() . '.com';
	$text =~ s/[^\w@.]//g;
	$text = lc $text;
	return $text;
}

sub randReln {
	my ($fld) = @_;
	our $mydb;
	my $table = $fld;
	$table =~ s/ID$//;
	if ($relMap{$table}) {
		$table = $relMap{$table};
	}
	eval {
		my $tblDef = $mydb->selectall_hashref(qq{ DESC $table }, 'Field');
		return unless $tblDef;
		my $img = $mydb->selectrow_hashref(qq{ SELECT ID FROM $table ORDER BY RAND() LIMIT 1 });
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


sub randEnum {
	my ($fld) = @_;
	our $fieldDef;
	if ($fieldDef->{$fld}->{Type} && 
		$fieldDef->{$fld}->{Type} =~ /^enum/) {

		my $endef = $fieldDef->{$fld}->{Type};
		$endef =~ s/^enum\(|\)$//;
		@$endef = map { $_ =~ s/'//g; return $_; } split(/,/, $endef);
		return $endef->[int(rand(@$endef))];
	}
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
