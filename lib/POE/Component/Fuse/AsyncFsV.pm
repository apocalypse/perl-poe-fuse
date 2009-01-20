# Declare our package
package POE::Component::Fuse::AsyncFsV;
use strict;
use warnings;

# Initialize our version
use vars qw( $VERSION );
$VERSION = '0.01';

# load the aio helper
use POE::Component::AIO;

# we need access to the kernel
use POE;

# constants we need to interact with FUSE
use Errno qw( :POSIX );    # ENOENT EISDIR etc
use Fcntl qw( :DEFAULT :mode );  # S_IFREG S_IFDIR, O_SYNC O_LARGEFILE etc

# creates a new instance
sub new {
	my $class = shift;
	my $fsv   = shift;

	# Create our obj and return it
	return bless {
		'fsv'	=> $fsv,
		'fhmap'	=> {},
	}, $class;
}

# simple accessor
sub fsv {
	return shift->{'fsv'};
}

sub fuse_getattr {
	my ( $self, $context, $path ) = @_;

	$self->fsv->stat( $path, $poe_kernel->get_active_session->postback( 'reply', 'getattr' ) );
	return;
}

sub fuse_getdir {
	my ( $self, $context, $path ) = @_;

	$self->fsv->dirlist( $path, $poe_kernel->get_active_session->postback( 'reply', 'getdir' ) );
	return;
}

sub fuse_getxattr {
	my ( $self, $context, $path, $attr ) = @_;

	# we don't have any extended attribute support
	$poe_kernel->get_active_session->yield( 'reply', [ 'getxattr' ], [ 0 ] );
	return;
}

sub fuse_setxattr {
	my ( $self, $context, $path, $attr, $value, $flags ) = @_;

	# we don't have any extended attribute support
	$poe_kernel->get_active_session->yield( 'reply', [ 'setxattr' ], [ -ENOSYS() ] );
	return;

}

sub fuse_listxattr {
	my ( $self, $context, $path ) = @_;

	# we don't have any extended attribute support
	$poe_kernel->get_active_session->yield( 'reply', [ 'listxattr' ], [ 0 ] );
	return;
}

sub fuse_removexattr {
	my ( $self, $context, $path, $attr ) = @_;

	# we don't have any extended attribute support
	$poe_kernel->get_active_session->yield( 'reply', [ 'removexattr' ], [ 0 ] );
	return;
}

