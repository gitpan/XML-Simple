package XML::Simple;

=head1 NAME

XML::Simple - Trivial API for reading and writing XML (esp config files)

=head1 SYNOPSIS

    use XML::Simple;

    my $ref = XMLin([<xml file or string>] [, <options>]);

    my $xml = XMLout($hashref [, <options>]);

=cut

# See after __END__ for more POD documentation


# Load essentials here, other modules loaded on demand later

use strict;
use Carp;
require Exporter;


##############################################################################
# Define some constants
#

use vars qw($VERSION @ISA @EXPORT);

@ISA               = qw(Exporter);
@EXPORT            = qw(XMLin XMLout);
$VERSION           = '1.04';

my %CacheScheme    = (
                       storable => [ \&StorableSave, \&StorableRestore ],
                       memshare => [ \&MemShareSave, \&MemShareRestore ],
                       memcopy  => [ \&MemCopySave,  \&MemCopyRestore  ]
		     );

my $DefaultValues  = 1;       # Used for locking only
my @KnownOptIn     = qw(keyattr keeproot contentkey
                        searchpath forcearray cache);
my @KnownOptOut    = qw(keyattr keeproot contentkey
                        rootname xmldecl outputfile noescape);
my @DefKeyAttr     = qw(name key id);
my $DefRootName    = qq(opt);
my $DefContentKey  = qq(content);
my $DefXmlDecl     = qq(<?xml version='1' standalone='yes'?>);


##############################################################################
# Globals for use by caching routines (access protected by locks)
#

my %MemShareCache  = ();
my %MemCopyCache   = ();


##############################################################################
# Dummy 'lock' routine for non-threaded versions of Perl
#

BEGIN {
  if($] < 5.005) {
    eval "sub lock {}";
  }
}


##############################################################################
# Constructor for optional object interface.
#

sub new {
  my $class = shift;

  if(@_ % 2) {
    croak "Default options must be name=>value pairs (odd number supplied)";
  }

  my $self = { @_ };

  return(bless($self, $class));
}


##############################################################################
# Sub: XMLin()
#
# Exported routine for slurping XML into a hashref - see pod for info.
#
# May be called as object method or as a plain function.
#
# Expects one arg for the source XML, optionally followed by a number of
# name => value option pairs.
#

sub XMLin {

  # Are we being called as an object method?

  my $DefOpts = undef;
  if($_[0]  and  UNIVERSAL::isa($_[0], 'XML::Simple')) {
    $DefOpts = shift;
  }


  my $String = shift;
  my $Options = HandleOptions($DefOpts, 'in', @_);

  # If no XML or filename supplied, look for scriptname.xml in script directory

  unless(defined($String))  {
    
    # Translate scriptname[.suffix] to scriptname.xml

    require File::Basename;

    my($ScriptName, $ScriptDir, $Extension) =
      File::Basename::fileparse($0, '\.[^\.]+');

    $String = $ScriptName . '.xml';


    # Add script directory to searchpath
    
    if($ScriptDir) {
      unshift(@{$Options->{searchpath}}, $ScriptDir);
    }
  }
  

  # Are we parsing from a file?  If so, is there a valid cache available?

  my($Filename, $Scheme);
  unless($String =~ m{<.*?>}s  ||  ref($String)) {

    require File::Basename;
    require File::Spec;

    $Filename = FindXMLFile($String, @{$Options->{searchpath}});

    if($Options->{cache}) {
      lock(%CacheScheme);
      foreach $Scheme (@{$Options->{cache}}) {
	croak "Unsupported caching scheme: $Scheme"
	  unless($CacheScheme{$Scheme});

	my $opt = $CacheScheme{$Scheme}->[1]->($Filename);
	return($opt) if($opt);
      }
    }
  }


  # Parsing is required, so let's get on with it

  {
    local($^W) = 0;       # Suppress warning from Expat.pm re File::Spec::load()
    require XML::Parser;  # We didn't need it until now
  }

  my $xp = new XML::Parser(Style => 'Tree');
  my($tree, $ref);
  if($Filename) {
    $tree = $xp->parsefile($Filename);
  }
  else {
    $tree = $xp->parse($String);
  }

  
  # Now work some magic on the resulting parse tree

  if($Options->{keeproot}) {
    $ref = Collapse($Options, {}, @$tree);
  }
  else {
    $ref = Collapse($Options, @{$tree->[1]});
  }

  if($Options->{cache}) {
    $CacheScheme{$Options->{cache}->[0]}->[0]->($ref, $Filename);
  }

  return($ref);
}


##############################################################################
# Sub: StorableSave()
#
# Wrapper routine for invoking Storable::nstore() to cache a parsed data
# structure.
#

sub StorableSave {
  my($Data, $Filename) = @_;

  my $CacheFile = $Filename;
  $CacheFile =~ s{(\.xml)?$}{.stor};

  require Storable;           # We didn't need it until now
  
  Storable::nstore($Data, $CacheFile);
  
}


##############################################################################
# Sub: StorableRestore()
#
# Wrapper routine for invoking Storable::retrieve() to read a cached parsed
# data structure.  Only returns cached data if the cache file exists and is
# newer than the source XML file.
#

sub StorableRestore {
  my($Filename) = @_;
  
  my $CacheFile = $Filename;
  $CacheFile =~ s{(\.xml)?$}{.stor};

  return unless(-r $CacheFile);
  return unless((stat($CacheFile))[9] > (stat($Filename))[9]);

  unless($INC{'Storable.pm'}) {
    require Storable;           # We didn't need it until now
  }
  
  return(Storable::retrieve($CacheFile));
  
}


##############################################################################
# Sub: MemShareSave()
#
# Takes the supplied data structure reference and stores it away in a global
# hash structure.
#

sub MemShareSave {
  my($Data, $Filename) = @_;

  lock(%MemShareCache);
  $MemShareCache{$Filename} = [time(), $Data];
}


