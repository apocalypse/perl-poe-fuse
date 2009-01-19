# Declare our package
package POE::Component::Fuse;
use strict; use warnings;

# Initialize our version
use vars qw( $VERSION );
$VERSION = '0.01';

# Import what we need from the POE namespace
use POE;
use POE::Session;
use POE::Wheel::Run;
use POE::Filter::Reference;
use base 'POE::Session::AttributeBased';

# Set some constants
BEGIN {
	# Debug fun!
	if ( ! defined &DEBUG ) {
		## no critic
		eval "sub DEBUG () { 0 }";
		## use critic
	}
}

# starts the component!
sub spawn {
	my $class = shift;

	# The options hash
	my %opt;

	# Support passing in a hash ref or a regular hash
	if ( ( @_ & 1 ) and ref $_[0] and ref( $_[0] ) eq 'HASH' ) {
		%opt = %{ $_[0] };
	} else {
		# Sanity checking
		if ( @_ & 1 ) {
			die 'POE::Component::Fuse requires an even number of options passed to spawn()';
		}

		%opt = @_;
	}

	# lowercase keys
	%opt = map { lc($_) => $opt{$_} } keys %opt;

	# Get the session alias
	if ( ! exists $opt{'alias'} or ! defined $opt{'alias'} ) {
		if ( DEBUG ) {
			warn 'Using default ALIAS = fuse';
		}

		# Set the default
		$opt{'alias'} = 'fuse';
	} else {
		# TODO validate for sanity
	}

	# are we using a Filesys::Virtual object?
	if ( ! exists $opt{'vfilesys'} or ! defined $opt{'vfilesys'} ) {
		if ( DEBUG ) {
			warn 'Using default VFILESYS = false';
		}

		# setup the session
		if ( ! exists $opt{'session'} or ! defined $opt{'session'} ) {
			# if we're running under POE, grab the active session
			$opt{'session'} = $poe_kernel->get_active_session();
			if ( ! defined $opt{'session'} or $opt{'session'}->isa( 'POE::Kernel' ) ) {
				die 'We need a session to send the callbacks to!';
			} else {
				$opt{'session'} = $opt{'session'}->ID();
			}
		} else {
			# TODO validate for sanity
		}

		# setup the callback prefix
		if ( ! exists $opt{'prefix'} or ! defined $opt{'prefix'} ) {
			if ( DEBUG ) {
				warn 'Using default event PREFIX = fuse_';
			}

			# Set the default
			$opt{'prefix'} = 'fuse_';
		} else {
			# TODO validate for sanity
		}
	} else {
		# make sure it's a real object
		if ( ! ref $opt{'vfilesys'} or ! $opt{'vfilesys'}->isa( 'Filesys::Virtual' ) ) {
			die 'The passed-in vfilesys object is not a subclass of Filesys::Virtual!';
		}

		# warn user if they tried to use both vfilesys+session
		if ( exists $opt{'session'} and defined $opt{'session'} ) {
			warn 'Setting both VFILESYS+SESSION will not work, choosing VFILESYS over SESSION!';
		}
		delete $opt{'session'} if exists $opt{'session'};

		# Wrap the vfilesys object around the FUSE <-> Filesys::Virtual wrapper
		require Fuse::Filesys::Virtual;
		$opt{'vfilesys'} = Fuse::Filesys::Virtual->new( $opt{'vfilesys'}, { 'debug' => DEBUG() } );
	}

	# should we automatically umount?
	if ( exists $opt{'autoumount'} ) {
		$opt{'autoumount'} = $opt{'autoumount'} ? 1 : 0;
	} else {
		if ( DEBUG ) {
			warn 'Using default AUTOUMOUNT = false';
		}

		$opt{'autoumount'} = 0;
	}

	# verify the mountpoint
	if ( ! exists $opt{'mount'} or ! defined $opt{'mount'} ) {
		if ( DEBUG ) {
			warn 'Using default MOUNT = /tmp/poefuse';
		}

		# set the default
		$opt{'mount'} = '/tmp/poefuse';
	} else {
		# TODO validate for sanity
	}

	# setup the FUSE mount options
	if ( ! exists $opt{'mountopts'} or ! defined $opt{'mountopts'} ) {
		if ( DEBUG ) {
			warn 'Using default MOUNTOPTS = undef';
		}

		# Set the default
		$opt{'mountopts'} = undef;
	} else {
		# TODO validate for sanity
	}

	# should we automatically create the mountpoint?
	if ( exists $opt{'automkdir'} ) {
		$opt{'automkdir'} = $opt{'automkdir'} ? 1 : 0;
	} else {
		if ( DEBUG ) {
			warn 'Using default AUTOMKDIR = true';
		}

		# set the default
		$opt{'automkdir'} = 1;
	}

	# make sure the mountpoint exists
	if ( ! -d $opt{'mount'} ) {
		# does it exist?
		if ( -e _ ) {
			# gaah, just let the caller know
			if ( exists $opt{'session'} ) {
				$poe_kernel->post( $opt{'session'}, $opt{'prefix'} . 'CLOSED', 'Mountpoint at ' . $opt{'mount'} . ' is not a directory!' );
			}
			return;
		} else {
			# should we try to create it?
			if ( $opt{'automkdir'} ) {
				if ( ! mkdir( $opt{'mount'} ) ) {
					# gaah, just let the caller know
					if ( exists $opt{'session'} ) {
						$poe_kernel->post( $opt{'session'}, $opt{'prefix'} . 'CLOSED', 'Unable to create directory at ' . $opt{'mount'} . ' - ' . $! );
					}
					return;
				}
			} else {
				# gaah, just let the caller know
				if ( exists $opt{'session'} ) {
					$poe_kernel->post( $opt{'session'}, $opt{'prefix'} . 'CLOSED', 'Mountpoint at ' . $opt{'mount'} . ' does not exist!' );
				}
				return;
			}
		}
	}

	# Create our session
	POE::Session->create(
		__PACKAGE__->inline_states(),
		'heap'	=>	{
			'ALIAS'		=> $opt{'alias'},
			'MOUNT'		=> $opt{'mount'},
			'MOUNTOPTS'	=> $opt{'mountopts'},
			'AUTOUMOUNT'	=> $opt{'autoumount'},
			( exists $opt{'session'} ? (	'PREFIX'	=> $opt{'prefix'},
							'SESSION'	=> $opt{'session'},
						) : (	'VFILESYS'	=> $opt{'vfilesys'}, )
			),

			# The Wheel::Run object
			'WHEEL'		=> undef,

			# Are we shutting down?
			'SHUTDOWN'	=> 0,
		},
	);

	return;
}

