#!/usr/bin/perl
# shamelessly adapted+expanded from Fuse.pm's examples/example.pl
# hmpf, using nano works fine but vi bombs out with this!
# must be some file mode thingy, have to investigate later... :)
use strict; use warnings;

# uncomment this to have debugging
#sub POE::Component::Fuse::DEBUG { 1 }

use POE;
use POE::Component::Fuse;
use base 'POE::Session::AttributeBased';

use Errno qw( :POSIX );		# ENOENT EISDIR etc
use Fcntl qw( :DEFAULT :mode );	# S_IFREG S_IFDIR, O_SYNC O_LARGEFILE etc

my %files = (
	'/' => {
		type => 0040,
		mode => 0755,
		ctime => time()-1000,
	},
	'/a' => {
		cont => "File 'a'.\n",
		type => 0100,
		mode => 0755,
		ctime => time()-2000,
	},
	'/b' => {
		cont => "This is file 'b'.\n",
		type => 0100,
		mode => 0644,
		ctime => time()-1000,
	},
	'/foo' => {
		type => 0040,
		mode => 0755,
		ctime => time()-3000,
	},
	'/foo/bar' => {
		cont => "APOCAL is the best!\nJust kidding :)",
		type => 0100,
		mode => 0755,
		ctime => time()-5000,
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
	print "This is an entirely in-memory filesystem, some things might not work.\n";
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
	#print "GETATTR: '$path'\n";

	if ( exists $files{ $path } ) {
		my $size = exists( $files{ $path }{'cont'} ) ? length( $files{ $path }{'cont'} ) : 0;
		$size = $files{ $path }{'size'} if exists $files{ $path }{'size'};
		my $modes = ( $files{ $path }{'type'} << 9 ) + $files{ $path }{'mode'};
		my ($dev, $ino, $rdev, $blocks, $gid, $uid, $nlink, $blksize) = ( 0, 0, 0, 1, (split( /\s+/, $) ))[0], $>, 1, 1024 );
		$gid = $files{ $path }{'gid'} if exists $files{ $path }{'gid'};
		$uid = $files{ $path }{'uid'} if exists $files{ $path }{'uid'};
		my ($atime, $ctime, $mtime);
		$atime = $ctime = $mtime = $files{ $path }{'ctime'};
		$atime = $files{ $path }{'atime'} if exists $files{ $path }{'atime'};
		$mtime = $files{ $path }{'mtime'} if exists $files{ $path }{'mtime'};

		# finally, return the darn data!
		$postback->( $dev, $ino, $modes, $nlink, $uid, $gid, $rdev, $size, $atime, $mtime, $ctime, $blksize, $blocks );
	} else {
		# path does not exist
		$postback->( -ENOENT() );
	}

	return;
}

sub fuse_readlink : State {
	my( $postback, $context, $path ) = @_[ ARG0 .. ARG2 ];
	#print "READLINK: '$path'\n";

	# we don't have any link support
	$postback->( -ENOSYS() );

	return;
}

sub fuse_getdir : State {
	my( $postback, $context, $path ) = @_[ ARG0 .. ARG2 ];
	#print "GETDIR: '$path'\n";

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
	#print "GETXATTR: '$path' - '$attr'\n";

	# we don't have any extended attribute support
	$postback->( 0 );

	return;
}

sub fuse_setxattr : State {
	my( $postback, $context, $path, $attr, $value, $flags ) = @_[ ARG0 .. ARG5 ];
	#print "SETXATTR: '$path' - '$attr' - '$value' - '$flags'\n";

	# we don't have any extended attribute support
	$postback->( -ENOSYS() );

	return;
}

sub fuse_listxattr : State {
	my( $postback, $context, $path ) = @_[ ARG0 .. ARG2 ];
	#print "LISTXATTR: '$path'\n";

	# we don't have any extended attribute support
	$postback->( 0 );

	return;
}

sub fuse_removexattr : State {
	my( $postback, $context, $path, $attr ) = @_[ ARG0 .. ARG3 ];
	#print "REMOVEXATTR: '$path' - '$attr'\n";

	# we don't have any extended attribute support
	$postback->( 0 );

	return;
}

