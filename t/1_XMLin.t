use strict;
use IO::File;

BEGIN { print "1..38\n"; }

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
      return(0) unless(exists($y->{$i}));
      DataCompare($x->{$i}, $y->{$i}) || return(0);
    }
    return(1);
  }

  print STDERR "Don't know how to compare: " . ref($x) . "\n";
  return(0);
}


##############################################################################
#                      T E S T   R O U T I N E S
##############################################################################

use XML::Simple;
ok(1, 1);                         # Module compiled OK

# Start by parsing an extremely simple piece of XML

my $opt = XMLin(q(<opt name1="value1" name2="value2"></opt>));

my $expected = {
		 name1 => 'value1',
		 name2 => 'value2',
	       };

ok(2, 1);                         # XMLin() didn't crash 
ok(3, defined($opt));             # and it returned a value
ok(4, ref($opt) eq 'HASH');       # and a hasref at that
ok(5, DataCompare($opt, $expected));


# Now try a slightly more complex one that returns the same value

$opt = XMLin(q(
  <opt> 
    <name1>value1</name1>
    <name2>value2</name2>
  </opt>
));
ok(6, DataCompare($opt, $expected));


# And something else that returns the same (line break included to pick up
# missing /s bug)

$opt = XMLin(q(<opt name1="value1"
                    name2="value2" />));
ok(7, DataCompare($opt, $expected));


# Try something with two lists of nested values 

$opt = XMLin(q(
  <opt> 
    <name1>value1.1</name1>
    <name1>value1.2</name1>
    <name1>value1.3</name1>
    <name2>value2.1</name2>
    <name2>value2.2</name2>
    <name2>value2.3</name2>
  </opt>)
);

ok(8, DataCompare($opt, {
  name1 => [ 'value1.1', 'value1.2', 'value1.3' ],
  name2 => [ 'value2.1', 'value2.2', 'value2.3' ],
}));


# Now a simple nested hash

$opt = XMLin(q(
  <opt> 
    <item name1="value1" name2="value2" />
  </opt>)
);

ok(9, DataCompare($opt, {
  item => { name1 => 'value1', name2 => 'value2' }
}));


# Now a list of nested hashes

$opt = XMLin(q(
  <opt> 
    <item name1="value1" name2="value2" />
    <item name1="value3" name2="value4" />
  </opt>)
);
ok(10, DataCompare($opt, {
  item => [
            { name1 => 'value1', name2 => 'value2' },
            { name1 => 'value3', name2 => 'value4' }
	  ]
}));


# Now a list of nested hashes transformed into a hash using default key names

my $string = q(
  <opt> 
    <item name="item1" attr1="value1" attr2="value2" />
    <item name="item2" attr1="value3" attr2="value4" />
  </opt>
);
$opt = XMLin($string);
ok(11, DataCompare($opt, {
  item => {
            item1 => { attr1 => 'value1', attr2 => 'value2' },
            item2 => { attr1 => 'value3', attr2 => 'value4' }
	  }
}));


# Same thing left as an array by suppressing default key names

$opt = XMLin($string, keyattr => [] );
ok(12, DataCompare($opt, {
  item => [
            {name => 'item1', attr1 => 'value1', attr2 => 'value2' },
            {name => 'item2', attr1 => 'value3', attr2 => 'value4' }
	  ]
}));


# Try the other two default key attribute names

$opt = XMLin(q(
  <opt> 
    <item key="item1" attr1="value1" attr2="value2" />
    <item key="item2" attr1="value3" attr2="value4" />
  </opt>
));
ok(13, DataCompare($opt, {
  item => {
            item1 => { attr1 => 'value1', attr2 => 'value2' },
            item2 => { attr1 => 'value3', attr2 => 'value4' }
	  }
}));


$opt = XMLin(q(
  <opt> 
    <item id="item1" attr1="value1" attr2="value2" />
    <item id="item2" attr1="value3" attr2="value4" />
  </opt>
));
ok(14, DataCompare($opt, {
  item => {
            item1 => { attr1 => 'value1', attr2 => 'value2' },
            item2 => { attr1 => 'value3', attr2 => 'value4' }
	  }
}));


# Similar thing using non-standard key names

my $xml = q(
  <opt> 
    <item xname="item1" attr1="value1" attr2="value2" />
    <item xname="item2" attr1="value3" attr2="value4" />
  </opt>);

my $target = {
  item => {
            item1 => { attr1 => 'value1', attr2 => 'value2' },
            item2 => { attr1 => 'value3', attr2 => 'value4' }
	  }
};

$opt = XMLin($xml, keyattr => [qw(xname)]);
ok(15, DataCompare($opt, $target));


# Same again but with key field further down the list

