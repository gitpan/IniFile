package IniFile;

=head1 NAME

IniFile - Perl interface to MS-Windows style and Unreal style .ini files

=cut

# Copyright (C) 2000 Avatar <avatar@deva.net>.  All rights reserved.
# This program is free software;  you can redistribute it and/or modify
# it under under the same terms as Perl itself.  There is NO warranty;
# not even for MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.

=head1 SYNOPSIS

    use IniFile;
    $ini = new IniFile('system.ini');

    # MS-Windows style
    print $ini->get(['system', 'path']);
    $oldpath = $ini->put(['system', 'path', 'C:\\windows']);
    if ($ini->exists(['system', 'path'])) ...
    $ini->delete(['system', 'path']);

    # Unreal style (multi-valued keys)
    $ini = new IniFile('UnrealTournament.ini');
    print map "$_\n", $ini->get(['Engine.GameEngine', 'ServerPackages']);
    $ini->put(['Engine.GameEngine', 'ServerPackages', 'New Mod'], -add => 1);
    if ($ini->exists(['Engine.GameEngine', 'ServerPackages', 'Old Mod'])) ...
    $ini->delete(['Engine.GameEngine', 'ServerPackages', 'Some Mod']);

    $ini->save;

=head1 DESCRIPTION

This package provides easy access to the familiar MS-Windows style .ini
files as well as the Unreal style extended .ini files, where multiple
values can be associated with a single key.

For an .ini file to be recognized it must be of the following format:

    [section]
    key=value           ; comments

Sections must be separated from each other by an empty line (i.e. a
newline on its own).  In our implementation the key must be no longer
than 1024 characters, and contain no high-ASCII nor control character.

On a line, everything after the semicolon is ignored.  Spaces
surrounding the delimiting equation sign are stripped.  If there are
more than one equation sign on a line the first one is treated as the
delimiter, the rest of them are considered part of the value.

Specifcations of section, key and value are to be supplied to methods
via an array reference containing just a section name, or the section
name plus a key name, or the section name plus a key name with its
associated value.

=head1 METHODS

=over 4

=cut

use Tie::IxHash;
use strict;
use vars qw($VERSION @ISA @EXPORT @EXPORT_OK);

require Exporter;
require AutoLoader;

@ISA = qw(Exporter AutoLoader);
# Items to export into callers namespace by default. Note: do not export
# names by default without a very good reason. Use EXPORT_OK instead.
# Do not simply export all your public functions/methods/constants.
@EXPORT = qw(
    
);
@EXPORT_OK = qw(
    adjustfilecase
    adjustpathcase
);
$VERSION = '1.01';


# Preloaded methods go here.

# Autoload methods go after =cut, and are processed by the autosplit program.

# ----------------------------------------------------------------

=item B<new([filename])>

Constructor.  If a filename is supplied it will be opened as an .ini
file with its content read as the initial configuration of the object.

=cut

sub new {
    my ($class, $file, %args) = @_;

    my $self = bless {}, $class;

    # Use an indexed hash to preserve the order.
    tie %{ $self->{sections} }, 'Tie::IxHash';

    if (defined $file) {
	$self->{file} = $file;
	$self->open($file, -umod => $args{-umod}) or return undef;
    }

    return $self;
}

# ----------------------------------------------------------------

=item B<open(self[, filename])>

Open the .ini file and read in all valid entries.  New entries will be
merged with the existing configuration.

=cut

