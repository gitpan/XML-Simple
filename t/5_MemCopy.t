use strict;

BEGIN {
  eval { require Storable; };
  unless($INC{'Storable.pm'}) {
    print STDERR "skipping - Storable.pm not available on this platform\n";
    print "1..1\nok\n";
    exit;
  }
  print "1..7\n";
}

my $t = 1;

##############################################################################
#                   S U P P O R T   R O U T I N E S
##############################################################################

##############################################################################
# Print out 'n ok' or 'n not ok' as expected by test harness.
# First arg is test number (n).  If only one following arg, it is interpreted
# as true/false value.  If two args, equality = true.
#

sub ok {
  my($n, $x, $y) = @_;
  die "Sequence error got $n expected $t" if($n != $t);
  $x = 0 if(defined($y)  and  $x ne $y);
  print(($x ? '' : 'not '), 'ok ', $t++, "\n");
}


##############################################################################
# Take two scalar values (may be references) and compare them (recursively
# if necessary) returning 1 if same, 0 if different.
#

sub DataCompare {
  my($x, $y) = @_;

  my($i);

  if(!ref($x)) {
    return($x eq $y);
  }

  if(ref($x) eq 'ARRAY') {
    return(0) unless(ref($y) eq 'ARRAY');
    return(0) if(scalar(@$x) != scalar(@$y));
    for($i = 0; $i < scalar(@$x); $i++) {
      DataCompare($x->[$i], $y->[$i]) || return(0);
    }
    return(1);
  }

  if(ref($x) eq 'HASH') {
    return(0) unless(ref($y) eq 'HASH');
    return(0) if(scalar(keys(%$x)) != scalar(keys(%$y)));
    foreach $i (keys(%$x)) {
      DataCompare($x->{$i}, $y->{$i}) || return(0);
    }
    return(1);
  }

  print STDERR "Don't know how to compare: " . ref($x) . "\n";
  return(0);
}


##############################################################################
# Copy a file
#

sub CopyFile {
  my($Src, $Dst) = @_;
  
  open(IN, $Src) || return(undef);
  local($/) = undef;
  my $Data = <IN>;
  close(IN);

  open(OUT, ">$Dst") || return(undef);
  print OUT $Data;
  close(OUT);

  return(1);
}


##############################################################################
#                      T E S T   R O U T I N E S
##############################################################################

use XML::Simple;

# Initialise some filenames and test data

my $SrcFile   = 't/desertnet.xml-source';
my $XMLFile   = 't/desertnet.xml';
my $Expected  = {
          'server' => {
                        'sahara' => {
                                      'osversion' => '2.6',
                                      'osname' => 'solaris',
                                      'address' => [
                                                     '10.0.0.101',
                                                     '10.0.1.101'
                                                   ]
                                    },
                        'gobi' => {
                                    'osversion' => '6.5',
                                    'osname' => 'irix',
                                    'address' => '10.0.0.102'
                                  },
                        'kalahari' => {
                                        'osversion' => '2.0.34',
                                        'osname' => 'linux',
                                        'address' => [
                                                       '10.0.0.103',
                                                       '10.0.1.103'
                                                     ]
                                      }
                      }
        };

ok(1, CopyFile($SrcFile, $XMLFile));  # Start with known source file
my $t0 = (stat($XMLFile))[9];         # Remember its timestamp
                                      
				      # Parse it with caching enabled
my $opt = XMLin($XMLFile, cache => 'memcopy');
ok(2, DataCompare($opt, $Expected));  # Got what we expected

unlink($XMLFile);
ok(3, ! -e $XMLFile);                 # Original XML file is gone
open(FILE, ">$XMLFile");              # Re-create it (empty)
close(FILE);
$t0--;
utime($t0, $t0, $XMLFile);            # but wind back the clock

$opt = XMLin($XMLFile, cache => 'memcopy');
ok(4, DataCompare($opt, $Expected));  # Got what we expected from the cache
ok(5, ! -s $XMLFile);                 # even though the XML file is empty


sleep(1);
open(FILE, ">$XMLFile");              # Write some new data to the XML file
print FILE qq(<opt one="1" two="2"></opt>\n);
close(FILE);

                                      # Parse again with caching enabled
$opt = XMLin($XMLFile, cache => 'memcopy');
                                      # Came through the cache
ok(6, DataCompare($opt, { one => 1, two => 2}));

$opt->{three} = 3;                    # Alter the returned structure
                                      # Retrieve again from the cache
my $opt2 = XMLin($XMLFile, cache => 'memcopy');

ok(7, !defined($opt2->{three}));      # Confirm cached copy is not altered


# Clean up and go

unlink($XMLFile);
exit(0);

