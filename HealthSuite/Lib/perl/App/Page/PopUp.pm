##############################################################################
package App::Page::PopUp;
##############################################################################

use strict;
use base 'App::Page';

use DBI::StatementManager;
use App::Statements::Component::Scheduling;
use App::Statements::Person;

use vars qw(%RESOURCE_MAP);
%RESOURCE_MAP = (
	'popup' => {},
);

sub prepare_view_alerts
{
	my ($self) = @_;
	my $patientId = $self->param('person_id');
	
	my $html = $STMTMGR_COMPONENT_SCHEDULING->createHtml($self, STMTMGRFLAG_NONE, 
		'sel_detail_alerts',	[$patientId],);
		
	my $patient = $STMTMGR_PERSON->getRowAsHash($self, STMTMGRFLAG_NONE, 'selPersonData',
		$patientId);

	$self->addContent(qq{
		<TABLE CELLSPACING=0 BORDER=0 CELLPADDING=0 width=100%>
			<TR>
				<TD>
					<b style="color:darkgreen">@{[$patient->{complete_name}]} - ($patientId)</b>
				</TD>
				<TD align=right>
					<a href='javascript:window.close()'><img src='/resources/icons/done.gif' border=0></a>
				</TD>
			</TR>
			<TR>
				<TD>
					$html				
				</TD>
			</TR>
		</TABLE>
	});

	return 1;
}

sub getContentHandlers
{
	return ('prepare_view_$_pm_view=alerts$');
}

sub prepare_page_content_footer
{
	my $self = shift;
	return 1;
}

sub prepare_page_content_header
{
	my $self = shift;
	return 1;
}

sub initialize
{
	my $self = shift;
	$self->SUPER::initialize(@_);
}

sub handleARL
{
	my ($self, $arl, $params, $rsrc, $pathItems) = @_;

	$self->param('_pm_view', $pathItems->[0]);
	$self->param('person_id', $pathItems->[1]);

	$self->printContents();
	return 0;
}

1;
