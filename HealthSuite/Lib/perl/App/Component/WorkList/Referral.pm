##############################################################################
package App::Component::WorkList::Referral;
##############################################################################

use strict;
use CGI::Layout;
use CGI::Component;

use Date::Calc qw(:all);
use Date::Manip;
use DBI::StatementManager;

use App::Statements::Component::Referral;

use App::Statements::Person;
use App::Statements::Scheduling;
use App::Schedule::Utilities;
use Data::Publish;
use Exporter;

use vars qw(@ISA @ITEM_TYPES @EXPORT
	%PATIENT_URLS
	%PHYSICIAN_URLS
	%ORG_URLS
	%APPT_URLS
	$patientDefault
	$physicianDefault
	$orgDefault
	$apptDefault
);

@ISA   = qw(CGI::Component Exporter);

@ITEM_TYPES = ('patient', 'physician', 'org', 'appt');

%PATIENT_URLS = (
	'View Profile' => {arl => '/person/itemValue/profile', title => 'View Profile'},
	'View Chart' => {arl => '/person/itemValue/chart', title => 'View Chart'},
	'View Account' => {arl => '/person/itemValue/account', title => 'View Account'},
	'Make Appointment' => {arl => '/worklist/patientflow/dlg-add-appointment/itemValue', title => 'Make Appointment'},
);

%PHYSICIAN_URLS = (
	'View Profile' => {arl => '/person/itemValue/profile', title => 'View Profile'},
	'View Schedule' => {arl => '/schedule/apptcol/itemValue', title => 'View Schedule'},
	'Create Template' => {arl => '/worklist/patientflow/dlg-add-template/itemValue', title => 'Create Schedule Template'},
);

%ORG_URLS = (
	'View Profile' => {arl => '/org/itemValue/profile', title => 'View Profile'},
	'View Fee Schedules' => {arl => '/org/itemValue/catalog', title => 'View Fee Schedules'},
);

%APPT_URLS = (
	'Reschedule' => {arl => '/worklist/patientflow/dlg-reschedule-appointment/itemValue', title => 'Reschedule Appointment'},
	'Cancel' => {arl => '/worklist/patientflow/dlg-cancel-appointment/itemValue', title => 'Cancel Appointment'},
	'No-Show' => {arl => '/worklist/patientflow/dlg-noshow-appointment/itemValue', title => 'No-Show Appointment'},
	'Update' => {arl => '/worklist/patientflow/dlg-update-appointment/itemValue', title => 'Update Appointment'},
);

$patientDefault = 'View Profile';
$physicianDefault = 'View Profile';
$orgDefault = 'View Profile';
$apptDefault = 'Update';

@EXPORT = qw(%PATIENT_URLS %PHYSICIAN_URLS %ORG_URLS %APPT_URLS @ITEM_TYPES);

sub initialize
{
	my ($self, $page) = @_;
	my $layoutDefn = $self->{layoutDefn};
	my $arlPrefix = '/worklist/patientflow';

	my $facility_id = $page->session('org_id');
	my $user_id = $page->session('user_id');

	$layoutDefn->{frame}->{heading} = " ";
	$layoutDefn->{style} = 'panel.transparent';

	$layoutDefn->{banner}->{actionRows} =
	[
		{
			caption => qq{
				<a href='/person/$user_id/dlg-add-referral'>Add Referral</a>
			}
		},
	];
}

sub getHtml
{
	my ($self, $page) = @_;

	$self->initialize($page);
	createLayout_html($page, $self->{flags}, $self->{layoutDefn}, $self->getComponentHtml($page));
}

sub getComponentHtml
{
	my ($self, $page) = @_;
	
	my $referrals;
	$referrals = $STMTMGR_COMPONENT_REFERRAL->getRowsAsHashList($page, STMTMGRFLAG_NONE, 'sel_referrals_open');

	my @data = ();
	my $html = qq{
		<style>
			a.today {text-decoration:none; font-family:Verdana; font-size:8pt}
			strong {font-family:Tahoma; font-size:8pt; font-weight:normal}
		</style>
	};
#$_->{referral_id}
	foreach (@$referrals)
	{
		#$_->{checkin_time}
		
		my @rowData = (
			qq{
				$_->{referral_id}
			},
			qq{
				$_->{trans_status_reason}
			},
			qq{
				$_->{patient}
			},
			qq{
				$_->{service_provider}
			},
			qq{
				$_->{service_provider_type}
			},
			qq{
				$_->{requested_service}
			},
			qq{
				$_->{trans_end_stamp}
			},
			qq{
				$_->{patient_id}
			},
		);

		push(@data, \@rowData);
	}

	$html .= createHtmlFromData($page, 0, \@data, $App::Statements::Component::Referral::STMTRPTDEFN_WORKLIST);

	$html .= "<i style='color=red'>No referrals data found.</i> <P>" 
		if (scalar @{$referrals} < 1);

	return $html;
}

# auto-register instance
new App::Component::WorkList::Referral(id => 'worklist-referral');

1;
