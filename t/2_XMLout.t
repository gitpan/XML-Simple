use strict;
use IO::File;

BEGIN { print "1..126\n"; }

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
# Read file and return contents as a scalar.
#

sub ReadFile {
  local($/) = undef;

  open(_READ_FILE_, $_[0]) || die "open($_[0]): $!";
  my $data = <_READ_FILE_>;
  close(_READ_FILE_);
  return($data);
}

use XML::Simple;

# Try encoding a scalar value

my $xml = XMLout("scalar");
ok(1, 1);                             # XMLout did not crash 
ok(2, defined($xml));                 # and it returned an XML string
ok(3, XMLin($xml), 'scalar');         # which parses back OK


# Next try encoding a hash

my $hashref1 = { one => 1, two => 'II', three => '...' };
my $hashref2 = { one => 1, two => 'II', three => '...' };

# Expect:
# <opt one="1" two="II" three="..." />

$_ = XMLout($hashref1);               # Encode to $_ for convenience
                                      # Confirm it parses back OK
ok(4, DataCompare($hashref1, XMLin($_)));
ok(5, s/one="1"//);                   # first key encoded OK
ok(6, s/two="II"//);                  # second key encoded OK
ok(7, s/three="..."//);               # third key encoded OK
ok(8, /^<\w+\s+\/>/);                 # no other attributes encoded


# Now try encoding a hash with a nested array

my $ref = {array => [qw(one two three)]};
# Expect:
# <opt>
#   <array>one</array>
#   <array>two</array>
#   <array>three</array>
# </opt>

$_ = XMLout($ref);                    # Encode to $_ for convenience
ok(9, DataCompare($ref, XMLin($_)));
ok(10, s{<array>one</array>\s*
         <array>two</array>\s*
         <array>three</array>}{}sx);  # array elements encoded in correct order
ok(11, /^<(\w+)\s*>\s*<\/\1>\s*$/s);  # no other spurious encodings


# Now try encoding a nested hash

$ref = { value => '555 1234',
         hash1 => { one => 1 },
         hash2 => { two => 2 } };
# Expect:
# <opt value="555 1234">
#   <hash1 one="1" />
#   <hash2 two="2" />
# </opt>

$_ = XMLout($ref);
ok(12, DataCompare($ref, XMLin($_))); # Parses back OK

ok(13, s{<hash1 one="1" />\s*}{}s);
ok(14, s{<hash2 two="2" />\s*}{}s);
ok(15, m{^<(\w+)\s+value="555 1234"\s*>\s*</\1>\s*$}s);


# Now try encoding an anonymous array

$ref = [ qw(1 two III) ];
# Expect:
# <opt>
#   <anon>1</anon>
#   <anon>two</anon>
#   <anon>III</anon>
# </opt>

$_ = XMLout($ref);
ok(16, DataCompare($ref, XMLin($_))); # Parses back OK

ok(17, s{<anon>1</anon>\s*}{}s);
ok(18, s{<anon>two</anon>\s*}{}s);
ok(19, s{<anon>III</anon>\s*}{}s);
ok(20, m{^<(\w+)\s*>\s*</\1>\s*$}s);


# Now try encoding a nested anonymous array

$ref = [ [ qw(1.1 1.2) ], [ qw(2.1 2.2) ] ];
# Expect:
# <opt>
#   <anon>
#     <anon>1.1</anon>
#     <anon>1.2</anon>
#   </anon>
#   <anon>
#     <anon>2.1</anon>
#     <anon>2.2</anon>
#   </anon>
# </opt>

$_ = XMLout($ref);
ok(21, DataCompare($ref, XMLin($_))); # Parses back OK

ok(22, s{<anon>1\.1</anon>\s*}{row}s);
ok(23, s{<anon>1\.2</anon>\s*}{ one}s);
ok(24, s{<anon>2\.1</anon>\s*}{row}s);
ok(25, s{<anon>2\.2</anon>\s*}{ two}s);
ok(26, s{<anon>\s*row one\s*</anon>\s*}{}s);
ok(27, s{<anon>\s*row two\s*</anon>\s*}{}s);
ok(28, m{^<(\w+)\s*>\s*</\1>\s*$}s);


# Now try encoding a hash of hashes with key folding disabled

$ref = { country => {
		      England => { capital => 'London' },
		      France  => { capital => 'Paris' },
		      Turkey  => { capital => 'Istanbul' },
                    }
       };
# Expect:
# <opt>
#   <country>
#     <England capital="London" />
#     <France capital="Paris" />
#     <Turkey capital="Istanbul" />
#   </country>
# </opt>

$_ = XMLout($ref, keyattr => []);
ok(29, DataCompare($ref, XMLin($_))); # Parses back OK
ok(30, s{<England\s+capital="London"\s*/>\s*}{}s);
ok(31, s{<France\s+capital="Paris"\s*/>\s*}{}s);
ok(32, s{<Turkey\s+capital="Istanbul"\s*/>\s*}{}s);
ok(33, s{<country\s*>\s*</country>}{}s);
ok(34, s{^<(\w+)\s*>\s*</\1>$}{}s);


# Try encoding same again with key folding set to non-standard value

# Expect:
# <opt>
#   <country fullname="England" capital="London" />
#   <country fullname="France" capital="Paris" />
#   <country fullname="Turkey" capital="Istanbul" />
# </opt>

$_ = XMLout($ref, keyattr => ['fullname']);
$xml = $_;
ok(35, DataCompare($ref,
                   XMLin($_, keyattr => ['fullname']))); # Parses back OK
ok(36, s{\s*fullname="England"}{uk}s);
ok(37, s{\s*capital="London"}{uk}s);
ok(38, s{\s*fullname="France"}{fr}s);
ok(39, s{\s*capital="Paris"}{fr}s);
ok(40, s{\s*fullname="Turkey"}{tk}s);
ok(41, s{\s*capital="Istanbul"}{tk}s);
ok(42, s{<countryukuk\s*/>\s*}{}s);
ok(43, s{<countryfrfr\s*/>\s*}{}s);
ok(44, s{<countrytktk\s*/>\s*}{}s);
ok(45, s{^<(\w+)\s*>\s*</\1>$}{}s);

# Same again but specify name as scalar rather than array

$_ = XMLout($ref, keyattr => 'fullname');
ok(46, $_ eq $xml);                            # Same result as last time


# One more time but with default key folding values

# Expect:
# <opt>
#   <country name="England" capital="London" />
#   <country name="France" capital="Paris" />
#   <country name="Turkey" capital="Istanbul" />
# </opt>

$_ = XMLout($ref);
ok(47, DataCompare($ref, XMLin($_))); # Parses back OK
ok(48, s{\s*name="England"}{uk}s);
ok(49, s{\s*capital="London"}{uk}s);
ok(50, s{\s*name="France"}{fr}s);
ok(51, s{\s*capital="Paris"}{fr}s);
ok(52, s{\s*name="Turkey"}{tk}s);
ok(53, s{\s*capital="Istanbul"}{tk}s);
ok(54, s{<countryukuk\s*/>\s*}{}s);
ok(55, s{<countryfrfr\s*/>\s*}{}s);
ok(56, s{<countrytktk\s*/>\s*}{}s);
ok(57, s{^<(\w+)\s*>\s*</\1>$}{}s);


# Check that default XML declaration works
#
# Expect:
# <?xml version='1' standalone='yes'?>
# <opt one="1" />

$ref = { one => 1 };

$_ = XMLout($ref, xmldecl => 1);
ok(58, DataCompare($ref, XMLin($_))); # Parses back OK
ok(59, s{^\Q<?xml version='1' standalone='yes'?>\E}{}s);
ok(60, s{<opt one="1" />}{}s);
ok(61, m{^\s*$}s);


# Check that custom XML declaration works
#
# Expect:
# <?xml version='1' encoding='ISO-8859-1'?>
# <opt one="1" />

$_ = XMLout($ref, xmldecl => "<?xml version='1' encoding='ISO-8859-1'?>");
ok(62, DataCompare($ref, XMLin($_))); # Parses back OK
ok(63, s{^\Q<?xml version='1' encoding='ISO-8859-1'?>\E}{}s);
ok(64, s{<opt one="1" />}{}s);
ok(65, m{^\s*$}s);


# Check that special characters do get escaped

$ref = { a => '<A>', b => '"B"', c => '&C&' };
$_ = XMLout($ref);
ok(66, DataCompare($ref, XMLin($_))); # Parses back OK
ok(67, s{a="&lt;A&gt;"}{}s);
ok(68, s{b="&quot;B&quot;"}{}s);
ok(69, s{c="&amp;C&amp;"}{}s);
ok(70, s{^<(\w+)\s*/>$}{}s);


# unless we turn escaping off

$_ = XMLout($ref, noescape => 1);
ok(71, s{a="<A>"}{}s);
ok(72, s{b=""B""}{}s);
ok(73, s{c="&C&"}{}s);
ok(74, s{^<(\w+)\s*/>$}{}s);


# Try encoding a recursive data structure and confirm that it fails

$_ = eval {
  my $ref = { a => '1' };
  $ref->{b} = $ref;
  XMLout($ref);
};
ok(75, !defined($_));
ok(76, $@ =~ /recursive data structures not supported/);


# Try encoding a blessed reference and confirm that it fails

$_ = eval { my $ref = new IO::File; XMLout($ref) };
ok(77, !defined($_));
ok(78, $@ =~ /Can't encode a value of type: /);


# Repeat some of the above tests with named root element

# Try encoding a scalar value

$xml = XMLout("scalar", rootname => 'TOM');
ok(79, defined($xml));                 # and it returned an XML string
ok(80, XMLin($xml), 'scalar');         # which parses back OK
                                       # and contains the expected data
ok(81, $xml =~ /^\s*<TOM>scalar<\/TOM>\s*$/si);


# Next try encoding a hash

# Expect:
# <DICK one="1" two="II" three="..." />

$_ = XMLout($hashref1, rootname => 'DICK');
                                      # Confirm it parses back OK
ok(82, DataCompare($hashref1, XMLin($_)));
ok(83, s/one="1"//);                  # first key encoded OK
ok(84, s/two="II"//);                 # second key encoded OK
ok(85, s/three="..."//);              # third key encoded OK
ok(86, /^<DICK\s+\/>/);               # only expected root element left


# Now try encoding a hash with a nested array

$ref = {array => [qw(one two three)]};
# Expect:
# <LARRY>
#   <array>one</array>
#   <array>two</array>
#   <array>three</array>
# </LARRY>

$_ = XMLout($ref, rootname => 'LARRY'); # Encode to $_ for convenience
ok(87, DataCompare($ref, XMLin($_)));
ok(88, s{<array>one</array>\s*
         <array>two</array>\s*
         <array>three</array>}{}sx);    # array encoded in correct order
ok(89, /^<(LARRY)\s*>\s*<\/\1>\s*$/s);  # only expected root element left


# Now try encoding a nested hash

$ref = { value => '555 1234',
         hash1 => { one => 1 },
         hash2 => { two => 2 } };
# Expect:
# <CURLY value="555 1234">
#   <hash1 one="1" />
#   <hash2 two="2" />
# </CURLY>

$_ = XMLout($ref, rootname => 'CURLY');
ok(90, DataCompare($ref, XMLin($_))); # Parses back OK

ok(91, s{<hash1 one="1" />\s*}{}s);
ok(92, s{<hash2 two="2" />\s*}{}s);
ok(93, m{^<(CURLY)\s+value="555 1234"\s*>\s*</\1>\s*$}s);


# Now try encoding an anonymous array

$ref = [ qw(1 two III) ];
# Expect:
# <MOE>
#   <anon>1</anon>
#   <anon>two</anon>
#   <anon>III</anon>
# </MOE>

$_ = XMLout($ref, rootname => 'MOE');
ok(94, DataCompare($ref, XMLin($_))); # Parses back OK

ok(95, s{<anon>1</anon>\s*}{}s);
ok(96, s{<anon>two</anon>\s*}{}s);
ok(97, s{<anon>III</anon>\s*}{}s);
ok(98, m{^<(MOE)\s*>\s*</\1>\s*$}s);


# Test again, this time with no root element

# Try encoding a scalar value

ok(99, XMLout("scalar", rootname => '')    =~ /scalar\s+/s);
ok(100, XMLout("scalar", rootname => undef) =~ /scalar\s+/s);


# Next try encoding a hash

# Expect:
#   <one>1</one>
#   <two>II</two>
#   <three>...</three>

$_ = XMLout($hashref1, rootname => '');
                                      # Confirm it parses back OK
ok(101, DataCompare($hashref1, XMLin("<opt>$_</opt>")));
ok(102, s/<one>1<\/one>//);            # first key encoded OK
ok(103, s/<two>II<\/two>//);           # second key encoded OK
ok(104, s/<three>...<\/three>//);      # third key encoded OK
ok(105, /^\s*$/);                      # nothing else left


# Now try encoding a nested hash

$ref = { value => '555 1234',
         hash1 => { one => 1 },
         hash2 => { two => 2 } };
# Expect:
#   <value>555 1234</value>
#   <hash1 one="1" />
#   <hash2 two="2" />

$_ = XMLout($ref, rootname => '');
ok(106, DataCompare($ref, XMLin("<opt>$_</opt>"))); # Parses back OK
ok(107, s{<value>555 1234<\/value>\s*}{}s);
ok(108, s{<hash1 one="1" />\s*}{}s);
ok(109, s{<hash2 two="2" />\s*}{}s);
ok(110, m{^\s*$}s);


# Now try encoding an anonymous array

$ref = [ qw(1 two III) ];
# Expect:
#   <anon>1</anon>
#   <anon>two</anon>
#   <anon>III</anon>

$_ = XMLout($ref, rootname => '');
ok(111, DataCompare($ref, XMLin("<opt>$_</opt>"))); # Parses back OK

ok(112, s{<anon>1</anon>\s*}{}s);
ok(113, s{<anon>two</anon>\s*}{}s);
ok(114, s{<anon>III</anon>\s*}{}s);
ok(115, m{^\s*$}s);


# Test option error handling

$_ = eval { XMLout($hashref1, searchpath => []) }; # only valid for XMLin()
ok(116, !defined($_));
ok(117, $@ =~ /Unrecognised option:/);

$_ = eval { XMLout($hashref1, 'bogus') };
ok(118, !defined($_));
ok(119, $@ =~ /Options must be name => value pairs .odd number supplied./);


# Test output to file

my $TestFile = 'testoutput.xml';
unlink($TestFile);
ok(120, !-e $TestFile);

$xml = XMLout($hashref1);
XMLout($hashref1, outputfile => $TestFile);
ok(121, -e $TestFile);
ok(122, ReadFile($TestFile) eq $xml);
unlink($TestFile);


# Test output to an IO handle

ok(123, !-e $TestFile);
my $fh = new IO::File;
$fh->open(">$TestFile") || die "$!";
XMLout($hashref1, outputfile => $TestFile);
$fh->close();
ok(124, -e $TestFile);
ok(125, ReadFile($TestFile) eq $xml);
unlink($TestFile);

# After all that, confirm that the original hashref we supplied has not
# been corrupted.

ok(126, DataCompare($hashref1, $hashref2));

exit(0);