# This starts the component
sub _start : State {
	if ( DEBUG ) {
		warn 'Starting alias "' . $_[HEAP]->{'ALIAS'} . '"';
	}

	# Set up the alias for ourself
	$_[KERNEL]->alias_set( $_[HEAP]->{'ALIAS'} );

	# spawn the subprocess
	$_[KERNEL]->yield( 'wheel_setup' );

	# increment the refcount for calling session
	if ( exists $_[HEAP]->{'SESSION'} ) {
		$_[KERNEL]->refcount_increment( $_[HEAP]->{'SESSION'}, 'fuse' );
	}

	return;
}

# POE Handlers
sub _stop : State {
	if ( DEBUG ) {
		warn 'Stopping alias "' . $_[HEAP]->{'ALIAS'} . '"';
	}

	return;
}
sub _parent : State {
	return;
}

sub shutdown : State {
	if ( DEBUG ) {
		warn "received shutdown signal" . ( defined $_[ARG0] ? ' NOW' : '' );
	}

	# okay, let's shutdown now!
	$_[HEAP]->{'SHUTDOWN'} = 1;

	# cleanup some stuff
	$_[KERNEL]->alias_remove( $_[HEAP]->{'ALIAS'} );
	if ( defined $_[HEAP]->{'WHEEL'} ) {
		$_[HEAP]->{'WHEEL'}->pause_stdout;
		$_[HEAP]->{'WHEEL'}->pause_stderr;
		$_[HEAP]->{'WHEEL'}->kill( 9 );
		undef $_[HEAP]->{'WHEEL'};
	}

	# Do we have a session to inform?
	if ( exists $_[HEAP]->{'SESSION'} ) {
		# decrement the refcount for calling session
		$_[KERNEL]->refcount_decrement( $_[HEAP]->{'SESSION'}, 'fuse' );

		# let it know we shutdown
		if ( exists $_[HEAP]->{'ERROR'} ) {
			$_[KERNEL]->call( $_[HEAP]->{'SESSION'}, $_[HEAP]->{'PREFIX'} . 'CLOSED', $_[HEAP]->{'ERROR'} );
		} else {
			$_[KERNEL]->call( $_[HEAP]->{'SESSION'}, $_[HEAP]->{'PREFIX'} . 'CLOSED', 'shutdown' );
		}
	}

	# FIXME fire off the "fusermount -u /mnt/point" so we umount sanely
	if ( $_[HEAP]->{'AUTOUMOUNT'} ) {
		# blah
	}

	return;
}