##############################################################################
# Sub: MemShareRestore()
#
# Takes a filename and looks in a global hash for a cached parsed version.
#

sub MemShareRestore {
  my($Filename) = @_;
  
  lock(%MemShareCache);
  return unless($MemShareCache{$Filename});
  return unless($MemShareCache{$Filename}->[0] > (stat($Filename))[9]);

  return($MemShareCache{$Filename}->[1]);
  
}


##############################################################################
# Sub: MemCopySave()
#
# Takes the supplied data structure and stores a copy of it in a global hash
# structure.
#

sub MemCopySave {
  my($Data, $Filename) = @_;

  lock(%MemCopyCache);
  unless($INC{'Storable.pm'}) {
    require Storable;           # We didn't need it until now
  }
  
  $MemCopyCache{$Filename} = [time(), Storable::dclone($Data)];
}


##############################################################################
# Sub: MemCopyRestore()
#
# Takes a filename and looks in a global hash for a cached parsed version.
# Returns a reference to a copy of that data structure.
#

sub MemCopyRestore {
  my($Filename) = @_;
  
  lock(%MemCopyCache);
  return unless($MemCopyCache{$Filename});
  return unless($MemCopyCache{$Filename}->[0] > (stat($Filename))[9]);

  return(Storable::dclone($MemCopyCache{$Filename}->[1]));
  
}


##############################################################################
# Sub: XMLout()
#
# Exported routine for 'unslurping' a data structure out to XML.
#

sub XMLout {

  # Are we being called as an object method?

  my $DefOpts = undef;
  if (UNIVERSAL::isa($_[0], 'XML::Simple')) {
    $DefOpts = shift;
  }


  my $ref = shift;

  my $Options = HandleOptions($DefOpts, 'out', @_);


  # Wrap top level arrayref in a hash

  if(ref($ref) eq 'ARRAY') {
    $ref = { anon => $ref };
  }


  # Extract rootname from top level hash if keeproot enabled

  if($Options->{keeproot}) {
    my(@keys) = keys(%$ref);
    if(@keys == 1) {
      $ref = $ref->{$keys[0]};
      $Options->{rootname} = $keys[0];
    }
  }
  
  # Ensure there are no top level attributes if we're not adding root elements

  elsif($Options->{rootname} eq '') {
    if(ref($ref) eq 'HASH') {
      my $refsave = $ref;
      $ref = {};
      foreach (keys(%$refsave)) {
	if(ref($refsave->{$_})) {
	  $ref->{$_} = $refsave->{$_};
	}
	else {
	  $ref->{$_} = [ $refsave->{$_} ];
	}
      }
    }
  }


  # Encode the hashref and write to file if necessary

  my $xml = ValueToXML($Options, $ref, $Options->{rootname}, {}, '');
  if($Options->{xmldecl}) {
    $xml = $Options->{xmldecl} . "\n" . $xml;
  }

  if($Options->{outputfile}) {
    if(ref($Options->{outputfile})) {
      return($Options->{outputfile}->print($xml));
    }
    else {
      open(_XML_SIMPLE_OUT_, ">$Options->{outputfile}") ||
        croak "open($Options->{outputfile}): $!";
      print _XML_SIMPLE_OUT_ $xml || croak "print: $!";
      close(_XML_SIMPLE_OUT_);
    }
  }
  else {
    return($xml);
  }
}


##############################################################################
# Sub: HandleOptions()
#
# Helper routine for both XMLin() and XMLout().  Both routines handle their
# first argument and assume all other args are options handled by this routine.
# Returns a reference to a hash of options.
#
# Expects first argument to be hashref of 'default' options from object
# constructor (or undef if not OO mode).
#
# Second argument should be the string 'in' or the string 'out'.
#
# Remaining arguments should be name=>value pairs.  Sets up default values
# for options not supplied.  Unrecognised options are a fatal error.
#

sub HandleOptions  {

  lock($DefaultValues);


  my $DefOpts = shift;

  
  # Determine valid options based on context

  my %KnownOpt; 
  my $Dirn = shift;
  if($Dirn eq 'in') {
    @KnownOpt{@KnownOptIn} = @KnownOptIn;
  }
  else {
    @KnownOpt{@KnownOptOut} = @KnownOptOut;
  }


  # Store supplied options in hashref and weed out invalid ones

  if(@_ % 2) {
    croak "Options must be name=>value pairs (odd number supplied)";
  }
  my $Options = { @_ };

  foreach (keys(%$Options)) {
    croak "Unrecognised option: $_"
      unless($KnownOpt{$_});
  }


  # Merge in values from $DefOpts

  if($DefOpts) {
    foreach (keys(%KnownOpt)) {
      unless(exists($Options->{$_})) {
	if(exists($DefOpts->{$_})) {
	  $Options->{$_} = $DefOpts->{$_};
	}
      }
    }
  }


  # Set sensible defaults if not supplied
  
  if(exists($Options->{rootname})) {
    unless(defined($Options->{rootname})) {
      $Options->{rootname} = '';
    }
  }
  else {
    $Options->{rootname} = $DefRootName;
  }
  
  if($Options->{xmldecl}  and  $Options->{xmldecl} eq '1') {
    $Options->{xmldecl} = $DefXmlDecl;
  }

  unless(exists($Options->{contentkey})) {
    $Options->{contentkey} = $DefContentKey;
  }


  # Cleanups for values assumed to be arrays later

  if($Options->{searchpath}) {
    unless(ref($Options->{searchpath})) {
      $Options->{searchpath} = [ $Options->{searchpath} ];
    }
  }
  else  {
    $Options->{searchpath} = [ ];
  }

  if($Options->{cache}  and !ref($Options->{cache})) {
    $Options->{cache} = [ $Options->{cache} ];
  }
  

  # Special cleanup for {keyattr} which could be arrayref or hashref or left
  # to default to arrayref

  if(exists($Options->{keyattr}))  {
    if(ref($Options->{keyattr})) {
      if(ref($Options->{keyattr}) eq 'HASH') {

	# Make a copy so we can mess with it

	$Options->{keyattr} = { %{$Options->{keyattr}} };

	
	# Convert keyattr => { elem => '+attr' }
	# to keyattr => { elem => [ 'attr', '+' ] } 

	foreach (keys(%{$Options->{keyattr}})) {
	  if($Options->{keyattr}->{$_} =~ /^(\+|-)?(.*)$/) {
	    $Options->{keyattr}->{$_} = [ $2, ($1 ? $1 : '') ];
	  }
	  else {
	    delete($Options->{keyattr}->{$_}); # Never reached
	  }
	}
      }
      else {
	if(@{$Options->{keyattr}} == 0) {
	  delete($Options->{keyattr});
	}
      }
    }
    else {
      $Options->{keyattr} = [ $Options->{keyattr} ];
    }
  }
  else  {
    $Options->{keyattr} = [ @DefKeyAttr ];
  }

  
  # Special cleanup for {forcearray} which could be arrayref or boolean
  # or left to default to 0

  if(exists($Options->{forcearray})) {
    if(ref($Options->{forcearray}) eq 'ARRAY') {
      if(@{$Options->{forcearray}}) {
        $Options->{forcearray} = { (
	  map { $_ => 1 } @{$Options->{forcearray}}
	) };
      }
      else {
        $Options->{forcearray} = 0;
      }
    }
    else {
      $Options->{forcearray} = ( $Options->{forcearray} ? 1 : 0 );
    }
  }
  else {
    $Options->{forcearray} = 0;
  }


  return($Options);
}