sub fuse_open : State {
	my( $postback, $context, $path, $flags ) = @_[ ARG0 .. ARG3 ];
	#print "OPEN: '$path' - " . dump_open_flags( $flags );

	if ( exists $files{ $path } ) {
		unless ( $files{ $path }{'type'} & 0040 ) {
			# accept the open! ( we ignore the flags for now )
			$postback->( 0 );
		} else {
			# path is a directory!
			$postback->( -EISDIR() );
		}
	} else {
		# path does not exist
		$postback->( -ENOENT() );
	}

	return;
}

sub fuse_read : State {
	my( $postback, $context, $path, $size, $offset ) = @_[ ARG0 .. ARG4 ];
	#print "READ: '$path' - '$size' - '$offset'\n";

	if ( exists $files{ $path } ) {
		unless ( $files{ $path }{'type'} & 0040 ) {
			# valid file, proceed with the read!

			# sanity check, offset cannot be bigger than the length of the file!
			if ( $offset > length( $files{ $path }{'cont'} ) ) {
				$postback->( -EINVAL() );
			} else {
				# did we reach the end of the file?
				if ( $offset == length( $files{ $path }{'cont'} ) ) {
					$postback->( 0 );
				} else {
					# phew, return the data!
					$postback->( substr( $files{ $path }{'cont'}, $offset, $size ) );
				}
			}
		} else {
			# path is a directory!
			$postback->( -EISDIR() );
		}
	} else {
		# path does not exist
		$postback->( -ENOENT() );
	}

	return;
}

sub fuse_flush : State {
	my( $postback, $context, $path ) = @_[ ARG0 .. ARG2 ];
	#print "FLUSH: '$path'\n";

	if ( exists $files{ $path } ) {
		unless ( $files{ $path }{'type'} & 0040 ) {
			# allow flushing of a file ( we don't track state so who cares, ha! )
			$postback->( 0 );
		} else {
			# path is a directory!
			$postback->( -EISDIR() );
		}
	} else {
		# path does not exist
		$postback->( -ENOENT() );
	}

	return;
}

sub fuse_release : State {
	my( $postback, $context, $path, $flags ) = @_[ ARG0 .. ARG3 ];
	#print "RELEASE: '$path' - " . dump_open_flags( $flags );

	if ( exists $files{ $path } ) {
		unless ( $files{ $path }{'type'} & 0040 ) {
			# allow releasing of a file ( we don't track state so who cares, ha! )
			$postback->( 0 );
		} else {
			# path is a directory!
			$postback->( -EISDIR() );
		}
	} else {
		# path does not exist
		$postback->( -ENOENT() );
	}

	return;
}

sub fuse_truncate : State {
	my( $postback, $context, $path, $offset ) = @_[ ARG0 .. ARG3 ];
	#print "TRUNCATE: '$path' - '$offset'\n";

	if ( exists $files{ $path } ) {
		unless ( $files{ $path }{'type'} & 0040 ) {
			# valid file, proceed with the truncate!

			# sanity check, offset cannot be bigger than the length of the file!
			if ( $offset > length( $files{ $path }{'cont'} ) ) {
				$postback->( -EINVAL() );
			} else {
				# did we reach the end of the file?
				if ( $offset != length( $files{ $path }{'cont'} ) ) {
					# ok, truncate our copy!
					$files{ $path }{'cont'} = substr( $files{ $path }{'cont'}, 0, $offset );
				}

				# successfully truncated
				$postback->( 0 );
			}
		} else {
			# path is a directory!
			$postback->( -EISDIR() );
		}
	} else {
		# path does not exist
		$postback->( -ENOENT() );
	}

	return;
}

sub fuse_write : State {
	my( $postback, $context, $path, $buffer, $offset ) = @_[ ARG0 .. ARG4 ];
	#print "WRITE: '$path' - '" . length( $buffer ) . "' - '$offset'\n";

	if ( exists $files{ $path } ) {
		unless ( $files{ $path }{'type'} & 0040 ) {
			# valid file, proceed with the write!

			# sanity check, offset cannot be bigger than the length of the file!
			if ( $offset > length( $files{ $path }{'cont'} ) ) {
				$postback->( -EINVAL() );
			} else {
				# save the buffer!
				substr( $files{ $path }{'cont'}, $offset, length( $buffer ), $buffer );

				# successfully wrote the data!
				$postback->( length( $buffer ) );
			}
		} else {
			# path is a directory!
			$postback->( -EISDIR() );
		}
	} else {
		# path does not exist
		$postback->( -ENOENT() );
	}

	return;
}