$opt = XMLin($xml, keyattr => [qw(wibble xname)]);
ok(16, DataCompare($opt, $target));


# Same again but with key field supplied as scalar

$opt = XMLin($xml, keyattr => qw(xname));
ok(17, DataCompare($opt, $target));


# Weird variation, not exactly what we wanted but it is what we expected 
# given the current implementation and we don't want to break it accidently

$xml = q(
<opt>
  <item id="one" value="1" name="a" />
  <item id="two" value="2" />
  <item id="three" value="3" />
</opt>
);

$target = { item => {
    'three' => { 'value' => 3 },
    'a'     => { 'value' => 1, 'id' => 'one' },
    'two'   => { 'value' => 2 }
  }
};

$opt = XMLin($xml);
ok(18, DataCompare($opt, $target));

# Try parsing a named external file

$opt = eval{ XMLin('t/test1.xml'); };
ok(19, !$@);                                  # XMLin didn't die
print STDERR $@ if($@);
ok(20, DataCompare($opt, {
  location => 't/test1.xml'
}));


# Try parsing default external file (scriptname.xml in script directory)

$opt = eval { XMLin(); };
print STDERR $@ if($@);
ok(21, !$@);                                  # XMLin didn't die
ok(22, DataCompare($opt, {
  location => 't/1_XMLin.xml'
}));


# Try parsing named file in a directory in the searchpath

$opt = eval {
  XMLin('test2.xml', searchpath => [qw(dir1 dir2 t/subdir)] );
};
print STDERR $@ if($@);
ok(23, !$@);                                  # XMLin didn't die
ok(24, DataCompare($opt, {
  location => 't/subdir/test2.xml'
}));


# Ensure we get expected result if file does not exist

$opt = eval {
  XMLin('bogusfile.xml', searchpath => [qw(. ./t)] ); # should 'die'
};
ok(25, !defined($opt));                          # XMLin failed
ok(26, $@ =~ /Could not find bogusfile.xml in/); # with the expected message


# Try parsing from an IO::Handle 

my $fh = new IO::File;
$fh->open('t/1_XMLin.xml');
$opt = XMLin($fh);
ok(27, 1);                                      # XMLin didn't die
ok(28, $opt->{location}, 't/1_XMLin.xml');      # and it parsed the right file


# Confirm anonymous array folding works in general

$opt = XMLin(q(
  <opt>
    <row>
      <anon>0.0</anon><anon>0.1</anon><anon>0.2</anon>
    </row>
    <row>
      <anon>1.0</anon><anon>1.1</anon><anon>1.2</anon>
    </row>
    <row>
      <anon>2.0</anon><anon>2.1</anon><anon>2.2</anon>
    </row>
  </opt>
));
ok(29, DataCompare($opt, {
  row => [
	   [ '0.0', '0.1', '0.2' ],
	   [ '1.0', '1.1', '1.2' ],
	   [ '2.0', '2.1', '2.2' ]
         ]
}));


# Confirm anonymous array folding works in special top level case

$opt = XMLin(q{
  <opt>
    <anon>one</anon>
    <anon>two</anon>
    <anon>three</anon>
  </opt>
});
ok(30, DataCompare($opt, [
  qw(one two three)
]));


$opt = XMLin(q(
  <opt>
    <anon>1</anon>
    <anon>
      <anon>2.1</anon>
      <anon>
	<anon>2.2.1</anon>
	<anon>2.2.2</anon>
      </anon>
    </anon>
  </opt>
));
ok(31, DataCompare($opt, [
  1,
  [
   '2.1', [ '2.2.1', '2.2.2']
  ]
]));


# Check for the dreaded 'content' attribute

$opt = XMLin(q(
  <opt>
    <item>text<nested key="value" /></item>
  </opt>
));
ok(32, DataCompare($opt, {
  item => {
	    content => 'text',
	    nested  => {
		         key => 'value'
	               }
          }
}));


# Confirm single nested element rolls up into a scalar attribute value

$string = q(
  <opt>
    <name>value</name>
  </opt>
);
$opt = XMLin($string);
ok(33, DataCompare($opt, {
  name => 'value'
}));


# Unless 'forcearray' option is specified

$opt = XMLin($string, forcearray => 1);
ok(34, DataCompare($opt, {
  name => [ 'value' ]
}));


# Test option error handling

$_ = eval { XMLin('<x y="z" />', rootname => 'fred') }; # not valid for XMLin()
ok(35, !defined($_));
ok(36, $@ =~ /Unrecognised option:/);

$_ = eval { XMLin('<x y="z" />', 'searchpath') };
ok(37, !defined($_));
ok(38, $@ =~ /Options must be name => value pairs .odd number supplied./);




exit(0);