# creates the subprocess
sub wheel_setup : State {
	if ( DEBUG ) {
		warn 'Attempting creation of SubProcess wheel now...';
	}

	# Are we shutting down?
	if ( $_[HEAP]->{'SHUTDOWN'} ) {
		# Do not re-create the wheel...
		if ( DEBUG ) {
			warn 'Hmm, we are shutting down but got setup_wheel event...';
		}
		return;
	}

	# Add the windows method
	if ( $^O eq 'MSWin32' ) {
		# make sure we load the subprocess
		require POE::Component::Fuse::SubProcess;

		# Set up the SubProcess we communicate with
		$_[HEAP]->{'WHEEL'} = POE::Wheel::Run->new(
			# What we will run in the separate process
			'Program'	=>	\&POE::Component::Fuse::SubProcess::main(),

			# Kill off existing FD's
			'CloseOnCall'	=>	0,

			# events
			'ErrorEvent'	=>	'wheel_error',
			'CloseEvent'	=>	'wheel_close',
			'StdoutEvent'	=>	'wheel_stdout',
			'StderrEvent'	=>	'wheel_stderr',

			# Set our filters
			'StdinFilter'	=>	POE::Filter::Reference->new(),		# Communicate with child via Storable::nfreeze
			'StdoutFilter'	=>	POE::Filter::Reference->new(),		# Receive input via Storable::nfreeze
			'StderrFilter'	=>	POE::Filter::Line->new(),		# Plain ol' error lines
		);
	} else {
		# Set up the SubProcess we communicate with
		$_[HEAP]->{'WHEEL'} = POE::Wheel::Run->new(
			# What we will run in the separate process
			'Program'	=>	"$^X -MPOE::Component::Fuse::SubProcess -e 'POE::Component::Fuse::SubProcess::main()'",

			# Kill off existing FD's
			'CloseOnCall'	=>	1,

			# events
			'ErrorEvent'	=>	'wheel_error',
			'CloseEvent'	=>	'wheel_close',
			'StdoutEvent'	=>	'wheel_stdout',
			'StderrEvent'	=>	'wheel_stderr',

			# Set our filters
			'StdinFilter'	=>	POE::Filter::Reference->new(),		# Communicate with child via Storable::nfreeze
			'StdoutFilter'	=>	POE::Filter::Reference->new(),		# Receive input via Storable::nfreeze
			'StderrFilter'	=>	POE::Filter::Line->new(),		# Plain ol' error lines
		);
	}

	# Check for errors
	if ( ! defined $_[HEAP]->{'WHEEL'} ) {
		# flag the error
		$_[HEAP]->{'ERROR'} = 'Unable to create the FUSE subprocess';

		# shut ourself down
		$_[KERNEL]->yield( 'shutdown' );
	} else {
		# smart CHLD handling
		if ( $_[KERNEL]->can( 'sig_child' ) ) {
			$_[KERNEL]->sig_child( $_[HEAP]->{'WHEEL'}->PID => 'Wheel_CHLD' );
		} else {
			$_[KERNEL]->sig( 'CHLD' => 'Wheel_CHLD' );
		}

		# push the data the subprocess needs to initialize
		$_[HEAP]->{'WHEEL'}->put( {
			'ACTION'	=> 'INIT',
			'MOUNT'		=> $_[HEAP]->{'MOUNT'},
			'MOUNTOPTS'	=> $_[HEAP]->{'MOUNTOPTS'},
		} );
	}
}

