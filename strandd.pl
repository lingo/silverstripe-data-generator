#!/usr/bin/perl

=pod SUMMARY

Generate random data for a SilverStripe site.
Use --help for more information

Example:

  strandd.pl Page 10 --inherit SiteTree --include Title:Title:20,Content,Created

=pod AUTHOR

Luke Hudson <lukeletters@gmail.com>

=cut

use warnings;
use strict;
no strict 'refs';
use Data::Dumper;
use Carp;

use Date::Manip;
use YAML::Tiny;
use Getopt::Declare;
use DBI;

use File::Basename qw/dirname/;

our $opt = Getopt::Declare->new(q'

	Database connection parameters (required)
	=========================================

	--db <DBNAME>			Specify DB name (used to find field names & types)

	--user <DBUSER>			DB username

	--pass <DBPASS>			DB pass

	If these are not provided, the program will look for a file \'db.cfg\' in
	the current dir, which should contain something like the following:

		user = USERNAME
		pass = PASSWORD
		db = DBNAME

	Field control options
	=====================

	--columns <COLSPEC>		Add extra (or override) columns
							These are comma-separated fields in the format  NAME[:TYPE:LENGTH]
							E.G Created:Datetime,Content:HtmlText,Name:Text:30
							Length is in chars, or is INT length otherwise (latter not impl.)
							Column Type is one of:
								Static - (Length is used for fixed content)
								Num - Int
								HtmlText - Lorem ipsum with <p> tags
								Text - Lorem ipsum with \n
								Title - Words from /etc/dictionaries-common/words combined by spaces
								Email - Words from same file, made into email
								Reln -- Random relation ID from DB table.  See also --maptable
								Image -- Random image from File table
								Datetime
								Date
								Timestamp
								Enum -- Random option from Enum def.  This requires the field to be defined in the table..
	-c <COLSPEC>			[ditto]

	--exclude <COLSPEC>		Skip these columns from the output
	-x <COLSPEC>			[ditto]

	--include <COLSPEC>		Only include these columns in the output
	-i <COLSPEC>			[ditto]

	--maptable <TMAP>		Map relation to table. form is  FieldName:DBTable  eg  AuthorID:Member, or PageID:SiteTree

	--many <COLSPEC>		Which columns are has_many or many_many.  Format is  COLNAME:MAXREL
							E.g.  --many Tags:5 will create up to 5 tag relations.


	--relfilter <FILTERS>	Format: Field:SQLWHERE, used to filter source rows in randReln.
							E.g.  --relfilter Image:"File.Path LIKE \'%/avatars/%\'

	--imgdir <DIR>			Special case of --relfilter for random Images.  Allows you to limit random images to those coming from DIR.
							E.g.  --imgdir AvatarID:avatars  would map to images within  <sstr_dir>/assets/avatars/

	--inherit <TABLE>		Inherit fields from TABLE

	Miscellaneous options
	=====================

	--dir <DIR>				Specify out-dir

	--verbose				The usual!  Output to STDERR
	--debug					Output SQL debuginfo

	REQUIRED VALUES
	===============

	<CLASS>					Specify class to create (default Page)
							[required]

	<NUM>					How many objects to create.
							[required]

');
croak unless $opt;

$opt->{'--include'} ||= $opt->{'-i'};
$opt->{'--exclude'} ||= $opt->{'-x'};
$opt->{'--columns'} ||= $opt->{'-c'};

our %typeMap = ();
our %relMap = (); # For randReln and --maptype
our %filters = (); # see --relfilter
our %manyMap = (); # for --many
our @keys;

findDBParams(); # Look for stored DB params

# Connect to DB
our $mydb = DBI->connect("DBI:mysql:host=localhost;database=$opt->{'--db'}",
		$opt->{'--user'}, $opt->{'--pass'},
		{RaiseError=>0, PrintError=>1
		}
	) or croak;

if ($opt->{'--debug'}) {
	$mydb->{TraceLevel} = '0|SQL';
}

our $class = $opt->{'<CLASS>'};
our $fieldDef = $mydb->selectall_hashref(qq{ DESC `$class` }, 'Field');
if ($opt->{'--inherit'}) {
	my $table = $opt->{'--inherit'};
	my $parDef = $mydb->selectall_hashref(qq{ DESC `$table` }, 'Field');
	for (keys %$parDef) {
		$fieldDef->{$_} ||= $parDef->{$_};
	}
}

our $out = {
	$class => []
};

our $VERBOSE = $opt->{'--verbose'};

=pod

Sort out columns which we will output

=cut

my %kDefined = map { $_ => 1 } keys %$fieldDef;

sub findDBParams {
	our $opt;
	use Config::Simple;
	my %db;

	if ( -f 'db.cfg' ) {
		Config::Simple->import_from('db.cfg', \%db);
		for (keys %db) {
			s/^default\.// for (my $okey = $_);
			$opt->{"--$okey"} = $db{$_};
		}
	}
}

sub addUserColumn {
	my ($col, $type, $len) = @_;
	$fieldDef->{$col} ||= {};
	if ($type) {
		$type = ucfirst lc $type;
		$fieldDef->{$col}->{'UserType'} = $type;
	}
	if ($len) {
		$fieldDef->{$col}->{'UserLen'} = $len;
	}
	$kDefined{$col} = 1;
	our @keys = sort keys %kDefined;
}


if ($opt->{'--columns'}) {
	my @col = split(',', $opt->{'--columns'});
	for my $c (@col) {
		my ($cn, $ct, $len) = split(':', $c);
		addUserColumn($cn, $ct, $len);
	}
}

if ($opt->{'--maptable'}) {
	%relMap = map { my ($fld, $type) = split(':',$_); $fld => ($type||'Text'); } split(',', $opt->{'--maptable'});
}

if ($opt->{'--many'}) {
	%manyMap = map { my ($c,$n) = split(':',$_); $c => ($n||1); } split(',', $opt->{'--many'});
	for (keys %manyMap) {
		my $pl = $_;
		$pl =~ s/ies$/y/;
		$pl =~ s/es$//;
		$pl =~ s/s$//;
		$relMap{$_} = $pl;
	}
	$kDefined{$_} = 1 for keys %manyMap;
	if ($opt->{'--include'}) {
		$opt->{'--include'} .= ",$_" for keys %manyMap;
	}
	print STDERR "# Many_many map:\n", Dumper(\%manyMap) if $VERBOSE;
}

print STDERR "# FieldType->Table map:\n", Dumper(\%relMap) if $VERBOSE;

delete $kDefined{ID};
@keys = sort keys %kDefined;

if ($opt->{'--include'}) {
	my %col = map { $_ => 1 } split(',', $opt->{'--include'});
	@keys = grep { $col{$_} } @keys;
}
if ($opt->{'--exclude'}) {
	my %col = map { $_ => 1 } split(',', $opt->{'--exclude'});
	@keys = grep { !$col{$_} } @keys;
}


if ($opt->{'--relfilter'}) {
	%filters = map { my ($fld,$filt);
		/^\s*([^:]+):(.+)\s*$/ && do {
			($fld, $filt) = ($1,$2);
		};
		$fld => $filt || '';
	} split(',', $opt->{'--relfilter'});
	print STDERR "# Rel Filters:\n", Dumper(\%filters) if $VERBOSE;
}

if ($opt->{'--imgdir'}) {
	my %dirs = map { my ($f,$d) = split(':', $_); $f => $d; } split(',', $opt->{'--imgdir'});
	for (keys %dirs) {
		my $sql = '';
		if ($filters{$_}) {
			$sql = $filters{$_} . ' AND ';
		}
		$sql .= "Filename LIKE '%/$dirs{$_}/%'";
		$filters{$_} = $sql;
	}
}

print STDERR "# Field defs:\n", Dumper(\$fieldDef) if $VERBOSE;
print STDERR "# Fields to output:\n", Dumper(\@keys) if $VERBOSE;

print STDERR "# Setting values:\n" if $VERBOSE;

$typeMap{$_} = fieldType($fieldDef, $_) for @keys;

for(my $i=0; $i < $opt->{'<NUM>'}; $i++) {
	my $obj = {};
FIELD: for my $field (@keys) {
		my $func = 'rand' . $typeMap{$field};
		if (!defined(&$func)) {
			$func = 'randReln';
			$relMap{$field} = $typeMap{$field};
		}
		my $val;
		printf STDERR ("[%20s] (%s) %s\n", $field, $func, $manyMap{$field} ? '**' : '') if $VERBOSE;
		if ($manyMap{$field}) {
			my @rels = ();
			my $fieldLen = fieldLen($fieldDef, $field);
			for(my $j=0; $j < $manyMap{$field}; $j++) {
				my $val = eval { &$func($field, $fieldLen) };
				push @rels, $val if $val;
			}
			$obj->{$field} = join(',', @rels);
			print "# Type map:\n",Dumper(\%typeMap) if $VERBOSE;
		} else {
			$val = eval { &$func($field, fieldLen($fieldDef, $field)) };
			$obj->{$field} = $val;
		}
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
			print STDERR "Using user-defined type |", $fieldDef->{$fld}->{UserType}, "| for field $fld\n" if $VERBOSE;
			return $fieldDef->{$fld}->{UserType};
		}
		# Spec cases.
		for($fld) {
			/^Content$/ && do { return 'Htmltext' };
			/^Email$/ && do { return 'Email' };
			/^Title$/ && do { return 'Title' };
			/Name$/i && do { return 'Name'; };
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
	our $manyMap;
	if ($manyMap{$fld}) {
		return 'Reln';
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
	my @sentences = split(/\.\s+/, $lorem);
	my $idx = int(rand((scalar @sentences)/2));
	my $text = '';
	my ($tlen, $llen, $line) = (0,0);
	while($tlen < $len && $idx < scalar @sentences) {
		$line = $sentences[$idx];
		$llen = length($line);
		$line .= '.';
		if ($tlen + $llen < $len) {
			if ($breaks && (rand() < 0.3)) {
				$text .= ($html ? '</p><p>' : "\n\n");
			}
			$text .= ucfirst($line);
			$tlen = length($text);
		}
		++$idx;
	}
	return ($html) ? '<p>' . $text . '</p>' : $text;
}


our @words;

sub getWords {
	my ($file) = @_;
	$file ||= '/etc/dictionaries-common/words';
	our @words;
	unless(@words) {
		open (my $fh, '<', $file)
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

sub randHtmltext {
	my ($fld, $len) = @_;
	return ipsum($len, $len > 300, 1);
}

sub randText {
	my ($fld, $len, $html) = @_;
	return ipsum($len, $len > 300, $html);
}

sub randName {
	my ($fld, $chars, $words) = @_;
	$chars ||= 20;
	$words ||= $chars / 5;
	my $text = '';
	my $shortWordsFile = dirname($0) . '/names.txt';
	my $len = 0;
	my ($word, $wl);
	for(my $i=0; $len < $chars && $i < $words; $i++) {
		$word = ucfirst(getWords($shortWordsFile));
		$wl = length($word);
		$text .= ' ' . $word if $len+$wl < $chars;
		$len += $wl + 1;
	}
	$text =~ s/[^\w\s]//g;
	$text =~ s/^\s+|\s+$//;
	return $text;
}

sub randTitle {
	my ($fld, $chars) = @_;
	$chars ||= 30;
	my $text = '';
	my ($len, $word, $wl) = (0);
	for(my $i=0; $len < $chars; $i++) {
		$word = getWords();
		$wl = length($word);
		$text .= ' ' . $word if $wl + $len < $chars;
		$len += $wl + 1;
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
	if ($relMap{$fld}) {
		$table = $relMap{$fld};
	}
	eval {
		my $tblDef = $mydb->selectall_hashref(qq{ DESC `$table` }, 'Field');
		return unless $tblDef;
		my $where = $filters{$fld} || '';
		$where = 'WHERE ' . $where if $where;
		my $img = $mydb->selectrow_hashref(qq{ SELECT ID FROM `$table` $where ORDER BY RAND() LIMIT 1 });
		return $img->{ID};
	}
}

sub randImage {
	our $mydb;
	my ($fld) = @_;
	my $where = $filters{$fld} || '';
	$where = ' AND ' . $where if $where;
	my $img = $mydb->selectrow_hashref(qq{ SELECT ID FROM \`File\` WHERE ClassName='Image' $where ORDER BY RAND() LIMIT 1 });
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

sub randStatic {
	# Not really  random!
	my ($fld) = @_;
	my $val = fieldLen($fieldDef, $fld);
	return $val;
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