sub fuse_mknod : State {
	my( $postback, $context, $path, $modes, $device ) = @_[ ARG0 .. ARG4 ];

	# cleanup the mode ( for some reason we get '100644' instead of '0644' )
	# FIXME this seems to also screw up the S_ISREG() stuff, have to investigate more...
	$modes = $modes & 000777;

	#print "MKNOD: '$path' - '" . sprintf( "%04o", $modes ) . "' - '$device'\n";

	if ( exists $files{ $path } or $path eq '.' or $path eq '..' ) {
		# already exists!
		$postback->( -EEXIST() );
	} else {
		# should we add validation to make sure all parents already exist
		# seems like touch() and friends check themselves, so we don't have to do it...

		# we only allow regular files to be created
		if ( $device == 0 ) {
			$files{ $path } = {
				type => 0100,
				mode => $modes,
				ctime => time(),
				cont => "",
			};

			# successful creation!
			$postback->( 0 );
		} else {
			# unsupported mode
			$postback->( -EINVAL() );
		}
	}

	return;
}

sub fuse_mkdir : State {
	my( $postback, $context, $path, $modes ) = @_[ ARG0 .. ARG3 ];
	#print "MKDIR: '$path' - '" . sprintf( "%04o", $modes ) . "'\n";

	if ( exists $files{ $path } ) {
		# already exists!
		$postback->( -EEXIST() );
	} else {
		# should we add validation to make sure all parents already exist
		# seems like mkdir() and friends check themselves, so we don't have to do it...

		# create the directory!
		$files{ $path } = {
			type => 0040,
			mode => $modes,
			ctime => time(),
		};

		# successful creation!
		$postback->( 0 );
	}

	return;
}

sub fuse_unlink : State {
	my( $postback, $context, $path ) = @_[ ARG0 .. ARG2 ];
	#print "UNLINK: '$path'\n";

	if ( exists $files{ $path } ) {
		unless ( $files{ $path }{'type'} & 0040 ) {
			# valid file, proceed with the deletion!
			delete $files{ $path };

			# successful deletion!
			$postback->( 0 );
		} else {
			# path is a directory!
			$postback->( -EISDIR() );
		}
	} else {
		# path does not exist
		$postback->( -ENOENT() );
	}

	return;
}

sub fuse_rmdir : State {
	my( $postback, $context, $path ) = @_[ ARG0 .. ARG2 ];
	#print "RMDIR: '$path'\n";

	if ( exists $files{ $path } ) {
		if ( $files{ $path }{'type'} & 0040 ) {
			# valid directory, does this directory have any children ( files, subdirs ) ??
			my $children = grep { $_ =~ /^$path/ } ( keys %files );
			if ( $children == 1 ) {
				delete $files{ $path };

				# successful deletion!
				$postback->( 0 );
			} else {
				# need to delete children first!
				$postback->( -ENOTEMPTY() );
			}
		} else {
			# path is not a directory!
			$postback->( -ENOTDIR() );
		}
	} else {
		# path does not exist
		$postback->( -ENOENT() );
	}

	return;
}

sub fuse_symlink : State {
	my( $postback, $context, $path, $symlink ) = @_[ ARG0 .. ARG3 ];
	#print "SYMLINK: '$path' - '$symlink'\n";

	# we simply don't support this operation because it would be too complicated for this "basic" script, ha!
	$postback->( -ENOSYS() );

	return;
}

sub fuse_rename : State {
	my( $postback, $context, $path, $newpath ) = @_[ ARG0 .. ARG3 ];
	#print "RENAME: '$path' - '$newpath'\n";

	if ( exists $files{ $path } ) {
		if ( ! exists $files{ $newpath } ) {
			# should we add validation to make sure all parents already exist
			# seems like mv() and friends check themselves, so we don't have to do it...

			# proceed with the rename!
			$files{ $newpath } = delete $files{ $path };

			$postback->( 0 );
		} else {
			# destination already exists!
			$postback->( -EEXIST() );
		}
	} else {
		# path does not exist
		$postback->( -ENOENT() );
	}

	return;
}