sub wheel_error : State {
	if ( DEBUG ) {
		my( $rv, $errno, $error, $id, $handle ) = @_[ ARG0 .. ARG4 ];
		warn "wheel error: $rv - $errno - $error - $id - $handle";
	}

	return;
}

sub wheel_close : State {
	# was this expected?
	if ( ! $_[HEAP]->{'SHUTDOWN'} ) {
		# set the error flag
		$_[HEAP]->{'ERROR'} = 'FUSE closed on us ( possibly umounted )';
	}

	# arg, cleanup!
	$_[KERNEL]->call( $_[SESSION], 'shutdown' );

	return;
}

sub wheel_stderr : State {
	my $line = $_[ARG0];

	# skip empty lines
	if ( $line ne '' ) {
		if ( DEBUG ) {
			warn "received stderr from subprocess: $line";
		}
	}

	return;
}

sub wheel_stdout : State {
	my $data = $_[ARG0];

	if ( defined $data and ref $data and ref( $data ) eq 'HASH' ) {
		if ( DEBUG ) {
			require Data::Dumper;
			warn "received from subprocess: " . Data::Dumper::Dumper( $data );
		}

		# TODO generate some way of matching request with response when we go multithreaded...

		# vfilesys or session?
		if ( exists $_[HEAP]->{'SESSION'} ) {
			# make the postback
			my $postback = $_[SESSION]->postback( 'reply', $data->{'TYPE'} );

			# send it to the session!
			$_[KERNEL]->post( $_[HEAP]->{'SESSION'}, $_[HEAP]->{'PREFIX'} . $data->{'TYPE'}, $postback, $data->{'CONTEXT'}, @{ $data->{'ARGS'} } );
		} else {
			# send it to the wrapper!
			my $subname = $_[HEAP]->{'VFILESYS'}->can( $data->{'TYPE'} );
			my @result;
			if ( defined $subname ) {
				@result = $subname->( $_[HEAP]->{'VFILESYS'}, @{ $data->{'ARGS'} } );
			} else {
				@result = ( 0 );	# FIXME: change to EPERM or something
			}
			$_[KERNEL]->yield( 'reply', [ $data->{'TYPE'} ], \@result );
		}
	} else {
		if ( DEBUG ) {
			warn "received malformed input from subprocess";
		}
	}

	return;
}

sub reply : State {
	my( $orig_data, $result ) = @_[ ARG0 .. ARG2 ];

	# send it down the pipe!
	if ( defined $_[HEAP]->{'WHEEL'} ) {
		# build the data struct
		my $data = {
			'ACTION'	=> 'REPLY',
			'TYPE'		=> $orig_data->[0],
			'RESULT'	=> $result,
		};

		if ( DEBUG ) {
			require Data::Dumper;
			warn "sending to subprocess: " . Data::Dumper::Dumper( $data );
		}

		# capture it in an eval block - sometimes the wheel disappears!
		eval {
			$_[HEAP]->{'WHEEL'}->put( $data );
		};
		if ( DEBUG and $@ ) {
			warn "error sending to subprocess: $@";
		}
	} else {
		if ( DEBUG ) {
			warn "wheel disappeared, unable to send reply!";
		}
	}

	return;
}

1;
__END__
=head1 NAME

POE::Component::Fuse - Using FUSE in POE asynchronously

