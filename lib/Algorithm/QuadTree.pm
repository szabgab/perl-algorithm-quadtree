package Algorithm::QuadTree;

use strict;
use warnings;
use Carp;

our $VERSION = '0.1';

###############################
#
# sub new() - constructor
#
# Arguments are a hash:
#
# -xmin  => minimum x value
# -xmax  => maximum x value
# -ymin  => minimum y value
# -ymax  => maximum y value
# -depth => depth of tree
#
# Creating a new QuadTree objects automatically
# segments the given area into quadtrees of the
# specified depth.
#
###############################

sub new
{
	my $self  = shift;
	my $class = ref($self) || $self;
	my %args = @_;

	my $obj = bless {}, $class;

	for my $arg (qw/xmin ymin xmax ymax depth/) {
		unless (exists $args{"-$arg"}) {
			carp "- must specify $arg";
			return undef;
		}

		$obj->{uc $arg} = $args{"-$arg"};
	}

	$obj->{BACKREF} = {};
	$obj->{ORIGIN} = [0, 0];
	$obj->{SCALE} = 1;
	$obj->{ROOT} = $obj->_addLevel(
		$obj->{XMIN},
		$obj->{YMIN},
		$obj->{XMAX},
		$obj->{YMAX},
		1    # current depth
	);

	return $obj;
}

###############################
#
# sub _addLevel() - private method
#
# This method segments a given area
# and adds a level to the tree.
#
###############################

sub _addLevel
{
	my (
		$self,
		$xmin, $ymin,
		$xmax, $ymax,
		$curDepth
	) = @_;

	my $node = {
		AREA => [$xmin, $ymin, $xmax, $ymax],
		OBJECTS => [],
	};

	if ($curDepth < $self->{DEPTH}) {
		my $xmid = $xmin + ($xmax - $xmin) / 2;
		my $ymid = $ymin + ($ymax - $ymin) / 2;

		# now segment in the following order (doesn't matter):
		# top left, top right, bottom left, bottom right
		$node->{CHILDREN} = [

			# tl
			$self->_addLevel(
				$xmin, $ymid, $xmid, $ymax,
				$curDepth + 1
			),

			# tr
			$self->_addLevel(
				$xmid, $ymid, $xmax, $ymax,
				$curDepth + 1
			),

			# bl
			$self->_addLevel(
				$xmin, $ymin, $xmid, $ymid,
				$curDepth + 1
			),

			# br
			$self->_addLevel(
				$xmid, $ymin, $xmax, $ymid,
				$curDepth + 1
			),
		];
	}

	return $node;
}

###############################
#
# sub add() - public method
#
# This method adds an object to the tree.
# The arguments are a unique tag to identify
# the object, and the bounding box of the object.
# It automatically assigns the proper quadtree
# sections to each object.
#
###############################

sub add
{
	my ($self, $objRef, @coords) = @_;

	# assume that $objRef is unique.
	# assume coords are (xmin, ymix, xmax, ymax).

	# modify coords according to window.
	@coords = $self->_adjustCoords(@coords)
		unless $self->{SCALE} == 1;

	($coords[0], $coords[2]) = ($coords[2], $coords[0])
		if $coords[2] < $coords[0];

	($coords[1], $coords[3]) = ($coords[3], $coords[1])
		if $coords[3] < $coords[1];

	$self->_addObjToChild(
		$self->{ROOT},
		$objRef,
		@coords,
	);
}

###############################
#
# sub _addObjToChild() - private method
#
# This method is used internally. Given
# a tree segment, an object and its area,
# it checks to see whether the object is to
# be included in the segment or not.
# The object is not included if it does not
# overlap the segment.
#
###############################

sub _addObjToChild
{
	my ($self, $current, $objRef, @coords) = @_;

	# first check if obj overlaps current segment.
	# if not, return.
	my ($cxmin, $cymin, $cxmax, $cymax) = @{$current->{AREA}};

	return if
		$coords[0] > $cxmax ||
		$coords[2] < $cxmin ||
		$coords[1] > $cymax ||
		$coords[3] < $cymin;

	# Only add the object to the segment if we are at the last
	# level of the tree.
	# Else, keep traversing down.

	if ($current->{CHILDREN}) {
		# Now, traverse down the hierarchy.
		for my $child (@{$current->{CHILDREN}}) {
			$self->_addObjToChild(
				$child,
				$objRef,
				@coords,
			);
		}
	} else {
		push @{$current->{OBJECTS}}, $objRef;    # points from leaf to object
		push @{$self->{BACKREF}{$objRef}}, $current;    # points from object to leaf
	}
}