sub open {
    my ($self, $file, %args) = @_;

    if (defined $file) {
	$self->{file} = $file;
    } else {
	$file = $self->{file};
    }

    # No need to do anything if this is a new file.
    return 1 if (!-e $file);

    open INIFILE, "<$file" or return 0;

    $self->{lastpos} = 0;
    my $section;
    my $section_terminated = 1;
    my $setup_seen;
    while (<INIFILE>) {
	s/\r*\n$//;

	if (m/^\[([^\]]+)\]\s*$/) {
	    if ($section_terminated) {
	        undef $section_terminated;

		$section = $1;
		tie %{ $self->{sections}->{$section} }, 'Tie::IxHash'
		    if (!defined $self->{sections}->{$section});

		if ($args{-umod}) {
		    if ($setup_seen and !defined $self->{end_of_manifest_int}
			and !grep { $_ eq $section }
			@{ $self->{sections}->{Setup}->{Group} }
			and !grep { $_ eq $section }
			@{ $self->{sections}->{Setup}->{Requires} }) {

			$self->{end_of_manifest_ini} = $self->{lastpos};

			my ($intsize) = grep /Manifest.int/i,
			    @{ $self->{sections}->{SetupGroup}->{Copy} };
			($intsize) = ($intsize =~ m/Size=(\d*)/);
			$self->{end_of_manifest_int} = $self->{lastpos}
			    + $intsize;
		    }

		    $setup_seen = 1 if ($section eq 'Setup');
		}

		next;
	    } else {
		# Empty line not present before the section heading.
		last;
	    }
	}

	next if (!defined $section);

	# An empty line properly terminates a section.
	if (m/^\s*$/) {
	    $section_terminated = 1;

	    # Update last valid read position.
	    $self->{lastpos} = tell INIFILE if tell INIFILE > $self->{lastpos};

	    next;
	}

	# Strip comments.
	s/;.*//;
	next unless length;

	# Strip spaces around first equation sign.
	s/\s*=\s*/=/;

	# Backslashes are allowed only in value part according to the MS-Windows
	# API;  but we'll allow them anyway.
	# Only non-control-character low-ASCII characters are disallowed in the
	# key part in our implementation.
	my ($key, $value) = (
	    m/^([\w !"#$%&'()*+,-.\/:;<>?@\[\]^`{|}~\\]{1,1024})=(.*)$/);

	last if (!defined $key);

	# To allow for multi-valued keys, values are pushed into an array.
	push @{ $self->{sections}->{$section}->{$key} }, $value;

	# Update last valid read position.
	$self->{lastpos} = tell INIFILE if tell INIFILE > $self->{lastpos};
    }

    close INIFILE;

    return 1;
}

# ----------------------------------------------------------------

=item B<save(self[, filename])>

Save the current configuration into file in the .ini format.  Both
the section order and the order of key=value pairs within a section
are preserved.  If a filename is given the file will be used as the save
target, otherwise the configuration will be save to the last used (via
B<new>, B<open> or B<save>) file.  The original content of the file will
be clobbered.  Be careful not to inadvertently merge two .ini files into
one by opening them in turn and then saving.

True will be returned if the save is successful, false otherwise.

=cut

sub save {
    my ($self, $file) = @_;

    if (defined $file) {
	$self->{file} = $file;
    } else {
	$file = $self->{file};
    }

    CORE::open INIFILE, ">$file" or return 0;

    foreach my $section (keys %{ $self->{sections} }) {
	print INIFILE "[$section]\n";
	my %hash = %{ $self->{sections}->{$section} };
	foreach my $key (keys %{ $self->{sections}->{$section} }) {
	    print INIFILE map "$key=$_\n", @{ $hash{$key} };
	}
	print INIFILE "\n";
    }

    close INIFILE or return 0;

    return 1;
}

# ----------------------------------------------------------------

=item B<file(self[, filename] )>

Set or retrieve the filename that was last used.  B<new>, B<open> and
B<save> will all update the last used filename if a filename was
supplied to them.

=cut

sub file {
    my ($self, $file) = shift;

    if (defined $file) {
	$self->{file} = $file;
    }

    return $self->{file};
}

# ----------------------------------------------------------------

=item B<lastpos(self)>

Set or retrieve the the byte offset into the file immediately after
the last line that conforms to the .ini format.

=cut

sub lastpos {
    my ($self, $lastpos) = shift;

    if (defined $lastpos) {
	$self->{lastpos} = $lastpos;
    }

    return $self->{lastpos};
}

# ----------------------------------------------------------------

=item B<exists(self, [ section[, key[, value]] ])>

Return true if the specified section exists, or if the specified key
exists in the specified section.  If a value is specified, return true
if it is any one of the values of the key.

=cut

sub exists {
    my ($self, $path) = @_;

    my ($section, $key, $value) = @$path;

    # Invalid section.
    return 0 if (!defined $section or $section eq '');

    # Only section given.
    return exists $self->{sections}->{$section}
	if (!defined $key or $key eq '');

    # Only section and key given.
    return exists $self->{sections}->{$section}->{$key}
	if (!defined $value or $value eq '');

    # Section, key and value all given.  Any matching value will do.
    return grep { $_ eq $value } @{ $self->{sections}->{$section}->{$key} };
}

# ----------------------------------------------------------------

=item B<get(self, [ section[, key[, value]] ][, -mapping => ('single'|'multiple'))>

Depending on how many elements are specified in the array reference,
retrieve the entire specified section or the values of the specified
key.

If nothing is specified the entire file is returned as a hash
reference.

If only a section name is specified the matching section is returned in
its entirety as a hash reference.

If both a section name and a key name are specified, the associated
values are returned.  If the key has multiple values the returned
result is an array reference containing all the values, otherwise if the
key has only one value that single value is returned as a scalar.

The decision of whether to return a single or multiple values can be
forced via the B<-mapping> argument.  If the multiple mapping option is
applied to a single value result an array of one element that is the
single value will be returned.  If on the other hand the single mapping
option is forced upon a mutli-valued result only the first value will
be returned.

In general, don't specify any mapping when dealing with standard
MS-Windows style .ini files and use the multiple mapping when dealing
with multivalued keys in an Unreal style .ini files.

=cut

sub get {
    my ($self, $path, %args) = @_;

    return $self->{sections} if (!defined $path);

    if ($self->exists($path)) {
	my ($section, $key, $value) = @$path;

	# It doesn't make sense to call get if the value is already
	# available, but we'll try to do something meaningful.
	return $self->exists($path) if (defined $value);

	# Return the entire section if that is the only thing
	# specified.
	return $self->{sections}->{$section} if (!defined $key);

	# Return the associated value/values.
	my @value = @{ $self->{sections}->{$section}->{$key} };

	if ($args{-mapping} eq 'single'
	    or ($#value == 0 and $args{-mapping} ne 'multiple')) {
	    # The key is singly-valued, return the only value.
	    return $value[0];
	} else {
	    # The key is multi-valued, return all of them in an array.
	    return @value;
	}
    } else {
	return undef;
    }
}

# ----------------------------------------------------------------

=item B<put(self, [ section[, key[, value]] ][, -add => boolean])>

Set the value for the specified key in the specified section and return
the old value.  If the optional B<-add> argument is true a new value
will be added to the key if that value does not already exist.

=cut

sub put {
    my ($self, $path, %args) = @_;

    my ($section, $key, $value) = @$path;

    tie %{ $self->{sections}->{$section} }, 'Tie::IxHash'
	if (!defined $self->{sections}->{$section});

    if ($args{-add}) {
	push @{ $self->{sections}->{$section}->{$key} }, $value
	    if (!$self->exists($path));
    } else {
	return splice @{ $self->{sections}->{$section}->{$key} }, 0, 1, $value;
    }
}

# ----------------------------------------------------------------

=item B<delete(self, [ section[, key[, value]] ][, -keep => boolean])>

If section, key and value are all given the corresponding key=value pair
will be deleted from the specified section.  If a specific value is not
given the entire key including all its values will be deleted.  If the
path only specifies a section the entire section will be deleted.

If the optional B<-keep> argument evaluates to true, when performing
section deletion all the keys along with their values are deleted but
the now empty section will still exist to mimic the bahavior of the
Unreal uninstaller.

=cut

sub delete {
    my ($self, $path, %args) = @_;

    return 0 if (!$self->exists($path));

    my ($section, $key, $value) = @$path;

    # Only section given.  Delete whole section.
    if (!defined $key) {
	if ($args{-keep}) {
	    $self->{sections}->{$section} = {};
	} else {
	    delete $self->{sections}->{$section};
	}
	return 1;
    }

    # Only section and key given.  Delete whole key.
    if (!defined $value) {
	delete  $self->{sections}->{$section}->{$key};
	return 1;
    }

    # Section, key and value all given.  Delete matching key=value pair.
    my @newkey =
	grep { $_ ne $value } @{ $self->{sections}->{$section}->{$key} };
    @{ $self->{sections}->{$section}->{$key} } = @newkey;
}

# ----------------------------------------------------------------

=item B<adjustfilecase(filename[, dirname])>

Return the properly cased filename by performing a case-insensitive
match of the specified file within the specified parent directory.  If
there is no match the filename passed in is return as-is.  If the
dirname argument is not given the current directory will be used.

=cut

sub adjustfilecase {
    my ($file) = shift;
    my ($dir) = shift || '.';

    # Win32 is too dumb to handle case-sensitive filenames anyway.
    return $file if ($^O eq 'MSWin32');

    opendir DIR, $dir or return $file;

    my $fileEscaped = $file;
    $fileEscaped =~ s#\[#\\\[#g;
    $fileEscaped =~ s#\]#\\\]#g;
    my @matches = grep { /^$fileEscaped$/i } readdir DIR;
    closedir DIR;

    # Return first match.
    return $matches[0] if ($matches[0]);

    # No match, just return the original filename.
    return $file;
}

# ----------------------------------------------------------------

=item B<adjustpathcase(pathname)>

Return the properly cased and slashed pathname, unless running on a
brain-damaged OS that is too dumb to handle pathnames in a modern,
case-sensitive manner.  Each path components are inspected from left to
right to see if a file or directory of the same name, in any case
combination, already exists.  If any match results the first match is
used, otherwise the original path component is used verbatim.  No
backtracking is performed, so if any path component in the middle fails
to match an existing directory, all subsequent path components are used
as-is.  All backslashes are also changed to forward-slashes.

=cut

sub adjustpathcase {
    my ($path) = @_;

    # Win32 is too dumb to handle case-sensitive pathnames anyway.
    return $path if ($^O eq 'MSWin32');

    $path =~ s#\\#/#g;

    my $dir;
    ($dir, $path) = ($path =~ m#(^/)?(.*)#);
    while ($path =~ m#^([^/]*)/#) {
	$dir .= adjustfilecase($1, $dir).'/';
	$path = $';
    }

    return $dir.adjustfilecase($path, $dir);
}

# ----------------------------------------------------------------

1;
__END__

=back

=head1 AUTHOR

Avatar <F<avatar@deva.net>>, based on a prototype by Mishka Gorodnitzky
<F<misaka@pobox.com>>.

=cut