##############################################################################
# Sub: FindXMLFile()
#
# Helper routine for XMLin().
# Takes a filename, and a list of directories, attempts to locate the file in
# the directories listed.
# Returns a full pathname on success; croaks on failure.
#

sub FindXMLFile  {
  my $File = shift;
  my @SearchPath = @_;


  my($FileName, $FileDir) =
    File::Basename::fileparse($File);

  if($FileName ne $File) {        # Ignore searchpath if dir component
    return($File) if(-e $File);
  }
  else {
    my($Path);
    foreach $Path (@SearchPath)  {
      my $FullPath = File::Spec->catfile($Path, $File);
      return($FullPath) if(-e $FullPath);
    }
  }

  croak "Could not find $File in ", join(':', @SearchPath);
}


##############################################################################
# Sub: Collapse()
#
# Helper routine for XMLin().  This routine really comprises the 'smarts' (or
# value add) of this module.
#
# Takes the parse tree that XML::Parser produced from the supplied XML and
# recurses through it 'collapsing' unnecessary levels of indirection (nested
# arrays etc) to produce a data structure that is easier to work with.
#
# Elements in the original parser tree are represented as an element name
# followed by an arrayref.  The first element of the array is a hashref
# containing the attributes.  The rest of the array contains ia list of any
# nested elements as name array ref pairs:
#
#  <element name>, [ { <attribute hashref> }, <element name>, [ ... ], ... ]
#
# The special element name '0' (zero) flags text content.
#
# This routine cuts down the noise by discarding any text content consisting of
# only whitespace and then moves the nested elements into the attribute hash
# using the name of the nested element as the hash key and the collapsed
# version of the nested element as the value.  Multiple nested elements with
# the same name will initially be represented as an arrayref, but this may be
# 'folded' into a hashref depending on the value of the keyattr option.
#

sub Collapse {

  my $Options = shift;


  # Start with the hash of attributes
  
  my $attr  = shift;


  # Add any nested elements

  my($key, $val);
  while(@_) {
    $key = shift;
    $val = shift;

    if(ref($val)) {
      $val = Collapse($Options, @$val);
    }
    elsif($key eq '0') {
      next if($val =~ m{^\s*$}s);  # Skip all whitespace content
      if(!%$attr  and  !@_) {      # Short circuit text in tag with no attr
        return($val);
      }
      $key = $Options->{contentkey};
    }


    # Combine duplicate attributes into arrayref if required

    if(exists($attr->{$key})) {
      if(ref($attr->{$key}) eq 'ARRAY') {
        push(@{$attr->{$key}}, $val);
      }
      else {
        $attr->{$key} = [ $attr->{$key}, $val ];
      }
    }
    elsif(ref($val) eq 'ARRAY') {  # Handle anonymous arrays
      $attr->{$key} = [ $val ];
    }
    else {
#      $attr->{$key} = ($Options->{forcearray} ? [ $val ] : $val);
      if(   ($Options->{forcearray} == 1)
         || (   (ref($Options->{forcearray}) eq 'HASH')
	     && ($Options->{forcearray}->{$key})
	    )
	) {
	$attr->{$key} = [ $val ];
      }
      else {
	$attr->{$key} = $val;
      }
    }
  }


  # Turn arrayrefs into hashrefs if key fields present

  my $count = 0;
  if($Options->{keyattr}) {
    while(($key,$val) = each %$attr) {
      if(ref($val) eq 'ARRAY') {
	$attr->{$key} = ArrayToHash($Options, $key, $val);
      }
      $count++;
    }
  }


  # Fold hashes containing a single anonymous array up into just the array

  if($count == 1  and  ref($attr->{anon}) eq 'ARRAY') {
    return($attr->{anon});
  }

  return($attr)
}


##############################################################################
# Sub: ArrayToHash()
#
# Helper routine for Collapse().
# Attempts to 'fold' an array of hashes into an hash of hashes.  Returns a
# reference to the hash on success or the original array if folding is
# not possible.  Behaviour is controlled by 'keyattr' option.
#

