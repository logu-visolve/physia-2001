##############################################################################
package App::Dialog::ApptType;
##############################################################################

use strict;
use Carp;
use CGI::Validator::Field;
use CGI::Dialog;
use App::Dialog::Field::Person;
use App::Dialog::Field::RovingResource;

use DBI::StatementManager;
use App::Statements::Scheduling;
use App::Statements::Transaction;
use Date::Manip;
use constant NEXTACTION_COPYASNEW => "/org/%session.org_id%/dlg-add-appttype/%field.appt_type_id%";
use vars qw(@ISA %RESOURCE_MAP);

@ISA = qw(CGI::Dialog);

%RESOURCE_MAP = (
	'appttype' => { 
			_arl => ['appt_type_id'], 
		},
);

sub new
{
	my $self = CGI::Dialog::new(@_, id => 'template', heading => '$Command Appointment Type');

	my $schema = $self->{schema};
	delete $self->{schema};  # make sure we don't store this!

	croak 'schema parameter required' unless $schema;

	my $physField = new App::Dialog::Field::Person::ID(name => 'r_ids',
		caption => 'Resource(s)',
		hints => 'Resource(s) and/or select Roving Physician(s)',
		size => 40,
		maxLength => 255,
		findPopupAppendValue => ',',
		options => FLDFLAG_REQUIRED,
	);
	$physField->clearFlag(FLDFLAG_IDENTIFIER); # because we can have roving resources, too.

	$self->addContent(

		new CGI::Dialog::Field(name => 'appt_type_id',
			caption => 'Appointment Type ID',
			options => FLDFLAG_READONLY,
			invisibleWhen => CGI::Dialog::DLGFLAG_ADD
		),

		new CGI::Dialog::Field::Duration(name => 'effective',
			caption => 'Effective Dates',
		),

		new CGI::Dialog::Field::TableColumn(column => 'Appt_Type.caption',
			caption => 'Caption',
			schema => $schema,
			options => FLDFLAG_REQUIRED
		),

		$physField,

		new App::Dialog::Field::RovingResource(physician_field => '_f_r_ids',
			name => 'roving_physician',
			caption => 'Roving Physician',
			type => 'foreignKey',
			fKeyDisplayCol => 0,
			fKeyValueCol => 0,
			fKeyStmtMgr => $STMTMGR_SCHEDULING,
			fKeyStmt => 'selRovingPhysicianTypes',
			appendMode => 1,
		),

		new CGI::Dialog::Field(caption => 'Duration',
			name => 'duration',
			fKeyStmtMgr => $STMTMGR_SCHEDULING,
			fKeyStmt => 'selApptDuration',
			fKeyDisplayCol => 1,
			fKeyValueCol => 0,
			options => FLDFLAG_REQUIRED),

		new CGI::Dialog::Field(name => 'facility_id',
			caption => 'Facility',
			fKeyStmtMgr => $STMTMGR_SCHEDULING,
			fKeyStmt => 'selFacilityList',
			fKeyDisplayCol => 1,
			fKeyValueCol => 0,
			options => FLDFLAG_REQUIRED
		),
	);

	$self->addFooter(new CGI::Dialog::Buttons(
		nextActions_update => [
			['', '', 1],
			['Copy as New Appointment Type', NEXTACTION_COPYASNEW],
		],
		cancelUrl => $self->{cancelUrl} || undef));

	return $self;
}

###############################
# makeStateChanges functions
###############################

sub makeStateChanges
{
	my ($self, $page, $command, $activeExecMode, $dlgFlags) = @_;

	$self->SUPER::makeStateChanges($page, $command, $activeExecMode, $dlgFlags);
}

###############################
# populateData functions
###############################

sub populateData_add
{
	my ($self, $page, $command, $activeExecMode, $flags) = @_;

	if ($page->param('appt_type_id'))
	{
		$self->populateData_update($page, $command, $activeExecMode, $flags);
	}
	else
	{
		my $startDate = $page->getDate();
		$page->field('effective_begin_date', $startDate);
		$page->field('r_ids', $page->param('resource_id'));
	}
}

sub populateData_update
{	my ($self, $page, $command, $activeExecMode, $flags) = @_;
	my $apptTypeId = $page->param('appt_type_id');

	$STMTMGR_SCHEDULING->createFieldsFromSingleRow($page, STMTMGRFLAG_NONE,'selPopulateApptTypeDialog', $apptTypeId);
}

###############################
# execute function
###############################

sub execute
{
	my ($self, $page, $command, $flags) = @_;

	my $apptTypeId = $page->field('appt_type_id');
	my $timeStamp = $page->getTimeStamp();

	my $newApptTypeId = $page->schemaAction(
		'Appt_Type', $command,
		appt_type_id => $command eq 'add' ? undef : $apptTypeId,
		effective_begin_date => $page->field('effective_begin_date') || undef,
		effective_end_date => $page->field('effective_end_date') || undef,
		caption => $page->field ('caption'),
		r_ids => $page->field ('r_ids'),
		facility_id => $page->field ('facility_id'),
		duration => $page->field('duration'),
		_debug => 0
	);

	$self->handlePostExecute($page, $command, $flags);
}

1;
