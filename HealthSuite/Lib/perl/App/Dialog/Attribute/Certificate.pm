##############################################################################
package App::Dialog::Attribute::Certificate;
##############################################################################

use DBI::StatementManager;
use App::Statements::Invoice;
use strict;
use Carp;
use CGI::Dialog;
use CGI::Validator::Field;
use App::Universal;
use Date::Manip;
use Devel::ChangeLog;
use App::Statements::Person;
use vars qw(@ISA @CHANGELOG);
@ISA = qw(CGI::Dialog);

sub initialize
{
	my $self = shift;

	$self->{activityLog} =
	{
		level => 1,
		scope =>'person_attribute',
		key => "#param.person_id#",
		data => "Certification '#field.value_text#' to <a href='/person/#param.person_id#/profile'>#param.person_id#</a>"
	};

	$self->addFooter(new CGI::Dialog::Buttons(cancelUrl => $self->{cancelUrl} || undef));
}

sub populateData
{
	my ($self, $page, $command, $activeExecMode, $flags) = @_;

	return unless $flags & CGI::Dialog::DLGFLAG_UPDORREMOVE_DATAENTRY_INITIAL;

	my $itemId = $page->param('item_id');

	$STMTMGR_PERSON->createFieldsFromSingleRow($page, STMTMGRFLAG_NONE, 'selAttributeById', $itemId);
}

sub execute
{
	my ($self, $page, $command, $flags) = @_;

	my $valueType = $self->{valueType};
	my $itemName = '';
	if($valueType == App::Universal::ATTRTYPE_ACCREDITATION || $valueType == App::Universal::ATTRTYPE_AFFILIATION)
	{
		$itemName = $page->field('value_text');
	}
	else
	{
		$itemName = $page->field('value_textb');
	}

	$page->schemaAction(
		'Person_Attribute',	$command,
		parent_id => $page->param('person_id'),
		item_id => $page->param('item_id') || undef,
		item_name => $itemName,
		value_type => $valueType || undef,
		value_text => $page->field('value_text') || undef,
		value_dateEnd => $page->field('value_dateend') ||undef,
		value_textB => $page->field('value_textb') || undef,
		_debug => 0
	);
	$self->handlePostExecute($page, $command, $flags | CGI::Dialog::DLGFLAG_IGNOREREDIRECT);

	return "\u$command completed.";
}

use constant PANEDIALOG_CERTIFICATE => 'Dialog/Pane/Certificate';

@CHANGELOG =
(
	[	CHANGELOGFLAG_SDE | CHANGELOGFLAG_NOTE, '01/30/2000', 'MAF',
		PANEDIALOG_CERTIFICATE,
		'Created new dialog for certificates.'],
	[	CHANGELOGFLAG_SDE | CHANGELOGFLAG_NOTE, '02/04/2000', 'RK',
		PANEDIALOG_CERTIFICATE,
		'Added customValidate subroutine to Validate Affiliation, License, State and Accreditation Certificates.'],
	[	CHANGELOGFLAG_SDE | CHANGELOGFLAG_UPDATE, '02/04/2000', 'RK',
		PANEDIALOG_CERTIFICATE,
		'Updated populateData subroutine to display data in affiliation pane while updating and deleting.'],
	[	CHANGELOGFLAG_SDE | CHANGELOGFLAG_NOTE, '03/14/2000', 'RK',
		PANEDIALOG_CERTIFICATE,
		'Removed Item Path from Item Name'],
);

1;