sub fuse_link : State {
	my( $postback, $context, $path, $hardlink ) = @_[ ARG0 .. ARG3 ];
	#print "LINK: '$path' - '$hardlink'\n";

	# we simply don't support this operation because it would be too complicated for this "basic" script, ha!
	$postback->( -ENOSYS() );

	return;
}

sub fuse_chmod : State {
	my( $postback, $context, $path, $modes ) = @_[ ARG0 .. ARG3 ];
	#print "CHMOD: '$path' - '" . sprintf( "%04o", $modes ) . "'\n";

	if ( exists $files{ $path } ) {
		# okay, update the mode!
		$files{ $path }{'mode'} = $modes;

		# successful update of mode!
		$postback->( 0 );
	} else {
		# path does not exist
		$postback->( -ENOENT() );
	}

	return;
}

sub fuse_chown : State {
	my( $postback, $context, $path, $uid, $gid ) = @_[ ARG0 .. ARG4 ];
	#print "CHOWN: '$path' - '$uid' - '$gid'\n";

	if ( exists $files{ $path } ) {
		# okay, update the ownerships!!
		$files{ $path }{'uid'} = $uid;
		$files{ $path }{'gid'} = $gid;

		# successful update of ownership!
		$postback->( 0 );
	} else {
		# path does not exist
		$postback->( -ENOENT() );
	}

	return;
}

sub fuse_utime : State {
	my( $postback, $context, $path, $atime, $mtime ) = @_[ ARG0 .. ARG4 ];
	#print "UTIME: '$path' - '$atime' - '$mtime'\n";

	if ( exists $files{ $path } ) {
		# okay, update the time
		$files{ $path }{'atime'} = $atime;
		$files{ $path }{'mtime'} = $mtime;

		# successful update of time!
		$postback->( 0 );
	} else {
		# path does not exist
		$postback->( -ENOENT() );
	}

	return;
}

sub fuse_statfs : State {
	my( $postback, $context ) = @_[ ARG0, ARG1 ];
	#print "STATFS\n";

	# This is a fake filesystem, so return fake data ;)
	# $namelen, $files, $files_free, $blocks, $blocks_avail, $blocksize
	$postback->( 255, 1, 1, 1, 1, 2 );

	return;
}

sub fuse_fsync : State {
	my( $postback, $context, $path, $fsync_mode ) = @_[ ARG0 .. ARG3 ];
	#print "FSYNC: '$path' - '$fsync_mode'\n";

	# we don't do anything that requires us to do this, so success!
	$postback->( 0 );

	return;
}

# copied from Fuse::Simple, thanks!
sub dump_open_flags {
    my $flags = shift;

    my $str = sprintf "flags: 0%o = (", $flags;
    for my $bits (
	[ O_ACCMODE(),   O_RDONLY(),     "O_RDONLY"    ],
	[ O_ACCMODE(),   O_WRONLY(),     "O_WRONLY"    ],
	[ O_ACCMODE(),   O_RDWR(),       "O_RDWR"      ],
	[ O_APPEND(),    O_APPEND(),    "|O_APPEND"    ],
	[ O_NONBLOCK(),  O_NONBLOCK(),  "|O_NONBLOCK"  ],
	[ O_SYNC(),      O_SYNC(),      "|O_SYNC"      ],
	[ O_DIRECT(),    O_DIRECT(),    "|O_DIRECT"    ],
	[ O_LARGEFILE(), O_LARGEFILE(), "|O_LARGEFILE" ],
	[ O_NOFOLLOW(),  O_NOFOLLOW(),  "|O_NOFOLLOW"  ],
    ) {
	my ($mask, $flag, $name) = @$bits;
	if (($flags & $mask) == $flag) {
	    $flags -= $flag;
	    $str .= $name;
	}
    }
    $str .= sprintf "| 0%o !!!", $flags if $flags;
    $str .= ")\n";

    return $str;
}