sub ArrayToHash {

  my $Options  = shift;
  my $Name     = shift;
  my $ArrayRef = shift;

  my $HashRef  = {};

  my($i, $key, $val, $flag);


  # Handle keyattr => { .... }

  if(ref($Options->{keyattr}) eq 'HASH') {
    return($ArrayRef) unless(exists($Options->{keyattr}->{$Name}));
    ($key, $flag) = @{$Options->{keyattr}->{$Name}};
    for($i = 0; $i < @$ArrayRef; $i++)  {
      return($ArrayRef) unless(exists($ArrayRef->[$i]->{$key}));
      $val = $ArrayRef->[$i]->{$key};
      $HashRef->{$val} = { %{$ArrayRef->[$i]} };
      $HashRef->{$val}->{"-$key"} = $HashRef->{$val}->{$key} if($flag eq '-');
      delete $HashRef->{$val}->{$key} unless($flag eq '+');
    }
  }


  # Or assume keyattr => [ .... ]

  else {
    ELEMENT: for($i = 0; $i < @$ArrayRef; $i++)  {
      return($ArrayRef) unless(ref($ArrayRef->[$i]) eq 'HASH');

      foreach $key (@{$Options->{keyattr}}) {
	if(defined($ArrayRef->[$i]->{$key}))  {
	  $val = $ArrayRef->[$i]->{$key};
	  $HashRef->{$val} = { %{$ArrayRef->[$i]} };
	  delete $HashRef->{$val}->{$key};
	  next ELEMENT;
	}
      }

      return($ArrayRef);    # No keyfield matched
    }
  }

  return($HashRef);
}


##############################################################################
# Sub: ValueToXML()
#
# Helper routine for XMLout() - recurses through a data structure building up
# and returning an XML representation of that structure as a string.
# 
# Arguments expected are:
# - a hashref of option settings (args to XMLin() merged with defaults)
# - the data structure to be encoded (usually a reference)
# - the XML tag name to use for this item
# - a hashref of references already encoded (to detect recursive structures)
# - a string of spaces for use as the current indent level
#

sub ValueToXML {
  my($Options, $ref, $name, $encoded, $indent) = @_;

  my $named = (defined($name) and $name ne '' ? 1 : 0);

  if(ref($ref)) {
    croak "recursive data structures not supported" if($encoded->{$ref});
    $encoded->{$ref} = $ref;
  }
  else {
    if($named) {
      return(join('',
              $indent, '<', $name, '>',
	      ($Options->{noescape} ? $ref : EscapeValue($ref)),
              '</', $name, ">\n"
	    ));
    }
    else {
      return("$ref\n");
    }
  }

  # Unfold hash to array if possible (skip for root elements)

  if(ref($ref) eq 'HASH' and $Options->{keyattr} and $indent) {
    $ref = HashToArray($Options, $name, $ref);
  }

  my @result = ();
  my($key, $value);

  if(ref($ref) eq 'HASH') {
    my @nested = ();
    my $text_content = undef;
    if($named) {
      push @result, $indent, '<', $name;
    }

    while(($key, $value) = each(%$ref)) {
      next if(substr($key, 0, 1) eq '-');
      if(!ref($value)) {
	$value = EscapeValue($value) unless($Options->{noescape});
        if($key eq $Options->{contentkey}) {
	  $text_content = $value;
	}
	else {
	  push @result, ' ', $key, '="', $value , '"';
	}
      }
      else {
	push @nested, ValueToXML($Options, $value, $key, $encoded, "$indent  ");
      }
    }

    if(@nested  or  $text_content) {
      if($named) {
        push @result, ">";
	if($text_content) {
	  push @result, $text_content;
	  $nested[0] =~ s/^\s+// if(@nested);
	}
	else {
	  push @result, "\n";
	}
	if(@nested) {
	  push @result, @nested, $indent;
	}
	push @result, '</', $name, ">\n";
      }
      else {
        push @result, @nested;             # Special case if no root elements
      }
    }
    else {
      push @result, " />\n";
    }
  }

  elsif(ref($ref) eq 'ARRAY') {
    foreach $value (@$ref) {
      if(!ref($value)) {
        push @result,
               $indent, '<', $name, '>',
	       ($Options->{noescape} ? $value : EscapeValue($value)),
               '</', $name, ">\n";
      }
      elsif(ref($value) eq 'HASH') {
	push @result, ValueToXML($Options, $value, $name, $encoded, $indent);
      }
      else {
	push @result,
	       $indent, '<', $name, ">\n",
	       ValueToXML($Options, $value, 'anon', $encoded, "$indent  "),
	       $indent, '</', $name, ">\n";
      }
    }
  }

  else {
    croak "Can't encode a value of type: " . ref($ref);
  }

  return(join('', @result));
}


##############################################################################
# Sub: EscapeValue()
#
# Helper routine for automatically escaping values for XMLout().
# Expects a scalar data value.  Returns escaped version.
#

sub EscapeValue {
  my($data) = @_;

  $data =~ s/&/&amp;/sg;
  $data =~ s/</&lt;/sg;
  $data =~ s/>/&gt;/sg;
  $data =~ s/"/&quot;/sg;

  return($data);
}


##############################################################################
# Sub: HashToArray()
#
# Helper routine for ValueToXML().
# Attempts to 'unfold' a hash of hashes into an array of hashes.  Returns a
# reference to the array on success or the original hash if unfolding is
# not possible.
#

sub HashToArray {
  my $Options = shift;
  my $Parent  = shift;
  my $HashRef = shift;

  my $ArrayRef = [];

  my($key, $value);

  foreach $key (keys(%$HashRef)) {
    $value = $HashRef->{$key};
    return($HashRef) unless(ref($value) eq 'HASH');

    if(ref($Options->{keyattr}) eq 'HASH') {
      return($HashRef) unless(defined($Options->{keyattr}->{$Parent}));
      push(@$ArrayRef, { $Options->{keyattr}->{$Parent}->[0] => $key, %$value });
    }
    else {
      push(@$ArrayRef, { $Options->{keyattr}->[0] => $key, %$value });
    }
  }

  return($ArrayRef);
}