###############################
#
# sub delete() - public method
#
# This method deletes an object from the tree.
#
###############################

sub delete
{
	my ($self, $objRef) = @_;

	return unless exists $self->{BACKREF}{$objRef};

	for my $node (@{$self->{BACKREF}{$objRef}}) {
		$node->{OBJECTS} = [ grep {$_ ne $objRef} @{$node->{OBJECTS}} ];
	}

	delete $self->{BACKREF}{$objRef};
}

###############################
#
# sub getEnclosedObjects() - public method
#
# This method takes an area, and returns all objects
# enclosed in that area.
#
###############################

sub getEnclosedObjects
{
	my ($self, @coords) = @_;

	@coords = $self->_adjustCoords(@coords)
		unless $self->{SCALE} == 1;

	my @results;
	$self->_checkOverlap(
		$self->{ROOT},
		\@results,
		@coords,
	);

	# uniq results
	my %temp = map { $_ => $_ } @results;

	# PS. I don't check explicitly if those objects
	# are enclosed in the given area. They are just
	# part of the segments that are enclosed in the
	# given area. TBD.

	return [values %temp];
}

###############################
#
# sub _adjustCoords() - private method
#
# This method adjusts the given coordinates
# according to the stored window. This is used
# when we 'zoom in' to avoid searching in areas
# that are not visible in the canvas.
#
###############################

sub _adjustCoords
{
	my ($self, @coords) = @_;

	# modify coords according to window.
	$_ = $self->{ORIGIN}[0] + $_ / $self->{SCALE}
		for $coords[0], $coords[2];
	$_ = $self->{ORIGIN}[1] + $_ / $self->{SCALE}
		for $coords[1], $coords[3];

	return @coords;
}

###############################
#
# sub _checkOverlap() - private method
#
# This method checks if the given coordinates overlap
# the specified tree segment. If not, nothing happens.
# If it does overlap, then it is called recuresively
# on all the segment's children. If the segment is a
# leaf, then its associated objects are saved into an
# out reference.
#
###############################

sub _checkOverlap
{
	my ($self, $current, $results, @coords) = @_;

	# first check if obj overlaps current segment.
	# if not, return.
	my ($cxmin, $cymin, $cxmax, $cymax) = @{$current->{AREA}};

	return if
		$coords[0] >= $cxmax ||
		$coords[2] <= $cxmin ||
		$coords[1] >= $cymax ||
		$coords[3] <= $cymin;

	if ($current->{CHILDREN}) {
		# Now, traverse down the hierarchy.
		for my $child (@{$current->{CHILDREN}}) {
			$self->_checkOverlap(
				$child,
				$results,
				@coords,
			);
		}
	} else {
		push @{$results}, @{$current->{OBJECTS}};
	}
}

###############################
#
# sub setWindow() - public method
#
# This method takes an area as input, and
# sets it as the active window. All new
# calls to any method will refer to that area.
#
###############################

sub setWindow
{
	my ($self, $sx, $sy, $s) = @_;

	$self->{ORIGIN}[0] += $sx / $self->{SCALE};
	$self->{ORIGIN}[1] += $sy / $self->{SCALE};
	$self->{SCALE} *= $s;
}

###############################
#
# sub setWindow() - public method
# This resets the window.
#
###############################

sub resetWindow
{
	my $self = shift;

	$self->{ORIGIN}[$_] = 0 for 0 .. 1;
	$self->{SCALE} = 1;
}

1;

__END__

=head1 NAME

Algorithm::QuadTree - A QuadTree Algorithm class in pure Perl.

=head1 SYNOPSIS

    use Algorithm::QuadTree;

    # create a quadtree object
    my $qt = Algorithm::QuadTree->new(-xmin  => 0,
                                      -xmax  => 1000,
                                      -ymin  => 0,
                                      -ymax  => 1000,
                                      -depth => 6);

    # add objects randomly
    my $x = my $tag = 1;
    while ($x < 1000) {
      my $y = 1;
      while ($y < 1000) {
        $qt->add($tag++, $x, $y, $x, $y);

        $y += int rand 200;
      }
      $x += int rand 100;
    }

    # find the objects enclosed in a given region
    my $r_list = $qt->getEnclosedObjects(400, 300,
                                         689, 799);

=head1 DESCRIPTION

Algorithm::QuadTree implements a quadtree algorithm (QTA) in pure Perl.
Essentially, a I<QTA> is used to access a particular area of a map very quickly.
This is especially useful in finding objects enclosed in a given region, or
in detecting intersection among objects. In fact, I wrote this module to rapidly
search through objects in a L<Tk::Canvas> widget, but have since used it in other
non-Tk programs successfully. It is a classic memory/speed trade-off.

