use strict;
use IO::File;
use File::Spec;

# Initialise filenames and check they're there

my $XMLFile = File::Spec->catfile('t', 'test1.xml');  # t/test1.xml

unless(-e $XMLFile) {
  print STDERR "test data missing...";
  print "1..0\n";
  exit 0;
}


print "1..46\n";

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
  $x = 0 if(@_ > 2  and  $x ne $y);
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
    return(1) if($x eq $y);
    print STDERR "$t:DataCompare: $x != $y\n";
    return(0);
  }

  if(ref($x) eq 'ARRAY') {
    unless(ref($y) eq 'ARRAY') {
      print STDERR "$t:DataCompare: expected arrayref, got: $y\n";
      return(0);
    }
    if(scalar(@$x) != scalar(@$y)) {
      print STDERR "$t:DataCompare: expected ", scalar(@$x),
                   " element(s), got: ", scalar(@$y), "\n";
      return(0);
    }
    for($i = 0; $i < scalar(@$x); $i++) {
      DataCompare($x->[$i], $y->[$i]) || return(0);
    }
    return(1);
  }

  if(ref($x) eq 'HASH') {
    unless(ref($y) eq 'HASH') {
      print STDERR "$t:DataCompare: expected hashref, got: $y\n";
      return(0);
    }
    if(scalar(keys(%$x)) != scalar(keys(%$y))) {
      print STDERR "$t:DataCompare: expected ", scalar(keys(%$x)),
                   " key(s), (", join(', ', keys(%$x)),
		   ") got: ",  scalar(keys(%$y)), " (", join(', ', keys(%$y)),
		   ")\n";
      return(0);
    }
    foreach $i (keys(%$x)) {
      unless(exists($y->{$i})) {
	print STDERR "$t:DataCompare: missing hash key - {$i}\n";
	return(0);
      }
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

eval "use XML::Simple;";
ok(1, !$@);                       # Module compiled OK
unless($XML::Simple::VERSION eq '1.03') {
  print STDERR "WARNING: XML::Simple::VERSION = $XML::Simple::VERSION (expected 1.03)...";
}


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
my $target = {
  item => {
            item1 => { attr1 => 'value1', attr2 => 'value2' },
            item2 => { attr1 => 'value3', attr2 => 'value4' }
	  }
};
$opt = XMLin($string);
ok(11, DataCompare($opt, $target));


# Same thing left as an array by suppressing default key names

$target = {
  item => [
            {name => 'item1', attr1 => 'value1', attr2 => 'value2' },
            {name => 'item2', attr1 => 'value3', attr2 => 'value4' }
	  ]
};
$opt = XMLin($string, keyattr => [] );
ok(12, DataCompare($opt, $target));


# Same again with alternative key suppression

$opt = XMLin($string, keyattr => {} );
ok(13, DataCompare($opt, $target));


# Try the other two default key attribute names

$opt = XMLin(q(
  <opt> 
    <item key="item1" attr1="value1" attr2="value2" />
    <item key="item2" attr1="value3" attr2="value4" />
  </opt>
));
ok(14, DataCompare($opt, {
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
ok(15, DataCompare($opt, {
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

$target = {
  item => {
            item1 => { attr1 => 'value1', attr2 => 'value2' },
            item2 => { attr1 => 'value3', attr2 => 'value4' }
	  }
};

$opt = XMLin($xml, keyattr => [qw(xname)]);
ok(16, DataCompare($opt, $target));


# And with precise element/key specification

$opt = XMLin($xml, keyattr => { 'item' => 'xname' });
ok(17, DataCompare($opt, $target));


# Same again but with key field further down the list

$opt = XMLin($xml, keyattr => [qw(wibble xname)]);
ok(18, DataCompare($opt, $target));


# Same again but with key field supplied as scalar

$opt = XMLin($xml, keyattr => qw(xname));
ok(19, DataCompare($opt, $target));


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
ok(20, DataCompare($opt, $target));


# Or somewhat more as one might expect

$target = { item => {
    'one'   => { 'value' => '1', 'name' => 'a' },
    'two'   => { 'value' => '2' },
    'three' => { 'value' => '3' },
  }
};
$opt = XMLin($xml, keyattr => { 'item' => 'id' });
ok(21, DataCompare($opt, $target));


# Now a somewhat more complex test of targetting folding

$xml = q(
<opt>
  <car license="SH6673" make="Ford" id="1">
    <option key="1" pn="6389733317-12" desc="Electric Windows"/>
    <option key="2" pn="3735498158-01" desc="Leather Seats"/>
    <option key="3" pn="5776155953-25" desc="Sun Roof"/>
  </car>
  <car license="LW1804" make="GM"   id="2">
    <option key="1" pn="9926543-1167" desc="Steering Wheel"/>
  </car>
</opt>
);

$target = {
  'car' => {
    'LW1804' => {
      'id' => 2,
      'make' => 'GM',
      'option' => {
	  '9926543-1167' => { 'key' => 1, 'desc' => 'Steering Wheel' }
      }
    },
    'SH6673' => {
      'id' => 1,
      'make' => 'Ford',
      'option' => {
	  '6389733317-12' => { 'key' => 1, 'desc' => 'Electric Windows' },
	  '3735498158-01' => { 'key' => 2, 'desc' => 'Leather Seats' },
	  '5776155953-25' => { 'key' => 3, 'desc' => 'Sun Roof' }
      }
    }
  }
};

$opt = XMLin($xml, forcearray => 1, keyattr => { 'car' => 'license', 'option' => 'pn' });
ok(22, DataCompare($opt, $target));


# Now try leaving the keys in place

$target = {
  'car' => {
    'LW1804' => {
      'id' => 2,
      'make' => 'GM',
      'option' => {
	  '9926543-1167' => { 'key' => 1, 'desc' => 'Steering Wheel',
	                      '-pn' => '9926543-1167' }
      },
      license => 'LW1804'
    },
    'SH6673' => {
      'id' => 1,
      'make' => 'Ford',
      'option' => {
	  '6389733317-12' => { 'key' => 1, 'desc' => 'Electric Windows',
	                       '-pn' => '6389733317-12' },
	  '3735498158-01' => { 'key' => 2, 'desc' => 'Leather Seats',
	                       '-pn' => '3735498158-01' },
	  '5776155953-25' => { 'key' => 3, 'desc' => 'Sun Roof',
	                       '-pn' => '5776155953-25' }
      },
      license => 'SH6673'
    }
  }
};
$opt = XMLin($xml, forcearray => 1, keyattr => { 'car' => '+license', 'option' => '-pn' });
ok(23, DataCompare($opt, $target));


# Try parsing a named external file

$opt = eval{ XMLin($XMLFile); };
ok(24, !$@);                                  # XMLin didn't die
print STDERR $@ if($@);
ok(25, DataCompare($opt, {
  location => 't/test1.xml'
}));


# Try parsing default external file (scriptname.xml in script directory)

$opt = eval { XMLin(); };
print STDERR $@ if($@);
ok(26, !$@);                                  # XMLin didn't die
ok(27, DataCompare($opt, {
  location => 't/1_XMLin.xml'
}));


# Try parsing named file in a directory in the searchpath

$opt = eval {
  XMLin('test2.xml', searchpath => [
    'dir1', 'dir2', File::Spec->catdir('t', 'subdir')
  ] );

};
print STDERR $@ if($@);
ok(28, !$@);                                  # XMLin didn't die
ok(29, DataCompare($opt, { location => 't/subdir/test2.xml' }));


# Ensure we get expected result if file does not exist

$opt = eval {
  XMLin('bogusfile.xml', searchpath => [qw(. ./t)] ); # should 'die'
};
ok(30, !defined($opt));                          # XMLin failed
ok(31, $@ =~ /Could not find bogusfile.xml in/); # with the expected message


# Try parsing from an IO::Handle 

my $fh = new IO::File;
$XMLFile = File::Spec->catfile('t', '1_XMLin.xml');  # t/1_XMLin.xml
$fh->open($XMLFile);
$opt = XMLin($fh);
ok(32, 1);                                      # XMLin didn't die
ok(33, $opt->{location}, 't/1_XMLin.xml');      # and it parsed the right file


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
ok(34, DataCompare($opt, {
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
ok(35, DataCompare($opt, [
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
ok(36, DataCompare($opt, [
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
ok(37, DataCompare($opt, {
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
ok(38, DataCompare($opt, {
  name => 'value'
}));


# Unless 'forcearray' option is specified

$opt = XMLin($string, forcearray => 1);
ok(39, DataCompare($opt, {
  name => [ 'value' ]
}));


# Confirm array folding of single nested hash

$string = q(<opt>
  <inner name="one" value="1" />
</opt>);

$opt = XMLin($string, forcearray => 1);
ok(40, DataCompare($opt, {
  'inner' => { 'one' => { 'value' => 1 } }
}));


# But not without forcearray option specified

$opt = XMLin($string, forcearray => 0);
ok(41, DataCompare($opt, {
  'inner' => { 'name' => 'one', 'value' => 1 } 
}));


# Test option error handling

$_ = eval { XMLin('<x y="z" />', rootname => 'fred') }; # not valid for XMLin()
ok(42, !defined($_));
ok(43, $@ =~ /Unrecognised option:/);

$_ = eval { XMLin('<x y="z" />', 'searchpath') };
ok(44, !defined($_));
ok(45, $@ =~ /Options must be name => value pairs .odd number supplied./);


# Now for a 'real world' test, try slurping in an SRT config file

$opt = XMLin(File::Spec->catfile('t', 'srt.xml'), forcearray => 1);
$target = {
  'global' => [
    {
      'proxypswd' => 'bar',
      'proxyuser' => 'foo',
      'exclude' => [
        '/_vt',
        '/save\\b',
        '\\.bak$',
        '\\.\\$\\$\\$$'
      ],
      'httpproxy' => 'http://10.1.1.5:8080/',
      'tempdir' => 'C:/Temp'
    }
  ],
  'pubpath' => {
    'test1' => {
      'source' => [
        {
          'label' => 'web_source',
          'root' => 'C:/webshare/web_source'
        }
      ],
      'title' => 'web_source -> web_target1',
      'package' => {
        'images' => { 'dir' => 'wwwroot/images' }
      },
      'target' => [
        {
          'label' => 'web_target1',
          'root' => 'C:/webshare/web_target1',
          'temp' => 'C:/webshare/web_target1/temp'
        }
      ],
      'dir' => [ 'wwwroot' ]
    },
    'test2' => {
      'source' => [
        {
          'label' => 'web_source',
          'root' => 'C:/webshare/web_source'
        }
      ],
      'title' => 'web_source -> web_target1 & web_target2',
      'package' => {
        'bios' => { 'dir' => 'wwwroot/staff/bios' },
        'images' => { 'dir' => 'wwwroot/images' },
        'templates' => { 'dir' => 'wwwroot/templates' }
      },
      'target' => [
        {
          'label' => 'web_target1',
          'root' => 'C:/webshare/web_target1',
          'temp' => 'C:/webshare/web_target1/temp'
        },
        {
          'label' => 'web_target2',
          'root' => 'C:/webshare/web_target2',
          'temp' => 'C:/webshare/web_target2/temp'
        }
      ],
      'dir' => [ 'wwwroot' ]
    },
    'test3' => {
      'source' => [
        {
          'label' => 'web_source',
          'root' => 'C:/webshare/web_source'
        }
      ],
      'title' => 'web_source -> web_target1 via HTTP',
      'addexclude' => [ '\\.pdf$' ],
      'target' => [
        {
          'label' => 'web_target1',
          'root' => 'http://127.0.0.1/cgi-bin/srt_slave.plx',
          'noproxy' => 1
        }
      ],
      'dir' => [ 'wwwroot' ]
    }
  }
};
ok(46, DataCompare($target, $opt));


exit(0);