=head1 SYNOPSIS

	#!/usr/bin/perl
	# a simple example to illustrate directory listings
	use strict; use warnings;

	use POE qw( Component::Fuse );
	use base 'POE::Session::AttributeBased';

	# constants we need to interact with FUSE
	use Errno qw( :POSIX );		# ENOENT EISDIR etc

	my %files = (
		'/' => {	# a directory
			type => 0040,
			mode => 0755,
			ctime => time()-1000,
		},
		'/a' => {	# a file
			type => 0100,
			mode => 0644,
			ctime => time()-2000,
		},
		'/foo' => {	# a directory
			type => 0040,
			mode => 0755,
			ctime => time()-3000,
		},
		'/foo/bar' => {	# a file
			type => 0100,
			mode => 0755,
			ctime => time()-4000,
		},
	);

	POE::Session->create(
		__PACKAGE__->inline_states(),
	);

	POE::Kernel->run();
	exit;

	sub _start : State {
		# create the fuse session
		POE::Component::Fuse->spawn;
		print "Check us out at the default place: /tmp/poefuse\n";
		print "You can do directory listings, but no I/O operations are supported!\n";
	}
	sub _child : State {
		return;
	}
	sub _stop : State {
		return;
	}

	sub fuse_CLOSED : State {
		print "shutdown: $_[ARG0]\n";
		return;
	}

	sub fuse_getattr : State {
		my( $postback, $context, $path ) = @_[ ARG0 .. ARG2 ];

		if ( exists $files{ $path } ) {
			my $size = exists( $files{ $path }{'cont'} ) ? length( $files{ $path }{'cont'} ) : 0;
			$size = $files{ $path }{'size'} if exists $files{ $path }{'size'};
			my $modes = ( $files{ $path }{'type'} << 9 ) + $files{ $path }{'mode'};
			my ($dev, $ino, $rdev, $blocks, $gid, $uid, $nlink, $blksize) = ( 0, 0, 0, 1, (split( /\s+/, $) ))[0], $>, 1, 1024 );
			my ($atime, $ctime, $mtime);
			$atime = $ctime = $mtime = $files{ $path }{'ctime'};

			# finally, return the darn data!
			$postback->( $dev, $ino, $modes, $nlink, $uid, $gid, $rdev, $size, $atime, $mtime, $ctime, $blksize, $blocks );
		} else {
			# path does not exist
			$postback->( -ENOENT() );
		}

		return;
	}

	sub fuse_getdir : State {
		my( $postback, $context, $path ) = @_[ ARG0 .. ARG2 ];

		if ( exists $files{ $path } ) {
			if ( $files{ $path }{'type'} & 0040 ) {
				# construct all the data in this directory
				my @list = map { $_ =~ s/^$path\/?//; $_ }
					grep { $_ =~ /^$path\/?[^\/]+$/ } ( keys %files );

				# no need to add "." and ".." - FUSE handles it automatically!

				# return the list with a success code on the end
				$postback->( @list, 0 );
			} else {
				# path is not a directory!
				$postback->( -ENOTDIR() );
			}
		} else {
			# path does not exist!
			$postback->( -ENOENT() );
		}

		return;
	}

	sub fuse_getxattr : State {
		my( $postback, $context, $path, $attr ) = @_[ ARG0 .. ARG3 ];

		# we don't have any extended attribute support
		$postback->( 0 );

		return;
	}

=head1 ABSTRACT

Using this module will enable you to asynchronously process FUSE requests from the kernel in POE. Think of
this module as a simple wrapper around L<Fuse> to POEify it.

=head1 DESCRIPTION

MISSING! ALERT ALERT ALERT!

=head1 EXPORT

None.

=head1 SEE ALSO

L<POE>

L<Fuse>

L<Filesys::Virtual>

=head1 SUPPORT

You can find documentation for this module with the perldoc command.

    perldoc POE::Component::Fuse

You can also look for information at:

=over 4

=item * AnnoCPAN: Annotated CPAN documentation

L<http://annocpan.org/dist/POE-Component-Fuse>

=item * CPAN Ratings

L<http://cpanratings.perl.org/d/POE-Component-Fuse>

=item * RT: CPAN's request tracker

L<http://rt.cpan.org/NoAuth/Bugs.html?Dist=POE-Component-Fuse>

=item * Search CPAN

L<http://search.cpan.org/dist/POE-Component-Fuse>

=back

=head1 AUTHOR

Apocalypse E<lt>apocal@cpan.orgE<gt>

Props goes to xantus who got me motivated to write this :)

Also, this module couldn't have gotten off the ground if not for L<Fuse> which did the heavy XS lifting!

=head1 COPYRIGHT AND LICENSE

Copyright 2009 by Apocalypse

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.

=cut