sub fuse_open {
	my ( $self, $context, $path, $flags ) = @_;

	# determine open mode
	my $mode;
	if ( $flags & O_RDONLY ) {
		$mode = 'READ';
	} elsif ( $flags & O_WRONLY or $flags & O_RDWR

	# did we already open this file?
	if ( exists $self->{'fhmap'}->{ $path } ) {
		$poe_kernel->get_active_session->yield( 'reply', [ 'open' ], [ 0 ] );
		return;
	}

	# make the generic callback
	my $cb = $poe_kernel->get_active_session->postback( 'reply', 'open' );

	# make a special wrapper
	my $callback = sub {
		my $fh = shift;
		if ( defined $fh ) {
			# store it!
			$self->{'fhmap'}->{ $path . $flags } = $fh;
			$cb->( 0 );
		} else {
			$cb->( $! );
		}
	};

	# figure out the mode and set it
	# FIXME we use 0666 as default, should we change this or something?
	my $mode = 0;
	if ( $flags & O_CREAT ) {
		$mode = 0666;
	}

	# actually open it!
	$self->fsv->open( $path, $flags, $mode, $callback );
	return;
}

sub fuse_read {
	my ( $self, $context, $path, $len, $offset ) = @_;

	# do we have a cached fh?
	if ( ! exists $self->{'fhmap'}->{ $path } ) {

}

sub fuse_flush {
	my ( $self, $context, $path ) = @_;

	if ( !$self->fsv->test( 'e', $path ) ) {
		return -ENOENT();
	}

	if ( $self->fsv->test( 'd', $path ) ) {
		return -EISDIR();
	}

	# FIXME what to do for flush? seems like we need to do nothing...
	return 0;
}

sub fuse_release {
	my ( $self, $context, $path, $flags ) = @_;

	if ( !$self->fsv->test( 'e', $path ) ) {
		return -ENOENT();
	}

	if ( $self->fsv->test( 'd', $path ) ) {
		return -EISDIR();
	}

	# FIXME close the $fh

	# successfully closed!
	return 0;
}

sub fuse_truncate {
	my ( $self, $context, $path, $offset ) = @_;

	if ( !$self->fsv->test( 'e', $path ) ) {
		return -ENOENT();
	}

	if ( $self->fsv->test( 'd', $path ) ) {
		return -EISDIR();
	}

	# get the size of the file
	my $size = ( $self->fsv->stat($path) )[7];
	if ( $offset > $size ) {
		return -EINVAL();
	}
	if ( $offset == $size ) {
		return 0;
	}

	# FIXME truncate the $fh

	# successfully truncated!
	return 0;
}

sub fuse_write {
	my ( $self, $context, $path, $buffer, $offset ) = @_;

	if ( !$self->fsv->test( 'e', $path ) ) {
		return -ENOENT();
	}

	if ( $self->fsv->test( 'd', $path ) ) {
		return -EISDIR();
	}

	# get the size of the file
	my $size = ( $self->fsv->stat($path) )[7];

	if ( $offset > $size ) {
		return -EINVAL();
	}

	# FIXME seek to $offset in the $fh

	# FIXME write $buffer to the $fh

	# successfully wrote!
	return length($buffer);
}

sub fuse_mknod {
	my ( $self, $context, $path, $modes, $device ) = @_;

# cleanup the mode ( for some reason we get '100644' instead of '0644' )
# FIXME this seems to also screw up the S_ISREG() stuff, have to investigate more...
	$modes = $modes & 000777;

	if ( $self->fsv->test( 'e', $path ) ) {
		return -EEXIST();
	}

	# we only allow regular files to be created
	if ( $device != 0 ) {
		return -EINVAL();
	}

 # should we add validation to make sure all parents already exist
 # seems like touch() and friends check themselves, so we don't have to do it...

	# FIXME actually create the file

	# successfully created the file!
	return 0;
}

sub fuse_mkdir {
	my ( $self, $context, $path, $modes ) = @_;

	if ( $self->fsv->test( 'e', $path ) ) {
		return -EEXIST();
	}

 # should we add validation to make sure all parents already exist
 # seems like mkdir() and friends check themselves, so we don't have to do it...

	if ( $self->fsv->mkdir( $path, $modes ) ) {
		return 0;
	}
	else {
		return -EIO();
	}
}

sub fuse_unlink {
	my ( $self, $context, $path ) = @_;

	if ( !$self->fsv->test( 'e', $path ) ) {
		return -ENOENT();
	}

	if ( $self->fsv->test( 'd', $path ) ) {
		return -EISDIR();
	}

	if ( $self->fsv->delete($path) ) {
		return 0;
	}
	else {
		return -EIO();
	}
}

sub fuse_rmdir {
	my ( $self, $context, $path ) = @_;

	if ( !$self->fsv->test( 'e', $path ) ) {
		return -ENOENT();
	}

	if ( !$self->fsv->test( 'd', $path ) ) {
		return -ENOTDIR();
	}

  # valid directory, does this directory have any children ( files, subdirs ) ??
	my @list = $self->fsv->list($path);
	if ( scalar @list == 0 ) {
		if ( $self->fsv->rmdir($path) ) {
			return 0;
		}
		else {
			return -EIO();
		}
	}
	else {
		return -ENOTEMPTY();
	}
}

sub fuse_symlink {
	my ( $self, $context, $path, $symlink ) = @_;

	# no support in Filesys::Virtual
	return -ENOSYS();
}

sub fuse_rename {
	my ( $self, $context, $path, $newpath ) = @_;

	if ( !$self->fsv->test( 'e', $path ) ) {
		return -ENOENT();
	}

	if ( $self->fsv->test( 'e', $newpath ) ) {
		return -EEXIST();
	}

    # should we add validation to make sure all parents already exist
    # seems like mv() and friends check themselves, so we don't have to do it...

	# FIXME do the rename

	# successful rename!
	return 0;
}

sub fuse_link {
	my ( $self, $context, $path, $hardlink ) = @_;

	# no support in Filesys::Virtual
	return -ENOSYS();
}

sub fuse_chmod {
	my ( $self, $context, $path, $modes ) = @_;

	if ( !$self->fsv->test( 'e', $path ) ) {
		return -ENOENT();
	}

	if ( $self->fsv->chmod( $modes, $path ) ) {
		return 0;
	}
	else {
		return -EIO();
	}
}

sub fuse_chown {
	my ( $self, $context, $path, $uid, $gid ) = @_;

	# no support in Filesys::Virtual
	return -ENOSYS();
}

sub fuse_utime {
	my ( $self, $context, $path, $atime, $mtime ) = @_;

	if ( !$self->fsv->test( 'e', $path ) ) {
		return -ENOENT();
	}

	if ( $self->fsv->utime( $atime, $mtime, $path ) ) {
		return 0;
	}
	else {
		return -EIO();
	}
}

1;
__END__

=head1 NAME

POE::Component::Fuse::AsyncFsV - Wrapper for Filesys::Virtual::Async

=head1 SYNOPSIS

  Please do not use this module directly.

=head1 ABSTRACT

Please do not use this module directly.

=head1 DESCRIPTION

This module is responsible for "wrapping" L<Filesys::Virtual::Async> objects and making them communicate properly
with the FUSE API that L<POE::Component::Fuse> exposes. Please do not use this module directly.

=head1 EXPORT

None.

=head1 SEE ALSO

L<POE::Component::Fuse>

L<Filesys::Virtual::Async>

=head1 AUTHOR

Apocalypse E<lt>apocal@cpan.orgE<gt>

Props goes to xantus and others who wrote the L<Filesys::Virtual> module!

=head1 COPYRIGHT AND LICENSE

Copyright 2009 by Apocalypse

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.

=cut
