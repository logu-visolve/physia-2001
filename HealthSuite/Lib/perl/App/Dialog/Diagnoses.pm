##############################################################################
package App::Dialog::Diagnoses;
##############################################################################

use strict;
use DBI::StatementManager;
use App::Statements::Invoice;
use Carp;
use CGI::Dialog;
use CGI::Validator::Field;
use App::Universal;
use App::Dialog::Field::Invoice;
use Date::Manip;
use vars qw(@ISA %RESOURCE_MAP);
@ISA = qw(CGI::Dialog);

%RESOURCE_MAP = (
	'diagnoses' => {},
);

sub new
{
	my ($self, $command) = CGI::Dialog::new(@_, id => 'diagnoses', heading => '$Command Diagnoses');
	my $schema = $self->{schema};
	delete $self->{schema};  # make sure we don't store this!

	croak 'schema parameter required' unless $schema;

	$self->addContent(
		new App::Dialog::Field::Diagnoses(caption => 'ICD-9 Codes', hints => 'Enter ICD-9 codes in a comma separated list', options => FLDFLAG_REQUIRED),
		new CGI::Dialog::Field(caption => 'Comments', name => 'comments'),
		);

	$self->addFooter(new CGI::Dialog::Buttons(cancelUrl => $self->{cancelUrl} || undef));

	return $self;
}

sub populateData
{
	my ($self, $page, $command, $activeExecMode, $flags) = @_;

	return unless $flags & CGI::Dialog::DLGFLAG_UPDORREMOVE_DATAENTRY_INITIAL;

	my $invoiceId = $page->param('invoice_id');
	$STMTMGR_INVOICE->createFieldsFromSingleRow($page, STMTMGRFLAG_NONE, 'selInvoiceDiags', $invoiceId);
}

sub execute
{
	my ($self, $page, $command, $flags) = @_;

	my $invoiceId = $page->param('invoice_id');
	my $sessOrg = $page->session('org_id');
	my $sessUser = $page->session('user_id');
	my $historyValueType = App::Universal::ATTRTYPE_HISTORY;

	my $todaysDate = UnixDate('today', $page->defaultUnixDateFormat());

	my @claimDiags = split(/\s*,\s*/, $page->field('diagcodes'));

	App::IntelliCode::incrementUsage($page, 'Icd', \@claimDiags, $sessUser, $sessOrg);

	$page->schemaAction(
			'Invoice', 'update',
			invoice_id => $invoiceId || undef,
			claim_diags => join(', ', @claimDiags) || undef,
			_debug => 0
		);

	## Add history attribute
	$page->schemaAction(
			'Invoice_Attribute', 'add',
			parent_id => $invoiceId,
			item_name => 'Invoice/History/Item',
			value_type => defined $historyValueType ? $historyValueType : undef,
			value_text => 'Diagnosis codes modified',
			value_textB => $page->field('comments') || undef,
			value_date => $todaysDate,
			_debug => 0
	);

#	$page->redirect("/invoice/$invoiceId/summary");
	$self->handlePostExecute($page, $command, $flags);

}

1;