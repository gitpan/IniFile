# Before `make install' is performed this script should be runnable with
# `make test'. After `make install' it should work as `perl test.pl'

######################### We start with some black magic to print on failure.

BEGIN { $| = 1; print "1..15\n"; }
END {print "not ok 1\n" unless $loaded;}
use IniFile;
$loaded = 1;
print "ok 1\n";

######################### End of black magic.

use POSIX qw(tmpnam);
do { $tmpfile = tmpnam() } until open TMPFILE, ">$tmpfile";
print TMPFILE <<EOT;
[Setup]
MasterProduct=UnrealTournament
Group=UnrealTournament
Group=DE Mutators
Group=Pinata
Group=NIUT

[DE Mutators]
File=System\\de.u
File=System\\de.int
File=Help\\demutators-readme.txt
File=System\\de-logo.bmp
Caption=DE Mutators
Version=100
Requires=UnrealTournament

[Pinata]
File=System\\Pinata.int
File=System\\Pinata.u
File=Help\\Pinata_readme.txt
Caption=Pinata
Version=200
Requires=UnrealTournament

[NIUT]
File=Help\\niut.txt
File=System\\NIUT.u
File=System\\Niut.int
File=System\\Niut.ini
Caption=NIUT
Version=121
Requires=UnrealTournament

[Engine.GameEngine]
MasterServerAddress=unreal.epicgames.com MasterServerPort=27900
ServerActors = IpServer.UdpServerUplinkMasterServerAddress=master0.gamespy.com MasterServerPort=27900
ServerActors	=	IpServer.UdpServerUplinkMasterServerAddress=master.mplayer.com MasterServerPort = 27900
EOT
close TMPFILE;

# constructor
$ini = new IniFile($tmpfile);
if (defined $ini) { print "ok 2\n"; }
else { print "not ok 2\n"; }

# existence test
if ($ini->exists(['Setup']) and $ini->exists(['Setup', 'Group'])
	and $ini->exists(['Setup', 'MasterProduct'])
	and $ini->exists(['Setup', 'Group', 'NIUT'])
	and $ini->exists(['Setup', 'MasterProduct', 'UnrealTournament'])
	and $ini->exists(['DE Mutators', 'File', 'System\\de.int'])) {
	print "ok 3\n";
} else { print "not ok 3\n"; }

# nonexistence test
if (!$ini->exists(['NONEXISTENT']) and !$ini->exists(['Setup', 'NONEXISTENT'])
	and !$ini->exists(['Setup', 'Group', 'NONEXISTENT'])
	and !$ini->exists(['Setup', 'MasterProduct', 'NONEXISTENT'])
	and !$ini->exists(['DE Mutators', 'File', 'NONEXISTENT'])) {
	print "ok 4\n";
} else { print "not ok 4\n"; }

# get single value
if ($ini->get(['Setup', 'MasterProduct']) eq 'UnrealTournament') {
	print "ok 5\n";
} else { print "not ok 5\n"; }

# get multiple values
@setupgroup = $ini->get(['Setup', 'Group']);
if ($setupgroup[0] eq 'UnrealTournament'
	and $setupgroup[1] eq 'DE Mutators'
	and $setupgroup[2] eq 'Pinata'
	and $setupgroup[3] eq 'NIUT') {
	print "ok 6\n";
} else { print "not ok 6\n" };

# force get single value
if ($ini->get(['Setup', 'Group'], -mapping => 'single') eq 'UnrealTournament') {
	print "ok 7\n";
} else { print "not ok 7\n"; }

# force get multiple value
@masterproducts = $ini->get(['Setup', 'MasterProduct'], -mapping => 'multiple');
if ($#masterproducts == 0 and $masterproducts[0] eq 'UnrealTournament') {
	print "ok 8\n";
} else { print "not ok 8\n"; }

# get entire section
%setup = %{ $ini->get(['Setup']) };
if ($setup{MasterProduct}[0] eq 'UnrealTournament'
	and $setup{Group}[0] eq 'UnrealTournament'
	and $setup{Group}[1] eq 'DE Mutators'
	and $setup{Group}[2] eq 'Pinata'
	and $setup{Group}[3] eq 'NIUT') {
	print "ok 9\n";
} else { print "not ok 9\n"; }

# get a non-existent key
if (!defined $ini->get(['Setup', 'NONEXISTENT'])) {
	print "ok 10\n";
} else { print "not ok 10\n"; }

# erroneous get calls
if (!defined $ini->get(['', 'MasterProduct'])
	and !defined $ini->get([undef, '', 'NIUT'])
	and !defined $ini->get(['', undef, 'NIUT'])
	and !defined $ini->get([''])) {
	print "ok 11\n";
} else { print "not ok 11\n"; }

# change value
if (($oldver = $ini->put(['DE Mutators', 'Version', '200'])) == 100
	and $ini->get(['DE Mutators', 'Version']) == 200) {
	print "ok 12\n";
} else { print "not ok 12\n"; }

# add value to existing key
$ini->put(['Setup', 'Group', 'NewMutator'], -add => 1);
# add new key
$ini->put(['DE Mutators', 'Old Version', $oldver]);
# add new group and key
$ini->put(['NewMutator', 'Caption', 'The Great New Mutator']);
if ($ini->exists(['Setup', 'Group', 'NewMutator'])
	and $ini->get(['DE Mutators', 'Old Version']) == 100
	and $ini->exists(['NewMutator', 'Caption', 'The Great New Mutator'])) {
	print "ok 13\n";
} else { print "not ok 13\n"; }

# delete one value from a key
$ini->delete(['Setup', 'Group', 'Pinata']);
# delete whole key
$ini->delete(['DE Mutators', 'File']);
# delete whole section
$ini->delete(['Pinata']);
# delete whole section content but keep section
$ini->delete(['NIUT'], -keep => 1);
if (!$ini->exists(['Setup', 'Group', 'Pinata'])
	and !defined $ini->get(['DE Mutators', 'File'])
	and !defined $ini->get(['Pinata'])
	and !%{ $ini->get(['NIUT']) }) {
	print "ok 14\n";
} else { print "not ok 14\n"; }

# save function
$ini->save;
open TMPFILE, "<$tmpfile";
undef $/;
my $wholefile = <TMPFILE>;
$/ = "\n";
close TMPFILE;
my $shouldbe = <<EOT;
[Setup]
MasterProduct=UnrealTournament
Group=UnrealTournament
Group=DE Mutators
Group=NIUT
Group=NewMutator

[DE Mutators]
Caption=DE Mutators
Version=200
Requires=UnrealTournament
Old Version=100

[NIUT]

[Engine.GameEngine]
MasterServerAddress=unreal.epicgames.com MasterServerPort=27900
ServerActors=IpServer.UdpServerUplinkMasterServerAddress=master0.gamespy.com MasterServerPort=27900
ServerActors=IpServer.UdpServerUplinkMasterServerAddress=master.mplayer.com MasterServerPort = 27900

[NewMutator]
Caption=The Great New Mutator

EOT
if ($wholefile eq $shouldbe) {
	print "ok 15\n";
} else { print "not ok 15\n"; }

unlink $tmpfile;