1;

__END__

=head1 QUICK START

Say you have a script called B<foo> and a file of configuration options
called B<foo.xml> containing this:

  <config logdir="/var/log/foo/" debugfile="/tmp/foo.debug">
    <server name="sahara" osname="solaris" osversion="2.6">
      <address>10.0.0.101</address>
      <address>10.0.1.101</address>
    </server>
    <server name="gobi" osname="irix" osversion="6.5">
      <address>10.0.0.102</address>
    </server>
    <server name="kalahari" osname="linux" osversion="2.0.34">
      <address>10.0.0.103</address>
      <address>10.0.1.103</address>
    </server>
  </config>

The following lines of code in B<foo>:

  use XML::Simple;

  my $config = XMLin();

will 'slurp' the configuration options into the hashref $config (because no
arguments are passed to C<XMLin()> the name and location of the XML file will
be inferred from name and location of the script).  You can dump out the
contents of the hashref using Data::Dumper:

  use Data::Dumper;

  print Dumper($config);

which will produce something like this (formatting has been adjusted for
brevity):

  {
      'logdir'        => '/var/log/foo/',
      'debugfile'     => '/tmp/foo.debug',
      'server'        => {
	  'sahara'        => {
	      'osversion'     => '2.6',
	      'osname'        => 'solaris',
	      'address'       => [ '10.0.0.101', '10.0.1.101' ]
	  },
	  'gobi'          => {
	      'osversion'     => '6.5',
	      'osname'        => 'irix',
	      'address'       => '10.0.0.102'
	  },
	  'kalahari'      => {
	      'osversion'     => '2.0.34',
	      'osname'        => 'linux',
	      'address'       => [ '10.0.0.103', '10.0.1.103' ]
	  }
      }
  }

Your script could then access the name of the log directory like this:

  print $config->{logdir};

similarly, the second address on the server 'kalahari' could be referenced as:

  print $config->{server}->{kalahari}->{address}->[1];

What could be simpler?  (Rhetorical).

For simple requirements, that's really all there is to it.  If you want to
store your XML in a different directory or file, or pass it in as a string or
even pass it in via some derivative of an IO::Handle, you'll need to check out
L<"OPTIONS">.  If you want to turn off or tweak the array folding feature (that
neat little transformation that produced $config->{server}) you'll find options
for that as well.

If you want to generate XML (for example to write a modified version of
$config back out as XML), check out C<XMLout()>.

If your needs are not so simple, this may not be the module for you.  In that
case, you might want to read L<"WHERE TO FROM HERE?">.

=head1 DESCRIPTION

The XML::Simple module provides a simple API layer on top of the XML::Parser
module.  Two functions are exported: C<XMLin()> and C<XMLout()>.

The most common approach is to simply call these two functions directly, but an
optional object oriented interface (see L<"OPTIONAL OO INTERFACE"> below)
allows them to be called as methods of an B<XML::Simple> object.

=head2 XMLin()

Parses XML formatted data and returns a reference to a data structure which
contains the same information in a more readily accessible form.  (Skip
down to L<"EXAMPLES"> below, for more sample code).

C<XMLin()> accepts an optional XML specifier followed by zero or more 'name =>
value' option pairs.  The XML specifier can be one of the following:

=over 4

=item A filename

If the filename contains no directory components C<XMLin()> will look for the
file in each directory in the searchpath (see L<"OPTIONS"> below).  eg:

  $ref = XMLin('/etc/params.xml');

=item undef

If there is no XML specifier, C<XMLin()> will check the script directory and
each of the searchpath directories for a file with the same name as the script
but with the extension '.xml'.  Note: if you wish to specify options, you
must specify the value 'undef'.  eg:

  $ref = XMLin(undef, forcearray => 1);

=item A string of XML

A string containing XML (recognised by the presence of '<' and '>' characters)
will be parsed directly.  eg:

  $ref = XMLin('<opt username="bob" password="flurp" />');

=item An IO::Handle object

An IO::Handle object will be read to EOF and its contents parsed. eg:

  $fh = new IO::File('/etc/params.xml');
  $ref = XMLin($fh);

=back

=head2 XMLout()

Takes a data structure (generally a hashref) and returns an XML encoding of
that structure.  If the resulting XML is parsed using C<XMLin()>, it will
return a data structure equivalent to the original. 

When translating hashes to XML, hash keys which have a leading '-' will be
silently skipped.  This is the approved method for marking elements of a
data structure which should be ignored by C<XMLout>.  (Note: If these items
were not skipped the key names would be emitted as element or attribute names
with a leading '-' which would not be valid XML).

=head2 Caveats

Some care is required in creating data structures which will be passed to
C<XMLout()>.  Hash keys from the data structure will be encoded as either XML
element names or attribute names.  Therefore, you should use hash key names 
which conform to the relatively strict XML naming rules:

Names in XML must begin with a letter.  The remaining characters may be
letters, digits, hyphens (-), underscores (_) or full stops (.).  It is also
allowable to include one colon (:) in an element name but this should only be
used when working with namespaces - a facility well beyond the scope of
B<XML::Simple>.

You can use other punctuation characters in hash values (just not in hash
keys) however B<XML::Simple> does not support dumping binary data.

If you break these rules, the current implementation of C<XMLout()> will 
simply emit non-compliant XML which will be rejected if you try to read it
back in.  (A later version of B<XML::Simple> might take a more proactive
approach).

Note also that although you can nest hashes and arrays to arbitrary levels,
recursive data structures are not supported and will cause C<XMLout()> to die.

