##############################################################################
package App::Dialog::Transaction::TestsMeasurements;
##############################################################################

use strict;
use Carp;
use CGI::Dialog;
use App::Universal;
use CGI::Validator::Field;
use App::Dialog::Field::Person;
use Date::Manip;
use Devel::ChangeLog;
use vars qw(@ISA @CHANGELOG);

@ISA = qw(CGI::Dialog);

sub new
{
	my ($self, $command) = CGI::Dialog::new(@_, id => 'tests', heading => '$Command Tests/Measurements');


	my $schema = $self->{schema};
	delete $self->{schema};  # make sure we don't store this!

	croak 'schema parameter required' unless $schema;

	$self->addContent(
				#new CGI::Dialog::Field::TableColumn(type => 'hidden', schema => $schema, column => 'Transaction.trans_type', typeRange => '12000..12999', name => 'trans_type'),
				new CGI::Dialog::Field(name => 'trans_begin_stamp', caption => 'TestDate' , type => 'stamp', futureOnly => 0,options => FLDFLAG_REQUIRED),
				new CGI::Dialog::Field(name => 'height_value', caption => 'Height'),
				new CGI::Dialog::Field(name => 'weight_value', caption => 'Weight'),
				new CGI::Dialog::Field(type =>'memo', name => 'diet_value', caption => 'Diet'),
				new CGI::Dialog::Field(name => 'blood_sugar_value', caption => 'Blood Sugar'),
				new CGI::Dialog::Field(type => 'memo',name => 'exercise_value', caption => 'Exercise'),
				new CGI::Dialog::Field(name => 'stress_value', caption => 'Stress'),
				new CGI::Dialog::Field(name => 'blood_pressure_value', caption => 'Blood Pressure'),
				new CGI::Dialog::Field(name => 'cholesterol_value', caption => 'Cholesterol'),

		);
	$self->{activityLog} =
		{
			level => 1,
			scope =>'transaction',
			key => "#param.person_id#",
			data => "Tests and Measurements to <a href='/person/#param.person_id#/profile'>#param.person_id#</a>"
	};
	$self->addFooter(new CGI::Dialog::Buttons(cancelUrl => $self->{cancelUrl} || undef));

	return $self;
}
sub execute
{
	my ($self, $page, $command, $flags) = @_;
	my $pane = $self->{pane};
	my $transaction = $self->{transaction};
	my $personId = $page->param('person_id');
	my $transType = App::Universal::TRANSTYPE_TESTSMEASUREMENTS;

	#$page->schemaAction(
	#		'Transaction',
	#		$command,
	#		trans_owner_type => 0,
	#		trans_owner_id => $page->param('person_id'),
	#		trans_id => $transaction->{trans_id} || undef,
	#		trans_type => $page->field('trans_type') || undef,
	#		trans_begin_stamp => $page->field('trans_begin_stamp') || undef,
	#	);

	$page->schemaAction(
			'Transaction',
			$command,
			trans_owner_type => 0,
			trans_owner_id => $page->param('person_id'),
			trans_id => $transaction->{trans_id} || undef,
			trans_type => $transType || undef,
			trans_begin_stamp => $page->field('trans_begin_stamp') || undef,
			data_text_a => $page->field('height_value') || undef,
			data_text_b => 'Height',
		) if $page->field('height_value') ne '';

	$page->schemaAction(
			'Transaction',
			$command,
			trans_owner_type => 0,
			trans_owner_id => $page->param('person_id'),
			trans_id => $transaction->{trans_id} || undef,
			trans_type => $transType || undef,
			trans_begin_stamp => $page->field('trans_begin_stamp') || undef,
			data_text_a => $page->field('weight_value') || undef,
			data_text_b => 'Weight',

		) if $page->field('weight_value') ne '';

	$page->schemaAction(
			'Transaction',
			$command,
			trans_owner_type => 0,
			trans_owner_id => $page->param('person_id'),
			trans_id => $transaction->{trans_id} || undef,
			trans_type => $transType || undef,
			trans_begin_stamp => $page->field('trans_begin_stamp') || undef,
			data_text_a => $page->field('diet_value') || undef,
			data_text_b => 'Diet',
		) if $page->field('diet_value') ne '';

	$page->schemaAction(
			'Transaction',
			$command,
			trans_owner_type => 0,
			trans_owner_id => $page->param('person_id'),
			trans_id => $transaction->{trans_id} || undef,
			trans_type => $transType || undef,
			trans_begin_stamp => $page->field('trans_begin_stamp') || undef,
			data_text_a => $page->field('blood_sugar_value') || undef,
			data_text_b =>'Blood Sugar',
		) if $page->field('blood_sugar_value') ne '';

	$page->schemaAction(
			'Transaction',
			$command,
			trans_owner_type => 0,
			trans_owner_id => $page->param('person_id'),
			trans_id => $transaction->{trans_id} || undef,
			trans_type => $transType || undef,
			trans_begin_stamp => $page->field('trans_begin_stamp') || undef,
			data_text_a => $page->field('exercise_value') || undef,
			data_text_b =>'Exercise',
		) if $page->field('exercise_value') ne '';

	$page->schemaAction(
			'Transaction',
			$command,
			trans_owner_type => 0,
			trans_owner_id => $page->param('person_id'),
			trans_id => $transaction->{trans_id} || undef,
			trans_type => $transType || undef,
			trans_begin_stamp => $page->field('trans_begin_stamp') || undef,
			data_text_a => $page->field('stress_value') || undef,
			data_text_b => 'Stress',
		) if $page->field('stress_value') ne '';

	$page->schemaAction(
			'Transaction',
			$command,
			trans_owner_type => 0,
			trans_owner_id => $page->param('person_id'),
			trans_id => $transaction->{trans_id} || undef,
			trans_type => $transType || undef,
			trans_begin_stamp => $page->field('trans_begin_stamp') || undef,
			data_text_a => $page->field('blood_pressure_value') || undef,
			data_text_b => 'Blood Pressure',
		) if $page->field('blood_pressure_value') ne '';

	$page->schemaAction(
			'Transaction',
			$command,
			trans_owner_type => 0,
			trans_owner_id => $page->param('person_id'),
			trans_id => $transaction->{trans_id} || undef,
			trans_type => $transType || undef,
			trans_begin_stamp => $page->field('trans_begin_stamp') || undef,
			data_text_a => $page->field('cholesterol_value') || undef,
			data_text_b => 'Cholesterol',
		) if $page->field('cholesterol_value') ne '';
	$self->handlePostExecute($page, $command, $flags | CGI::Dialog::DLGFLAG_IGNOREREDIRECT);
	return "\u$command completed.";
}

use constant TESTSMEASUREMENTS_DIALOG => 'Dialog/Pane/TestsMeasurements';

@CHANGELOG =
(

	[	CHANGELOGFLAG_SDE | CHANGELOGFLAG_UPDATE, '01/28/2000', 'RK',
		TESTSMEASUREMENTS_DIALOG,
		'Moved the dialog for Tests and Measurements from transaction.pm to a seperate file in Transaction directory.'],
	[	CHANGELOGFLAG_SDE | CHANGELOGFLAG_ADD, '01/31/2000', 'RK',
		TESTSMEASUREMENTS_DIALOG,
		'Added sub Execute subroutine.'],
);

1;