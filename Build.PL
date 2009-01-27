# Build.PL
use Module::Build;

my $ver = `fusermount -V 2>&1`;
my $ver2 = `mount_fusefs -V 2>&1`;
my $ver3 = `mount_fusefs -V 2>&1 | head -n1`;
chomp $ver if defined $ver; chomp $ver2 if defined $ver2; chomp $ver3 if defined $ver3;
$ver =~ s/^.*?version:\s+// if defined $ver;
$ver2 =~ s/^.*?version:\s+// if defined $ver2;
$ver3 =~ s/^.*?version\s+// if defined $ver3;
if (! $ver && ! $ver2 && ! $ver3) {
	# make CPANPLUS happy and don't report errors if fuse isn't installed
	warn("No support for os: $^O\n",
		"You need to have fuse-dev (or similar) package installed and have sufficient permissions in order to install this module\n",
		$^O eq 'darwin' ? ("One option on Mac is http://code.google.com/p/macfuse/\n") : (),
	);
	exit 0;
}
if ($ver && $ver + 0 < 2.5) {
	warn "Fuse perl bindings need Linux fuse version 2.5 or newer\n";
	exit 0;
} elsif ($ver2 && $ver2 + 0 < 0.3) {
	warn "Fuse perl bindings need FreeBSD fuse version 0.3 or newer\n";
	exit 0;
} elsif ($^O eq 'darwin' && $ver3 && !(($ver3 ge "0.1.0b006") || ($ver3 eq "0.1.0"))) {
	# the "ge" string-compare check will match all later revs and all later
	# betas, but not the final release of the current rev (0.1.0).
	warn "Fuse perl bindings need MacFUSE version 0.1.0b006 or newer, your version is \"$ver3\"\n";
	exit 0;
} else {
	warn "fuse version found: ", $ver || $ver2 || $ver3, "\n";
}

my $inc = '-DFUSE_USE_VERSION=25 ' . `pkg-config --cflags fuse` || '-I ../include -D_FILE_OFFSET_BITS=64';
my $obj = `pkg-config --libs fuse` || '-lfuse';
$inc .= '-Wall -g -ggdb';
$inc .= ' -D__FreeBSD__=10 -D_FILE_OFFSET_BITS=64' if $^O eq 'darwin';

my $build = Module::Build->new(
	# look up Module::Build::API for the info!
	'dynamic_config'	=> 0,
	'module_name'		=> 'POE::Component::Fuse',
	'license'		=> 'perl',

	'dist_abstract'		=> "Using FUSE in POE",
	'dist_author'		=> 'Apocalypse <APOCAL@cpan.org>',

	'create_packlist'	=> 1,
	'create_makefile_pl'	=> 'traditional',
	'create_readme'		=> 1,

	'test_files'		=> 't/*.t',

	'add_to_cleanup'	=> [ 'META.yml', 'Makefile.PL', 'README' ],	# automatically generated

	'build_requires'	=> {
		# Test stuff
		'Test::More'			=> '0.86',	# require latest for note() support in t/a_is_prereq_outdated.t
	},

	# set our XS stuff
	'extra_compiler_flags'	=> $inc,
	'extra_linker_flags'	=> $obj,

	'requires'		=> {
		# POE Stuff
		'POE'				=> 0,
		'POE::Session::AttributeBased'	=> 0,

		# FIXME POE stuff that Test::Dependencies needs to see
		'POE::Session'			=> 0,
		'POE::Wheel::Run'		=> 0,
		'POE::Filter::Reference'	=> 0,

		# system constants
		'Errno'				=> 0,
		'Fcntl'				=> 0,
		'Config'			=> 0,
		'Carp'				=> 0,
		'DynaLoader'			=> 0,

		# to find out stuff about $fh
		'Scalar::Util'			=> 0,
	},

	'recommends'		=> {
		# Filesys::Virtual wrapper
		'Fuse::Filesys::Virtual'	=> 0,

		# Async stuff for better integration with POE
		'Filesys::Virtual::Async'	=> 0,
		'POE::Component::AIO'		=> 0,
	},

	# FIXME wishlist...
#	'test_requires'		=> {
#		# Test stuff
#		'Test::Compile'		=> 0,
#		'Test::Perl::Critic'	=> 0,
#		'Test::Dependencies'	=> 0,
#		'Test::Distribution'	=> 0,
#		'Test::Fixme'		=> 0,
#		'Test::HasVersion'	=> 0,
#		'Test::Kwalitee'	=> 0,
#		'Test::CheckManifest'	=> 0,
#		'Test::MinimumVersion'	=> 0,
#		'Test::Pod::Coverage'	=> 0,
#		'Test::Spelling'	=> 0,
#		'Test::Pod'		=> 0,
#		'Test::Prereq'		=> 0,
#		'Test::Strict'		=> 0,
#		'Test::UseAllModules'	=> 0,
#		'Test::YAML::Meta'	=> 0,
#	},
);

# all done!
$build->create_build_script;