Refer to L<"WHERE TO FROM HERE?"> if C<XMLout()> is too simple for your needs.


=head1 OPTIONS

B<XML::Simple> supports a number of options (in fact as each release of
B<XML::Simple> adds more options, the module's claim to the name 'Simple'
becomes more tenuous).  If you find yourself repeatedly having to specify
the same options, you might like to investigate L<"OPTIONAL OO INTERFACE">
below.

Both C<XMLin()> and C<XMLout()> expect a single argument followed by a list of
options.  An option takes the form of a 'name => value' pair.  The options
listed below are marked with 'B<in>' if they are recognised by C<XMLin()> and
'B<out>' if they are recognised by C<XMLout()>.

=over 4

=item keyattr => [ list ] (B<in+out>)

This option controls the 'array folding' feature which translates nested
elements from an array to a hash.  For example, this XML:

    <opt>
      <user login="grep" fullname="Gary R Epstein" />
      <user login="stty" fullname="Simon T Tyson" />
    </opt>

would, by default, parse to this:

    {
      'user' => [
		  {
		    'login' => 'grep',
		    'fullname' => 'Gary R Epstein'
		  },
		  {
		    'login' => 'stty',
		    'fullname' => 'Simon T Tyson'
		  }
		]
    }

If the option 'keyattr => "login"' were used to specify that the 'login'
attribute is a key, the same XML would parse to:

    {
      'user' => {
		  'stty' => {
			      'fullname' => 'Simon T Tyson'
			    },
		  'grep' => {
			      'fullname' => 'Gary R Epstein'
			    }
		}
    }

The key attribute names should be supplied in an arrayref if there is more
than one.  C<XMLin()> will attempt to match attribute names in the order
supplied.  C<XMLout()> will use the first attribute name supplied when
'unfolding' a hash into an array.

Note: the keyattr option controls the folding of arrays.  By default a single
nested element will be rolled up into a scalar rather than an array and
therefore will not be folded.  Use the 'forcearray' option (below) to force
nested elements to be parsed into arrays and therefore candidates for folding
into hashes.

The default value for 'keyattr' is ['name', 'key', 'id'].  Setting this option
to an empty list will disable the array folding feature.

=item keyattr => { list } (B<in+out>)

This alternative method of specifiying the key attributes allows more fine grained
control over which elements are folded and on which attributes.  For example the 
option 'keyattr => { package => 'id' } will cause any package elements to be folded
on the 'id' attribute.  No other elements which have an 'id' attribute will be
folded at all. 

Two further variations are made possible by prefixing a '+' or a '-' character
to the attribute name:

The option 'keyattr => { user => "+login" }' will cause this XML:

    <opt>
      <user login="grep" fullname="Gary R Epstein" />
      <user login="stty" fullname="Simon T Tyson" />
    </opt>

to parse to this data structure:

    {
      'user' => {
		  'stty' => {
			      'fullname' => 'Simon T Tyson',
			      'login'    => 'stty'
			    },
		  'grep' => {
			      'fullname' => 'Gary R Epstein',
			      'login'    => 'grep'
			    }
		}
    }

The '+' indicates that the value of the key attribute should be copied rather than
moved to the folded hash key.

A '-' prefix would produce this result:

    {
      'user' => {
		  'stty' => {
			      'fullname' => 'Simon T Tyson',
			      '-login'    => 'stty'
			    },
		  'grep' => {
			      'fullname' => 'Gary R Epstein',
			      '-login'    => 'grep'
			    }
		}
    }

As described earlier, C<XMLout> will ignore hash keys starting with a '-'.

=item searchpath => [ list ] (B<in>)

Where the XML is being read from a file, and no path to the file is specified,
this attribute allows you to specify which directories should be searched.

If the first parameter to C<XMLin()> is undefined, the default searchpath
will contain only the directory in which the script itself is located.
Otherwise the default searchpath will be empty.  

Note: the current directory ('.') is B<not> searched unless it is the directory
containing the script.

=item forcearray => 1 (B<in>)

This option should be set to '1' to force nested elements to be represented
as arrays even when there is only one.  Eg, with forcearray enabled, this
XML:

    <opt>
      <name>value</name>
    </opt>

would parse to this:

    {
      'name' => [
		  'value'
		]
    }

instead of this (the default):

    {
      'name' => 'value'
    }

This option is especially useful if the data structure is likely to be written
back out as XML and the default behaviour of rolling single nested elements up
into attributes is not desirable. 

If you are using the array folding feature, you should almost certainly enable
this option.  If you do not, single nested elements will not be parsed to
arrays and therefore will not be candidates for folding to a hash.  (Given that
the default value of 'keyattr' enables array folding, the default value of this
option should probably also have been enabled too - sorry).

=item forcearray => [ name(s) ] (B<in>)

This alternative form of the 'forcearray' option allows you to specify a list
of element names which should always be forced into an array representation,
rather than the 'all or nothing' approach above.

=item cache => [ cache scheme(s) ] (B<in>)

Because loading the B<XML::Parser> module and parsing an XML file can consume a
significant number of CPU cycles, it is often desirable to cache the output of
C<XMLin()> for later reuse.

When parsing from a named file, B<XML::Simple> supports a number of caching
schemes.  The 'cache' option may be used to specify one or more schemes (using
an anonymous array).  Each scheme will be tried in turn in the hope of finding
a cached pre-parsed representation of the XML file.  If no cached copy is
found, the file will be parsed and the first cache scheme in the list will be
used to save a copy of the results.  The following cache schemes have been
implemented:

=over 4

=item storable

Utilises B<Storable.pm> to read/write a cache file with the same name as the
XML file but with the extension .stor

=item memshare