Lots of information about QTAs can be found on the web. But, very briefly,
a quadtree is a hierarchical data model that recursively decomposes a map into
smaller regions. Each node in the tree has 4 children nodes, each of which
represents one quarter of the area that the parent represents. So, the root
node represents the complete map. This map is then split into 4 equal quarters,
each of which is represented by one child node. Each of these children is now
treated as a parent, and its area is recursively split up into 4 equal areas,
and so on up to a desired depth.

Here is a somewhat crude diagram (those diagrams might not appear unless
you run pod2text):

=begin text

                   ------------------------------
                  |AAA|AAB|       |              |
                  |___AA__|  AB   |              |
                  |AAC|AAD|       |              |
                  |___|___A_______|      B       |
                  |       |       |              |
                  |       |       |              |
                  |   AC  |   AD  |              |
                  |       |       |              |
                   -------------ROOT-------------
                  |               |              |
                  |               |              |
                  |               |              |
                  |      C        |      D       |
                  |               |              |
                  |               |              |
                  |               |              |
                   ------------------------------

=end text

Which corresponds to the following quadtree:

=begin text

                    __ROOT_
                   /  / \  \
                  /  /   \  \
            _____A_  B   C   D
           /  / \  \
          /  /   \  \
    _____AA  AB  AC  AD
   /  / \  \
  /  /   \  \
AAA AAB AAC AAD

=end text

In the above diagrams I show only the nodes through the first branch of
each level. The same structure exists under each node. This quadtree has a
depth of 4.

Each object in the map is assigned to the nodes that it intersects. For example,
if we have a rectangular object that overlaps regions I<AAA> and I<AAC>, it will be
assigned to the nodes I<ROOT>, I<A>, I<AA>, I<AAA> and I<AAC>. Now, suppose we
want to find all the objects that intersect a given area. Instead of checking all
objects, we check to see which children of the ROOT node intersect the area. For
each of those nodes, we recursively check I<their> children nodes, and so on
until we reach the leaves of the tree. Finally, we find all the objects that are
assigned to those leaf nodes and check them for overlap with the initial area.

=head1 CLASS METHODS

The following methods are public:

=over 4

=item I<Algorithm::QuadTree>-E<gt>B<new>(I<options>)

This is the constructor. It expects the following options (all mandatory) and
returns an Algorithm::QuadTree object:

=over 8

=item -xmin

This is the X-coordinate of the bottom left corner of the area associated with
the quadtree.

=item -ymin

This is the Y-coordinate of the bottom left corner of the area associated with
the quadtree.

=item -xmax

This is the X-coordinate of the top right corner of the area associated with
the quadtree.

=item -ymax

This is the Y-coordinate of the top right corner of the area associated with
the quadtree.

=item -depth

The depth of the quadtree.

=back

=item I<$qt>-E<gt>B<add>(ID, x0, y0, x1, y1)

This method is used to add objects to the tree. It has to be called for every
object in the map so that it can properly assigned to the correct tree nodes.
The first argument is a I<unique> ID for the object. The remaining 4 arguments
define the outline of the object. This method will recursively traverse the
tree and add the object to the nodes that it overlaps with.

NOTE: The method does I<NOT> check if the ID is unique or not. It is up to you
to make sure it is.

=item I<$qt>-E<gt>B<delete>(ID)

This method deletes the object specified by the given ID, and unassigns it from
the tree nodes it was assigned to before.

=item I<$qt>-E<gt>B<getEnclosedObjects>(x0, y0, x1, y1)

This method returns an <anonymous list> of all the objects that are assigned
to the nodes that overlap the given area.

=item I<$qt>-E<gt>B<setWindow>(x0, y0, scale)

This method is useful when you zoom your display to a certain segment of
the map. It sets the window to the given region such that any calls to
B<add> or B<getEnclosedObjects> will have its coordinates properly adjusted
before running. The first two coordinates specify the lower left coordinates
of the new window. The third coordinate specifies the new zoom scale.

NOTE: You are free, of course, to make the coordinate transformation yourself.

=item I<$qt>-E<gt>B<resetWindow>()

This method resets the window region to the full map.

=back

=head1 BUGS

None that I am aware of. Please let me know if you find any.

=head1 AUTHORS

Ala Qumsieh I<aqumsieh@cpan.org>

Currently maintained by Bartosz Jarzyna I<bbrtj.pro@gmail.com>

=head1 COPYRIGHTS

This module is distributed under the same terms as Perl itself.

