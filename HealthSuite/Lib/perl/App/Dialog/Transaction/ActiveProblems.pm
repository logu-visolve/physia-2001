##############################################################################
package App::Dialog::Transaction::ActiveProblems;
##############################################################################

use strict;
use Carp;
use CGI::Dialog;
use App::Universal;
use CGI::Validator::Field;
use App::Dialog::Field::Person;
use DBI::StatementManager;
use App::Statements::Person;
use App::Statements::Transaction;
use Date::Manip;
use Devel::ChangeLog;
use vars qw(@ISA @CHANGELOG);

@ISA = qw(CGI::Dialog);

sub new
{
	my ($self, $command) = CGI::Dialog::new(@_);

	my $schema = $self->{schema};
	delete $self->{schema};  # make sure we don't store this!
	croak 'schema parameter required' unless $schema;

	my $transType = $self->{transType};
	my $transientType = App::Universal::TRANSTYPEDIAG_TRANSIENT;
	my $permanentType = App::Universal::TRANSTYPEDIAG_PERMANENT;
	my $icdType = App::Universal::TRANSTYPEDIAG_ICD;
	my $notesType = App::Universal::TRANSTYPEDIAG_NOTES;

	if($transType == $notesType)
	{
		$self->addContent(
			new App::Dialog::Field::Person::ID(caption => 'Physician', name => 'provider_id', types => ['Physician'], options => FLDFLAG_REQUIRED),
			new CGI::Dialog::Field(type => 'date', caption => 'Date', name => 'curr_onset_date', options => FLDFLAG_REQUIRED, futureOnly => 0),
			new CGI::Dialog::Field(type => 'memo', name => 'data_text_a', caption => 'Notes', options => FLDFLAG_REQUIRED),
		);
	}
	elsif($transType == $transientType || $transType == $permanentType)
	{
		$self->addContent(
			new App::Dialog::Field::Person::ID(caption => 'Physician', name => 'provider_id', types => ['Physician'], options => FLDFLAG_REQUIRED),
			new App::Dialog::Field::Diagnoses(caption => 'ICD-9 Codes', name => 'code', options => FLDFLAG_TRIM, hints => 'Enter ICD-9 codes in a comma separated list'),
			new CGI::Dialog::Field(type =>'memo', name => 'data_text_a', caption => 'Diagnosis'),
			new CGI::Dialog::Field(type => 'date', name => 'curr_onset_date', caption => 'Diagnosis Date'),
		);
	}

	if($transType == $icdType)
	{
		$self->addContent(
			new CGI::Dialog::Field(caption => 'Problem', name => 'caption'),
			new CGI::Dialog::Field(caption => 'ICD Code', name => 'code'),
			new CGI::Dialog::Field(caption => 'Begin Date', name => 'curr_onset_date'),
		);
	}
	$self->addFooter(new CGI::Dialog::Buttons);
	return $self;
}

sub populateData_remove
{
	my ($self, $page, $command, $activeExecMode, $flags) = @_;

	my $transId = $page->param('trans_id');
	my $transType = $self->{transType};
	my $icdTransType = App::Universal::TRANSTYPEDIAG_ICD;

	if($transType != $icdTransType)
	{
		$STMTMGR_TRANSACTION->createFieldsFromSingleRow($page, STMTMGRFLAG_NONE, 'selTransactionById', $transId);
	}
	elsif($transType == $icdTransType)
	{
		my $data = $STMTMGR_TRANSACTION->getRowAsHash($page, STMTMGRFLAG_NONE, 'selTransAndICDNameByTransId', $transId);
		$page->field('code', $data->{code});
		$page->field('curr_onset_date', $data->{'curr_onset_date'});
		$page->field('caption', $data->{icdname});
	}
}

sub execute_add
{
	my ($self, $page, $command, $flags) = @_;

	my $personType = App::Universal::ENTITYTYPE_PERSON;
	my $transStatusActive = App::Universal::TRANSSTATUS_ACTIVE;
	#my @icdDiags = split(/\s*,\s*/, $page->field('code'));

	$page->schemaAction(
		'Transaction', 'add',
		trans_type => $self->{transType} || undef,
		trans_status => defined $transStatusActive ? $transStatusActive : undef,
		trans_owner_type => $personType || undef,
		trans_owner_id => $page->param('person_id') || undef,
		curr_onset_date => $page->field('curr_onset_date') || undef,
		provider_id => $page->field('provider_id') || undef,
		data_text_a => $page->field('data_text_a') || undef,
		code => $page->field('code') || undef,
		_debug => 0
	);

	$self->handlePostExecute($page, $command, $flags | CGI::Dialog::DLGFLAG_IGNOREREDIRECT);
	return 'Add completed.';
}

sub execute_remove
{
	my ($self, $page, $command, $flags) = @_;

	my $transId = $page->param('trans_id');
	my $transStatusInactive = App::Universal::TRANSSTATUS_INACTIVE;

	#we don't want to delete any trans records so we set trans_status to 3 (inactive) when the command is 'remove'
	#and change $command to 'update'

	$page->schemaAction(
		'Transaction', 'update',
		trans_id => $transId || undef,
		trans_status => $transStatusInactive || undef,
		_debug => 0
	);

	$self->handlePostExecute($page, $command, $flags | CGI::Dialog::DLGFLAG_IGNOREREDIRECT);
	return 'Remove completed.';
}

use constant ACTIVEPROBLEMS_DIALOG => 'Dialog/ActiveProblems';

@CHANGELOG =
(

	[	CHANGELOGFLAG_SDE | CHANGELOGFLAG_UPDATE, '01/28/2000', 'RK',
		ACTIVEPROBLEMS_DIALOG,
		'Moved the dialog for Active Problems pane from transaction.pm to a seperate file in Transaction directory.'],
	[	CHANGELOGFLAG_SDE | CHANGELOGFLAG_ADD, '01/31/2000', 'RK',
		ACTIVEPROBLEMS_DIALOG,
		'Added sub execute and sub populateData_remove sub-routines.'],
	[	CHANGELOGFLAG_SDE | CHANGELOGFLAG_NOTE, '02/21/2000', 'MAF',
		ACTIVEPROBLEMS_DIALOG,
		'Cleaned up and organized code.'],
	[	CHANGELOGFLAG_SDE | CHANGELOGFLAG_UPDATE, '02/21/2000', 'MAF',
		ACTIVEPROBLEMS_DIALOG,
		'Created execute_remove and execute_add subroutines.'],
	[	CHANGELOGFLAG_SDE | CHANGELOGFLAG_UPDATE, '02/21/2000', 'MAF',
		ACTIVEPROBLEMS_DIALOG,
		'Fixed field names and populateData to populate dialogs correctly.'],
);

1;