When a file is first parsed, a copy of the resulting data structure is retained
in memory in the B<XML::Simple> module's namespace.  Subsequent calls to parse
the same file will return a reference to this structure.  This cached version
will persist only for the life of the Perl interpreter (which in the case of
mod_perl for example, may be some significant time).

Because each caller receives a reference to the same data structure, a change
made by one caller will be visible to all.  For this reason, the reference
returned should be treated as read-only.

=item memcopy

This scheme works identically to 'memshare' (above) except that each caller
receives a reference to a new data structure which is a copy of the cached
version.  Copying the data structure will add a little processing overhead,
therefore this scheme should only be used where the caller intends to modify
the data structure (or wishes to protect itself from others who might).  This
scheme uses B<Storable.pm> to perform the copy.

=back

=item keeproot => 1 (B<in+out>)

In its attempt to return a data structure free of superfluous detail and
unnecessary levels of indirection, C<XMLin()> normally discards the root
element name.  Setting the 'keeproot' option to '1' will cause the root element
name to be retained.  So after executing this code:

  $config = XMLin('<config tempdir="/tmp" />', keeproot => 1)

You'll be able to reference the tempdir as
C<$config-E<gt>{config}-E<gt>{tempdir}> instead of the default
C<$config-E<gt>{tempdir}>.

Similarly, setting the 'keeproot' option to '1' will tell C<XMLout()> that the
data structure already contains a root element name and it is not necessary to
add another.

=item rootname => 'string' (B<out>)

By default, when C<XMLout()> generates XML, the root element will be named
'opt'.  This option allows you to specify an alternative name.

Specifying either undef or the empty string for the rootname option will
produce XML with no root elements.  In most cases the resulting XML fragment
will not be 'well formed' and therefore could not be read back in by C<XMLin()>.
Nevertheless, the option has been found to be useful in certain circumstances.

=item contentkey => 'keyname' (B<in+out>)

When C<XMLin()> parses elements which have text content as well as attributes,
the text content must be represented as a hash value rather than a simple
scalar.  This option allows you to specify a name for the hash key to override
the default 'content'.  So for example:

  XMLin('<opt one="1">Text</opt>', contentkey => 'text')

will parse to:

  { 'one' => 1, 'text' => 'Text' }

instead of:

  { 'one' => 1, 'content' => 'Text' }

C<XMLout()> will also honour the value of this option when converting a hashref
to XML.

=item xmldecl => 1  or  xmldecl => 'string'  (B<out>)

If you want the output from C<XMLout()> to start with the optional XML
declaration, simply set the option to '1'.  The default XML declaration is:

        <?xml version='1' standalone='yes'?>

If you want some other string (for example to declare an encoding value), set
the value of this option to the complete string you require.

=item outputfile => <file specifier> (B<out>)

The default behaviour of C<XMLout()> is to return the XML as a string.  If you
wish to write the XML to a file, simply supply the filename using the
'outputfile' option.  Alternatively, you can supply an IO handle object instead
of a filename.

=item noescape => 1 (B<out>)

By default, C<XMLout()> will translate the characters 'E<lt>', 'E<gt>', '&' and
'"' to '&lt;', '&gt;', '&amp;' and '&quot' respectively.  Use this option to
suppress escaping (presumably because you've already escaped the data in some
more sophisticated manner).

=back

=head1 OPTIONAL OO INTERFACE

The default values for the options described above are unlikely to suit
everyone.  The object oriented interface allows you to effectively override
B<XML::Simple>'s defaults with your preferred values.  It works like this:

First create an XML::Simple parser object with your preferred defaults:

  my $xs = new XML::Simple(forcearray => 1, keeproot => 1);

Now call C<XMLin()> or C<XMLout()> as a method of that object:

  my $ref = $xs->XMLin($xml);
  my $xml = $xs->XMLout($ref);

You can also specify options when you make the method calls and these values
will be merged with the values specified when the object was created.  Values
specified in a method call take precedence.

=head1 ERROR HANDLING

The XML standard is very clear on the issue of non-compliant documents.  An
error in parsing any single element (for example a missing end tag) must cause
the whole document to be rejected.  B<XML::Simple> will die with an
appropriate message if it encounters a parsing error.

If dying is not appropriate for your application, you should arrange to call
C<XMLin()> in an eval block and look for errors in $@.  eg:

    my $config = eval { XMLin() };
    PopUpMessage($@) if($@);

Note, there is a common misconception that use of B<eval> will significantly
slow down a script.  While that may be true when the code being eval'd is in a
string, it is not true of code like the sample above.

=head1 EXAMPLES

When C<XMLin()> reads the following very simple piece of XML:

    <opt username="testuser" password="frodo"></opt>

it returns the following data structure:

    {
      'username' => 'testuser',
      'password' => 'frodo'
    }

The identical result could have been produced with this alternative XML:

    <opt username="testuser" password="frodo" />

Or this (although see 'forcearray' option for variations):

    <opt>
      <username>testuser</username>
      <password>frodo</password>
    </opt>

Repeated nested elements are represented as anonymous arrays:

    <opt>
      <person firstname="Joe" lastname="Smith">
        <email>joe@smith.com</email>
        <email>jsmith@yahoo.com</email>
      </person>
      <person firstname="Bob" lastname="Smith">
        <email>bob@smith.com</email>
      </person>
    </opt>

    {
      'person' => [
                    {
                      'email' => [
                                   'joe@smith.com',
                                   'jsmith@yahoo.com'
                                 ],
                      'firstname' => 'Joe',
                      'lastname' => 'Smith'
                    },
                    {
                      'email' => 'bob@smith.com',
                      'firstname' => 'Bob',
                      'lastname' => 'Smith'
                    }
                  ]
    }

