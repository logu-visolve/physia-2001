##############################################################################
package App::Page::WorkList;
##############################################################################

use strict;
use Date::Manip;
use Date::Calc qw(:all);

use App::Page;
use App::ImageManager;
use Devel::ChangeLog;

use DBI::StatementManager;
use App::Statements::Scheduling;
use App::Statements::Page;
use App::Statements::Search::Appointment;

use vars qw(@ISA @CHANGELOG %RESOURCE_MAP);
@ISA = qw(App::Page);
%RESOURCE_MAP = (
	'worklist' => {},
	);


sub prepare_view_default
{
	my ($self) = @_;

	$self->addContent(qq{
		<P><FONT SIZE=+1>
		<A HREF='/worklist/patientflow'>Patient Flow Worksheet</A><BR>
		<A HREF='/worklist/collection'>Collection Worksheet</A><BR>
		<A HREF='/worklist/referral'>Referral Authorization Worksheet</A><BR>
		</FONT></P>
	});

	return 1;
}

sub initialize
{
	my $self = shift;
	$self->SUPER::initialize(@_);

	$self->addLocatorLinks(
		['WorkList', '/worklist'],
	);
}

sub getContentHandlers
{
	return ('prepare_view_$_pm_view=default$');
}


1;
