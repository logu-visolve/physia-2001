##############################################################################
package App::Dialog::PostBatchPayment;
##############################################################################

use strict;
use Carp;

use DBI::StatementManager;
use App::Statements::Invoice;
use App::Statements::Catalog;
use App::Statements::Insurance;
use CGI::Dialog;
use CGI::Validator::Field;
use App::Dialog::Field::Person;
use App::Dialog::Field::Invoice;
use App::Universal;
use Date::Manip;

use vars qw(@ISA %RESOURCE_MAP);

@ISA = qw(CGI::Dialog);

%RESOURCE_MAP = (
	'batch' => {heading => '$Command Batch'},
);

sub new
{
	my $self = CGI::Dialog::new(@_);

	my $schema = $self->{schema};
	delete $self->{schema};  # make sure we don't store this!

	croak 'schema parameter required' unless $schema;

	$self->addContent(
		new CGI::Dialog::Field(caption => 'User Id', name => 'user_id', options => FLDFLAG_READONLY),
		new CGI::Dialog::Field(caption => 'Batch Number', name => 'batch_id', options => FLDFLAG_REQUIRED),
		new CGI::Dialog::Field(type => 'select', selOptions => 'Insurance Payments:insurance;Personal Payments:personal', caption => 'Batch Type', name => 'batch_type'),

	);
	#$self->{activityLog} =
	#{
	#	scope =>'invoice',
	#	key => "#param.invoice_id#",
	#	data => "batch'#param.item_id#' claim <a href='/invoice/#param.invoice_id#/summary'>#param.invoice_id#</a>"
	#};
	$self->addFooter(new CGI::Dialog::Buttons(cancelUrl => $self->{cancelUrl} || undef));

	return $self;
}

#sub makeStateChanges
#{
#	my ($self, $page, $command, $dlgFlags) = @_;
#	$self->SUPER::makeStateChanges($page, $command, $dlgFlags);
#}

sub populateData
{
	my ($self, $page, $command, $activeExecMode, $flags) = @_;

	my $sessUser = $page->session('user_id');
	$page->field('user_id', $sessUser);
}

sub execute
{
	my ($self, $page, $command, $flags) = @_;

	my $batchId = $page->field('batch_id');
	my $batchType = $page->field('batch_type');
	my $sessOrg = $page->session('org_id');
	if($batchType eq 'personal')
	{
		$page->param('_dialogreturnurl', "/org/$sessOrg/dlg-add-postpersonalpayment?_p_batch_id=$batchId");
	}
	elsif($batchType eq 'insurance')
	{
		$page->param('_dialogreturnurl', "/org/$sessOrg/dlg-add-postinvoicepayment/insurance?_p_batch_id=$batchId");
	}

	$self->handlePostExecute($page, $command, $flags);
}

#sub customValidate
#{
#	my ($self, $page) = @_;
#}

1;