Nested elements with a recognised key attribute are transformed (folded) from
an array into a hash keyed on the value of that attribute:

    <opt>
      <person key="jsmith" firstname="Joe" lastname="Smith" />
      <person key="tsmith" firstname="Tom" lastname="Smith" />
      <person key="jbloggs" firstname="Joe" lastname="Bloggs" />
    </opt>

    {
      'person' => {
                    'jbloggs' => {
                                   'firstname' => 'Joe',
                                   'lastname' => 'Bloggs'
                                 },
                    'tsmith' => {
                                  'firstname' => 'Tom',
                                  'lastname' => 'Smith'
                                },
                    'jsmith' => {
                                  'firstname' => 'Joe',
                                  'lastname' => 'Smith'
                                }
                  }
    }


The <anon> tag can be used to form anonymous arrays:

    <opt>
      <head><anon>Col 1</anon><anon>Col 2</anon><anon>Col 3</anon></head>
      <data><anon>R1C1</anon><anon>R1C2</anon><anon>R1C3</anon></data>
      <data><anon>R2C1</anon><anon>R2C2</anon><anon>R2C3</anon></data>
      <data><anon>R3C1</anon><anon>R3C2</anon><anon>R3C3</anon></data>
    </opt>

    {
      'head' => [
		  [ 'Col 1', 'Col 2', 'Col 3' ]
		],
      'data' => [
		  [ 'R1C1', 'R1C2', 'R1C3' ],
		  [ 'R2C1', 'R2C2', 'R2C3' ],
		  [ 'R3C1', 'R3C2', 'R3C3' ]
		]
    }

Anonymous arrays can be nested to arbirtrary levels and as a special case, if
the surrounding tags for an XML document contain only an anonymous array the
arrayref will be returned directly rather than the usual hashref:

    <opt>
      <anon><anon>Col 1</anon><anon>Col 2</anon></anon>
      <anon><anon>R1C1</anon><anon>R1C2</anon></anon>
      <anon><anon>R2C1</anon><anon>R2C2</anon></anon>
    </opt>

    [
      [ 'Col 1', 'Col 2' ],
      [ 'R1C1', 'R1C2' ],
      [ 'R2C1', 'R2C2' ]
    ]



=head1 WHERE TO FROM HERE?

B<XML::Simple> is by nature very simple.  

=over 4

=item *

The parsing process liberally disposes of 'surplus' whitespace - some 
applications will be sensitive to this.

=item *

Slurping data into a hash will implicitly discard information about attribute
order.  Normally this would not be a problem because any items for which order
is important would typically be encoded as elements rather than attributes.
However B<XML::Simple>'s aggressive slurping and folding algorithms can
defeat even these techniques.

=item *

XML elements containing both text content and nested elements (eg: marked-up
text) are not parsed in a useful way.

=item *

The API offers little control over the output of C<XMLout()>.  In particular,
it is not especially likely that feeding the output from C<XMLin()> into
C<XMLout()> will reproduce the original XML (although passing the output from
C<XMLout()> into C<XMLin()> should reproduce the original data structure).

=item *

C<XMLout()> does not currently support encodings (although it shouldn't stand
in your way if you feed it encoded data).

=item *

If you're attempting to get the output from C<XMLout()> to conform to a
specific DTD, you're almost certainly using the wrong tool for the job.

=back

If any of these points are a problem for you, then B<XML::Simple> is probably
not the right module for your application.  The following section is intended
to give pointers which might help you select a more powerful tool - it's a bit
sketchy right now but submissions are welcome.

=over 4

=item XML::Parser

B<XML::Simple> is built on top of B<XML::Parser>, so if you have B<XML::Simple>
working you already have B<XML::Parser> installed.  This is a comprehensive,
fast, industrial strength (non-validating) parsing tool built on top of James
Clark's 'expat' library.  It does support converting XML into a Perl tree
structure but for arbritrarily large documents you're probably better off
defining handler routines for B<XML::Parser> to call as each element is parsed.
The distribution includes a number of sample applications.

=item XML::DOM

The data structure returned by B<XML::Simple> was designed for convenience
rather than standards compliance.  B<XML::DOM> is a parser built on top of
B<XML::Parser>, which returns a 'Document' object conforming to the API of the
Document Object Model as described at http://www.w3.org/TR/REC-DOM-Level-1 .
This Document object can then be examined, modified and written back out to a
file or converted to a string. 

=item XML::Grove

Compliance with the Document Object Model might be particularly useful when
porting code to or from another language.  However, if you're looking for a
simpler, 'perlish' object interface, take a look at B<XML::Grove>.

=item XML::Twig

XML::Twig offers a tree-oriented interface to a document while still allowing
the processing of documents of any size. It allows processing chunks of
documents in tree-mode which can then be flushed or purged from the memory.
The XML::Twig page is at http://standards.ieee.org/resources/spasystem/twig/

=item libxml-perl

B<libxml-perl> is a collection of Perl modules, scripts, and documents for
working with XML in Perl. The distribution includes PerlSAX - a Perl
implementation of the SAX API.  It also include B<XML::PatAct> modules for
processing XML by defining patterns and associating them with actions.  For more
details see http://bitsko.slc.ut.us/libxml-perl/ .

=item XML::Writer

B<XML::Writer> is a helper module for Perl programs that write a XML documents.

=item XML::Dumper

B<XML::Dumper> dumps Perl data to a structured XML format. B<XML::Dumper> can
also read XML data that was previously dumped by the module and convert it back
to Perl. 

=back

Don't forget to check out the Perl XML FAQ at:
http://www.perlxml.com/faq/perl-xml-faq.html


=head1 STATUS

This version (1.04) is the current stable version.  

=head1 SEE ALSO

B<XML::Simple> requires B<XML::Parser> and B<File::Spec>.  The optional caching
functions require B<Storable>.

=head1 COPYRIGHT 

Copyright 1999 Grant McLean E<lt>grantm@web.co.nzE<gt>

This library is free software; you can redistribute it and/or modify it
under the same terms as Perl itself. 

=cut


