##############################################################################
package App::Dialog::Encounter;
##############################################################################

use strict;
use DBI::StatementManager;
use App::Statements::Insurance;
use App::Statements::Transaction;
use App::Statements::Person;
use App::Statements::Org;
use App::Statements::Invoice;
use App::Statements::Scheduling;
use App::Statements::Catalog;
use Carp;
use CGI::Validator::Field;
use CGI::Dialog;
use App::Dialog::Field::Person;
use App::Dialog::Field::Invoice;
use App::Dialog::Field::Procedures;
use App::Universal;

use Date::Manip;
use Date::Calc qw(:all);
use Text::Abbrev;

use Devel::ChangeLog;

use vars qw(@ISA @CHANGELOG);

@ISA = qw(CGI::Dialog);

sub initialize
{
	my $self = shift;
	my $schema = $self->{schema};

	$self->addContent(

		new CGI::Dialog::Field(type => 'hidden', name => 'trans_id'),
		new CGI::Dialog::Field(type => 'hidden', name => 'condition_item_id'),
		new CGI::Dialog::Field(type => 'hidden', name => 'prior_auth_item_id'),
		new CGI::Dialog::Field(type => 'hidden', name => 'deduct_item_id'),
		new CGI::Dialog::Field(type => 'hidden', name => 'assignment_item_id'),
		new CGI::Dialog::Field(type => 'hidden', name => 'accept_assignment'),
		new CGI::Dialog::Field(type => 'hidden', name => 'illness_item_id'),
		new CGI::Dialog::Field(type => 'hidden', name => 'disability_item_id'),
		new CGI::Dialog::Field(type => 'hidden', name => 'hospital_item_id'),
		new CGI::Dialog::Field(type => 'hidden', name => 'cntrl_num_item_id'),
		new CGI::Dialog::Field(type => 'hidden', name => 'bill_contact_item_id'),
		new CGI::Dialog::Field(type => 'hidden', name => 'pay_to_org_item_id'),
		new CGI::Dialog::Field(type => 'hidden', name => 'pay_to_org_phone_item_id'),
		new CGI::Dialog::Field(type => 'hidden', name => 'pay_to_org_addr_item_id'),
		new CGI::Dialog::Field(type => 'hidden', name => 'claim_filing_item_id'),
		new CGI::Dialog::Field(type => 'hidden', name => 'event_id'),
		new CGI::Dialog::Field(type => 'hidden', name => 'insuranceIsSet'),
		new CGI::Dialog::Field(type => 'hidden', name => 'eventFieldsAreSet'),
		new CGI::Dialog::Field(type => 'hidden', name => 'invoiceFieldsAreSet'),

		new CGI::Dialog::Field(type => 'hidden', name => 'primary_payer'),
		new CGI::Dialog::Field(type => 'hidden', name => 'secondary_payer'),
		new CGI::Dialog::Field(type => 'hidden', name => 'tertiary_payer'),
		new CGI::Dialog::Field(type => 'hidden', name => 'quaternary_payer'),
		new CGI::Dialog::Field(type => 'hidden', name => 'third_party_payer_id'),
		new CGI::Dialog::Field(type => 'hidden', name => 'copay_amt'),


		new App::Dialog::Field::Person::ID(caption => 'Patient ID', name => 'attendee_id', options => FLDFLAG_REQUIRED,
			readOnlyWhen => CGI::Dialog::DLGFLAG_UPDORREMOVE,
			types => ['Patient']),

		new CGI::Dialog::Field(type => 'stamp', caption => 'Appointment Time',
			name => 'start_time', options => FLDFLAG_READONLY),
		new CGI::Dialog::Field(type => 'stamp', caption => 'Check-in Time',
			name => 'checkin_stamp', options => FLDFLAG_READONLY),
		new CGI::Dialog::Field(type => 'stamp', caption => 'Check-out Time',
			name => 'checkout_stamp', options => FLDFLAG_READONLY),


		new CGI::Dialog::Field::TableColumn(
			caption => 'Type of Visit',
			schema => $schema,
			column => 'Transaction.trans_type',
			typeRange => '2000..2999'),
		new CGI::Dialog::Field::TableColumn(
			caption => 'Appointment Type',
			schema => $schema,
			column => 'Event.event_type', typeRange => '100..199'),

		new CGI::Dialog::Field(caption => 'Reason for Visit', name => 'subject', options => FLDFLAG_REQUIRED),

		new CGI::Dialog::Field(type => 'memo', caption => 'Symptoms', name => 'remarks'),

		new CGI::Dialog::Field(name => 'accident',
				caption => 'Accident?',
				fKeyStmtMgr => $STMTMGR_INVOICE,
				fKeyStmt => 'selAccidentDropDown',
				fKeyDisplayCol => 0,
				fKeyValueCol => 1),

		new CGI::Dialog::Field(caption => 'Place of Auto Accident (State)', name => 'accident_state', size => 2, maxLength => 2),



		new CGI::Dialog::Field(caption => 'Primary Payer', type => 'select', name => 'payer', options => FLDFLAG_REQUIRED),

		new CGI::Dialog::Field(caption => 'Third-Party Payer for Today', name => 'other_payer'),

		#new CGI::Dialog::MultiField(caption => 'Deductible Balance/Insurance Phone', name => 'deduct_fields',
		#	fields => [
				new CGI::Dialog::Field(type => 'currency', caption => 'Deductible Balance', name => 'deduct_balance'),
		#		new CGI::Dialog::Field(caption => 'Contact Phone for Primary Insurance', name => 'primary_ins_phone', options => FLDFLAG_READONLY),
		#	]),

		new CGI::Dialog::Field(caption => 'Contact Phone for Primary Insurance', name => 'primary_ins_phone', options => FLDFLAG_READONLY),

		new CGI::Dialog::MultiField(caption => 'Provider Service/Billing', name => 'provider_fields',
			fields => [
				new CGI::Dialog::Field(
						caption => 'Service Provider',
						name => 'care_provider_id',
						fKeyStmtMgr => $STMTMGR_PERSON,
						fKeyStmt => 'selPersonBySessionOrgAndCategory',
						fKeyDisplayCol => 0,
						fKeyValueCol => 0,
						options => FLDFLAG_REQUIRED
						),
				new CGI::Dialog::Field(
						caption => 'Billing Provider',
						name => 'provider_id',
						fKeyStmtMgr => $STMTMGR_PERSON,
						fKeyStmt => 'selPersonBySessionOrgAndCategory',
						fKeyDisplayCol => 0,
						fKeyValueCol => 0,
						options => FLDFLAG_REQUIRED
						),
			]),

		new CGI::Dialog::MultiField(caption => 'Org Service/Billing/Pay To',
			hints => 'Service Org is the org in which services were given.<br>
						Billing org is the org in which the billing should be tracked.<br>
						Pay To org is the org which should receive payment.',
			fields => [
				new App::Dialog::Field::OrgType(
							caption => 'Service Facility',
							name => 'service_facility_id'),
				new App::Dialog::Field::OrgType(
							caption => 'Billing Org',
							name => 'billing_facility_id'),
				new App::Dialog::Field::OrgType(
							caption => 'Pay To Org',
							name => 'pay_to_org_id'),
			]),


		new CGI::Dialog::Field(caption => 'Billing Contact', name => 'billing_contact'),
		new CGI::Dialog::Field(type=>'phone', caption => 'Billing Phone', name => 'billing_phone'),

		new App::Dialog::Field::Person::ID(caption => 'Referring Physician ID', name => 'ref_id', types => ['Physician']),

		new CGI::Dialog::MultiField(caption =>'Similar/Current Illness Dates',
			fields => [
				new CGI::Dialog::Field(name => 'illness_begin_date', type => 'date', defaultValue => ''),
				new CGI::Dialog::Field(name => 'illness_end_date', type => 'date', defaultValue => '')
			]),

		new CGI::Dialog::MultiField(caption =>'Begin/End Disability Dates',
			fields => [
				new CGI::Dialog::Field(name => 'disability_begin_date', type => 'date', defaultValue => ''),
				new CGI::Dialog::Field(name => 'disability_end_date', type => 'date', defaultValue => '')
			]),

		new CGI::Dialog::MultiField(caption =>'Admission/Discharge Hospitalization Dates', name => 'hosp_dates',
			fields => [
				new CGI::Dialog::Field(name => 'hospitalization_begin_date', type => 'date', defaultValue => ''),
				new CGI::Dialog::Field(name => 'hospitalization_end_date', type => 'date', defaultValue => '')
			]),

		new CGI::Dialog::Field(caption => 'Prior Authorization Number', name => 'prior_auth'),

		new CGI::Dialog::Field(type => 'memo',
				caption => 'Comments',
				name => 'comments'),
		new CGI::Dialog::Field(type => 'bool',
				style => 'check',
				caption => 'Have you confirmed Personal Information/Insurance Coverage?',
				name => 'confirmed_info',
				options => FLDFLAG_REQUIRED),



		new CGI::Dialog::Subhead(heading => 'Procedure Entry', name => 'procedures_heading'),

		new App::Dialog::Field::Procedures(name =>'procedures_list', lineCount => 3),

	);

	return $self;
}

sub makeStateChanges
{
	my ($self, $page, $command, $dlgFlags) = @_;
	$self->SUPER::makeStateChanges($page, $command, $dlgFlags);
	$command ||= 'add';


	#Set attendee_id field and make it read only if person_id exists
	if(my $personId = $page->param('person_id') || $page->param('attendee_id') || $page->field('attendee_id'))
	{
		$page->field('attendee_id', $personId);
		$self->setFieldFlags('attendee_id', FLDFLAG_READONLY);
	}



	#Populate provider id field with session org's providers
	my $sessOrg = $page->session('org_id');
	$self->getField('provider_fields')->{fields}->[0]->{fKeyStmtBindPageParams} = [$sessOrg, 'Physician'];
	$self->getField('provider_fields')->{fields}->[1]->{fKeyStmtBindPageParams} = [$sessOrg, 'Physician'];



	#Don't want to show opt proc entry when deleting
	if($command eq 'remove')
	{
		$self->updateFieldFlags('procedures_heading', FLDFLAG_INVISIBLE, 1);
		$self->updateFieldFlags('procedures_list', FLDFLAG_INVISIBLE, 1);
	}



	#Billing Org Contact Information
	my $billingOrg = $page->field('billing_facility_id');
	my $billingContact = $STMTMGR_ORG->getRowAsHash($page, STMTMGRFLAG_CACHE, 'selAttribute', $billingOrg, 'Contact Information');
	if($billingOrg eq '' || $billingContact->{value_text} ne '')
	{
		$self->updateFieldFlags('billing_contact', FLDFLAG_INVISIBLE, 1);
		$self->updateFieldFlags('billing_phone', FLDFLAG_INVISIBLE, 1);
	}
	elsif($billingOrg ne '' && $billingContact->{value_text} eq '')
	{
		my $billContactField = $self->getField('billing_contact');
		my $billPhoneField = $self->getField('billing_phone');

		if($page->field('billing_contact') eq '')
		{
			$billContactField->invalidate($page, "Billing Facility '$billingOrg' does not have '$billContactField->{caption}' on file. Please provide one.");
		}
		if($page->field('billing_phone') eq '')
		{
			$billPhoneField->invalidate($page, "Billing Facility '$billingOrg' does not have '$billPhoneField->{caption}' on file. Please provide one.");
		}
	}
}

sub populateData
{
	my ($self, $page, $command, $activeExecMode, $flags) = @_;

	my $invoiceId = $page->param('invoice_id');
	my $eventId = $page->param('event_id');

	if(! $page->field('eventFieldsAreSet') && $eventId)
	{
		$page->field('checkin_stamp', $page->getTimeStamp());
		$page->field('checkout_stamp', $page->getTimeStamp());
		$page->field('event_id', $eventId);
		$STMTMGR_SCHEDULING->createFieldsFromSingleRow($page, STMTMGRFLAG_NONE, 'selEncountersCheckIn/Out', $eventId);

		$invoiceId = $page->param('invoice_id', $STMTMGR_INVOICE->getSingleValue($page, STMTMGRFLAG_NONE, 'selInvoiceIdByEventId', $eventId));

		$page->field('eventFieldsAreSet', 1);
	}

	if(! $page->field('invoiceFieldsAreSet') && $invoiceId ne '')
	{
		my $invoiceInfo = $STMTMGR_INVOICE->getRowAsHash($page, STMTMGRFLAG_NONE, 'selInvoice', $invoiceId);
		$page->field('attendee_id', $invoiceInfo->{client_id});
		#$page->field('reference', $invoiceInfo->{reference});
		$page->field('proc_diags', $invoiceInfo->{claim_diags});

		my $invoiceCopayItem = $STMTMGR_INVOICE->getRowAsHash($page, STMTMGRFLAG_NONE, 'selInvoiceItemsByType', $invoiceId, App::Universal::INVOICEITEMTYPE_COPAY);
		$page->field('copay_amt', $invoiceCopayItem->{extended_cost});

		my $procedures = $STMTMGR_INVOICE->getRowsAsHashList($page, STMTMGRFLAG_NONE, 'selInvoiceProcedureItems', $invoiceId, App::Universal::INVOICEITEMTYPE_SERVICE, App::Universal::INVOICEITEMTYPE_LAB);
		$page->param('_f_proc_service_place', $procedures->[0]->{hcfa_service_place});
		my $totalProcs = scalar(@{$procedures});
		foreach my $idx (0..$totalProcs)
		{
			#NOTE: data_text_a stores the indexes of the rel_diags (which are actual codes, not pointers)

			my $line = $idx + 1;
			$page->param("_f_proc_$line\_item_id", $procedures->[$idx]->{item_id});
			$page->param("_f_proc_$line\_dos_begin", $procedures->[$idx]->{service_begin_date});
			$page->param("_f_proc_$line\_dos_end", $procedures->[$idx]->{service_end_date});
			$page->param("_f_proc_$line\_service_type", $procedures->[$idx]->{hcfa_service_type});
			$page->param("_f_proc_$line\_procedure", $procedures->[$idx]->{code});
			$page->param("_f_proc_$line\_modifier", $procedures->[$idx]->{modifier});
			$page->param("_f_proc_$line\_units", $procedures->[$idx]->{quantity});
			$page->param("_f_proc_$line\_charges", $procedures->[$idx]->{unit_cost});
			$page->param("_f_proc_$line\_emg", @{[ ($procedures->[$idx]->{emergency} == 1 ? 'on' : '' ) ]});
			$page->param("_f_proc_$line\_comments", $procedures->[$idx]->{comments});
			$page->param("_f_proc_$line\_diags", $procedures->[$idx]->{data_text_a});
			$page->param("_f_proc_$line\_actual_diags", $procedures->[$idx]->{rel_diags});
		}


		$STMTMGR_TRANSACTION->createFieldsFromSingleRow($page, STMTMGRFLAG_NONE, 'selTransCreateClaim', $invoiceInfo->{main_transaction});
		$STMTMGR_INVOICE->createFieldsFromSingleRow($page, STMTMGRFLAG_NONE, 'selInvoiceAttrIllness',$invoiceId);
		$STMTMGR_INVOICE->createFieldsFromSingleRow($page, STMTMGRFLAG_NONE, 'selInvoiceAttrDisability',$invoiceId);
		$STMTMGR_INVOICE->createFieldsFromSingleRow($page, STMTMGRFLAG_NONE, 'selInvoiceAttrHospitalization',$invoiceId);
		#$STMTMGR_INVOICE->createFieldsFromSingleRow($page, STMTMGRFLAG_NONE, 'selInvoiceAttrPatientSign',$invoiceId);
		$STMTMGR_INVOICE->createFieldsFromSingleRow($page, STMTMGRFLAG_NONE, 'selInvoiceAttrAssignment',$invoiceId);
		$STMTMGR_INVOICE->createFieldsFromSingleRow($page, STMTMGRFLAG_NONE, 'selInvoiceAuthNumber',$invoiceId);
		$STMTMGR_INVOICE->createFieldsFromSingleRow($page, STMTMGRFLAG_NONE, 'selInvoiceDeductible',$invoiceId);

		my $cntrlData = $STMTMGR_INVOICE->getRowAsHash($page, STMTMGRFLAG_NONE, 'selInvoiceAttr', $invoiceId, 'Patient/Control Number');
		$page->field('cntrl_num_item_id', $cntrlData->{item_id});
		$page->field('control_number', $cntrlData->{value_text});

		my $billContactData = $STMTMGR_INVOICE->getRowAsHash($page, STMTMGRFLAG_NONE, 'selInvoiceAttr', $invoiceId, 'Service Provider/Facility/Billing/Contact');
		$page->field('bill_contact_item_id', $billContactData->{item_id});
		$page->field('billing_contact', $billContactData->{value_text});
		$page->field('billing_phone', $billContactData->{value_textb});

		my $payToOrg = $STMTMGR_INVOICE->getRowAsHash($page, STMTMGRFLAG_NONE, 'selInvoiceAttr', $invoiceId, 'Pay To Org/Name');
		$page->field('pay_to_org_item_id', $payToOrg->{item_id});
		$page->field('pay_to_org_id', $payToOrg->{value_textb});

		my $payToOrgAddr = $STMTMGR_INVOICE->getRowAsHash($page, STMTMGRFLAG_NONE, 'selInvoiceAddr', $invoiceId, 'Pay To Org');
		$page->field('pay_to_org_addr_item_id', $payToOrgAddr->{item_id});

		my $payToOrgPhone = $STMTMGR_INVOICE->getRowAsHash($page, STMTMGRFLAG_NONE, 'selInvoiceAttr', $invoiceId, 'Pay To Org/Phone');
		$page->field('pay_to_org_phone_item_id', $payToOrgPhone->{item_id});

		my $claimFiling = $STMTMGR_INVOICE->getRowAsHash($page, STMTMGRFLAG_NONE, 'selInvoiceAttr', $invoiceId, 'Claim Filing/Indicator');
		$page->field('claim_filing_item_id', $claimFiling->{item_id});

		my $assignment = $STMTMGR_INVOICE->getRowAsHash($page, STMTMGRFLAG_NONE, 'selInvoiceAttr', $invoiceId, 'Assignment of Benefits');
		my $value = $assignment->{value_int} ? 1 : 0;
		$page->field('assignment_item_id', $assignment->{item_id});
		$page->field('accept_assignment', $value);

		my $condRelTo = $STMTMGR_INVOICE->getRowAsHash($page, STMTMGRFLAG_NONE, 'selInvoiceAttrCondition', $invoiceId);
		my @condRelToIds = ();
		my @condRelToCaps = split(', ', $condRelTo->{value_text});
		foreach my $condition (@condRelToCaps)
		{
			my $conditionIds = $STMTMGR_INVOICE->getSingleValue($page, STMTMGRFLAG_NONE, 'selInvoiceConditionId', $condition);

			push(@condRelToIds, $conditionIds);
		}
		$page->field('condition_item_id', $condRelTo->{condition_item_id});
		$page->field('accident', @condRelToIds);
		$page->field('accident_state', $condRelTo->{value_textb});

		$page->field('invoiceFieldsAreSet', 1);
	}

	if( my $personId = $page->field('attendee_id') || $page->param('person_id') || $page->param('attendee_id') )
	{
		setInsuranceFields($self, $page, $command, $activeExecMode, $flags, $invoiceId, $personId);
	}

	return unless $flags & CGI::Dialog::DLGFLAG_ADD_DATAENTRY_INITIAL;

	#set service facility to session org
	if(my $orgId = $page->session('org_id'))
	{
		$page->field('service_facility_id', $orgId);
		#$page->field('billing_facility_id', $orgId);
		#$page->field('pay_to_org_id', $orgId);
	}
}

sub setInsuranceFields
{
	my ($self, $page, $command, $activeExecMode, $flags, $invoiceId, $personId) = @_;

	# CONSTANTS ---------------------------------------------------------------

	#party types
	my $billPartyTypeClient = App::Universal::INVOICEBILLTYPE_CLIENT;
	my $billPartyTypePerson = App::Universal::INVOICEBILLTYPE_THIRDPARTYPERSON;
	my $billPartyTypeOrg = App::Universal::INVOICEBILLTYPE_THIRDPARTYORG;
	my $billPartyTypeIns = App::Universal::INVOICEBILLTYPE_THIRDPARTYINS;

	#bill sequences
	my $primary = App::Universal::INSURANCE_PRIMARY;
	my $secondary = App::Universal::INSURANCE_SECONDARY;
	my $tertiary = App::Universal::INSURANCE_TERTIARY;

	#fake product names
	my $fakeProdNameThirdParty = App::Universal::INSURANCE_FAKE_CLIENTBILL;
	my $fakeProdNameSelfPay = App::Universal::INSURANCE_FAKE_SELFPAY;

	# -------------------------------------------------------------------------



	#Create drop-down of Payers

	my $payers = $STMTMGR_INSURANCE->getRowsAsHashList($page, STMTMGRFLAG_CACHE, 'selPayerChoicesByOwnerPersonId', $personId, $personId, $personId);
	my @insurPlans = ();
	my @wkCompPlans = ();
	my @thirdParties = ();
	foreach my $ins (@{$payers})
	{
		if($ins->{group_name} eq 'Insurance')
		{
			push(@insurPlans, "$ins->{bill_seq}($ins->{plan_name})");
		}
		elsif($ins->{group_name} eq 'Workers Compensation')
		{
			push(@wkCompPlans, "Work Comp($ins->{plan_name})");
		}
		elsif($ins->{group_name} eq 'Third-Party')
		{
			push(@thirdParties, "$ins->{group_name}($ins->{plan_name})");
		}
	}

	my $insurances = join(' / ', @insurPlans) if @insurPlans;
	$insurances = "$insurances;" if $insurances;

	my $workComp = join(';', @wkCompPlans) if @wkCompPlans;
	$workComp = "$workComp;" if $workComp;

	my $thirdParty = join(';', @thirdParties) if @thirdParties;
	$thirdParty = "$thirdParty;" if $thirdParty;

	my $thirdPartyOther = 'Third-Party Payer;';
	my $selfPay = 'Self-Pay;';

	$self->getField('payer')->{selOptions} = "$insurances $workComp $thirdParty $thirdPartyOther $selfPay";


	#Other third party payer if one is not given
	#if($page->field('payer') ne 'Third-Party Payer')
	#{
	#	$self->updateFieldFlags('other_payer', FLDFLAG_INVISIBLE, 1);
	#}
	#if($page->field('payer') eq 'Third-Party Payer')
	#{
	#	$page->addError('error');
	#	my $otherPayerField = $self->getField('other_payer');
	#	$otherPayerField->invalidate($page, "Please provide an alternate payer");
	#}
}

sub handlePayers
{
	my ($self, $page, $command, $flags) = @_;

	my $personId = $page->field('attendee_id');

	#CONSTANTS -------------------------------------------

	#bill sequences
	my $primary = App::Universal::INSURANCE_PRIMARY;
	my $secondary = App::Universal::INSURANCE_SECONDARY;
	my $tertiary = App::Universal::INSURANCE_TERTIARY;
	my $quaternary = App::Universal::INSURANCE_QUATERNARY;
	my $workerscomp = App::Universal::INSURANCE_WORKERSCOMP;

	#claim types
	my $typeSelfPay = App::Universal::CLAIMTYPE_SELFPAY;
	my $typeWorkComp = App::Universal::CLAIMTYPE_WORKERSCOMP;
	my $typeClient = App::Universal::CLAIMTYPE_CLIENT;

	#fake values for self-pay and third party payers
	my $fakeProdNameThirdParty = App::Universal::INSURANCE_FAKE_CLIENTBILL;
	my $fakeProdNameSelfPay = App::Universal::INSURANCE_FAKE_SELFPAY;

	# -----------------------------------------------------


	my $claimType = '';
	my $payer = $page->field('payer');
	if($payer eq 'Self-Pay')
	{
		$page->field('primary_payer', $fakeProdNameSelfPay);
		$claimType = $typeSelfPay;
	}
	elsif($payer eq 'Third-Party Payer')
	{
		$page->field('primary_payer', $fakeProdNameThirdParty);
		#$page->field('third_party_payer_id', id from inserted fields goes here);
		$claimType = $typeClient;
	}
	else
	{
		if($payer =~ '\/')
		{
			my @payerSeq = split(' \/ ', $payer);
			foreach (@payerSeq)
			{
				my @singlePayer = split('\(', $_);
				if($singlePayer[0] eq 'Primary')
				{
					my $primIns = $STMTMGR_INSURANCE->getRowAsHash($page, STMTMGRFLAG_NONE, 'selInsuranceByBillSequence', $primary, $personId);
					$claimType = $primIns->{ins_type};
					$page->field('primary_payer', $primIns->{product_name});
				}
				elsif($singlePayer[0] eq 'Secondary')
				{
					my $secIns = $STMTMGR_INSURANCE->getRowAsHash($page, STMTMGRFLAG_NONE, 'selInsuranceByBillSequence', $secondary, $personId);
					#$claimType = $secIns->{ins_type};
					$page->field('secondary_payer', $secIns->{product_name});
				}
				elsif($singlePayer[0] eq 'Tertiary')
				{
					my $tertIns = $STMTMGR_INSURANCE->getRowAsHash($page, STMTMGRFLAG_NONE, 'selInsuranceByBillSequence', $tertiary, $personId);
					#$claimType = $tertIns->{ins_type};
					$page->field('tertiary_payer', $tertIns->{product_name});
				}
				elsif($singlePayer[0] eq 'Quaternary')
				{
					my $quatIns = $STMTMGR_INSURANCE->getRowAsHash($page, STMTMGRFLAG_NONE, 'selInsuranceByBillSequence', $quaternary, $personId);
					#$claimType = $quatIns->{ins_type};
					$page->field('quaternary_payer', $quatIns->{product_name});
				}
			}
		}
		else
		{
			my @nonInsPayer = split('\(', $payer);
			if($nonInsPayer[0] eq 'Primary')
			{
				my @primaryPlan = split('\)', $nonInsPayer[1]);
				my $primIns = $STMTMGR_INSURANCE->getRowAsHash($page, STMTMGRFLAG_NONE, 'selInsuranceByBillSequence', $primary, $personId);
				$claimType = $primIns->{ins_type};
				$page->field('primary_payer', $primIns->{product_name});
			}
			elsif($nonInsPayer[0] eq 'Work Comp')
			{
				my @wcPlanName = split('\)', $nonInsPayer[1]);
				my $workCompPlanInfo = $STMTMGR_INSURANCE->getRowAsHash($page, STMTMGRFLAG_NONE, 'selInsuranceByPlanNameAndPersonAndInsType', $wcPlanName[0], $personId, $typeWorkComp);
				$claimType = $typeWorkComp;
				$page->field('primary_payer', $workCompPlanInfo->{product_name});
			}
			elsif($nonInsPayer[0] eq 'Third-Party')
			{
				my @thirdPartyOrgId = split('\)', $nonInsPayer[1]);
				my $thirdPartyPlan = $STMTMGR_INSURANCE->getRowAsHash($page, STMTMGRFLAG_NONE, 'selInsuranceByPersonOwnerOrgOwnerAndInsType', $personId, $thirdPartyOrgId[0], $typeClient);
				$claimType = $typeClient;
				$page->field('primary_payer', $fakeProdNameThirdParty);
				$page->field('third_party_payer_id', $thirdPartyPlan->{owner_org_id});
			}
		}
	}

	addTransactionAndInvoice($self, $page, $command, $flags, $claimType);
}

sub addTransactionAndInvoice
{
	my ($self, $page, $command, $flags, $claimType) = @_;
	$command ||= 'add';

	my $sessOrg = $page->session('org_id');
	my $sessUser = $page->session('user_id');
	my $personId = $page->field('attendee_id');
	my $editInvoiceId = $page->param('invoice_id');
	my $editTransId = $page->field('trans_id');
	my $timeStamp = $page->getTimeStamp();

	#CONSTANTS -------------------------------------------

	#invoice constants
	my $invoiceType = App::Universal::INVOICETYPE_HCFACLAIM;
	my $invoiceStatus = App::Universal::INVOICESTATUS_CREATED;

	#entity types
	my $entityTypePerson = App::Universal::ENTITYTYPE_PERSON;
	my $entityTypeOrg = App::Universal::ENTITYTYPE_ORG;

	#trans status
	my $transStatus = App::Universal::TRANSSTATUS_ACTIVE;

	#-------------------------------------------------------------------------------------------------------------------------------

	my $billingFacility = $page->field('billing_facility_id');
	my $transId = $page->schemaAction(
			'Transaction', $command,
			trans_id => $editTransId || undef,
			trans_type => $page->field('trans_type'),
			trans_status => defined $transStatus ? $transStatus : undef,
			parent_event_id => $page->field('event_id') || undef,
			caption => $page->field('subject') || undef,
			service_facility_id => $page->field('service_facility_id') || undef,
			billing_facility_id => $billingFacility || undef,
			provider_id => $page->field('provider_id') || undef,
			care_provider_id => $page->field('care_provider_id') || undef,
			trans_owner_type => defined $entityTypePerson ? $entityTypePerson : undef,
			trans_owner_id => $personId || undef,
			initiator_type => defined $entityTypePerson ? $entityTypePerson : undef,
			initiator_id => $personId || undef,
			receiver_type => defined $entityTypeOrg ? $entityTypeOrg : undef,
			receiver_id => $page->session('org_id') || undef,
			init_onset_date => $page->field('illness_begin_date') || undef,
			curr_onset_date => $page->field('illness_end_date') || undef,
			bill_type => defined $claimType ? $claimType : undef,
			data_text_a => $page->field('ref_id') || undef,
			data_text_b => $page->field('comments') || undef,
			trans_begin_stamp => $timeStamp || undef,
			_debug => 0
		);

	$transId = $command eq 'add' ? $transId : $editTransId;


	my @claimDiags = split(/\s*,\s*/, $page->field('proc_diags'));
	App::IntelliCode::incrementUsage($page, 'Icd', \@claimDiags, $sessUser, $sessOrg);

	my $invoiceId = $page->schemaAction(
			'Invoice', $command,
			invoice_id => $editInvoiceId || undef,
			invoice_type => defined $invoiceType ? $invoiceType : undef,
			invoice_subtype => defined $claimType ? $claimType : undef,
			invoice_status => defined $invoiceStatus ? $invoiceStatus : undef,
			invoice_date => $page->getDate() || undef,
			main_transaction => $transId || undef,
			submitter_id => $page->session('user_id') || undef,
			claim_diags => join(', ', @claimDiags) || undef,
			owner_type => App::Universal::ENTITYTYPE_ORG,
			owner_id => $page->session('org_id') || undef,
			client_type => App::Universal::ENTITYTYPE_PERSON,
			client_id => $personId || undef,
			_debug => 0
		);

	$invoiceId = $command eq 'add' ? $invoiceId : $editInvoiceId;

	$page->param('invoice_id', $invoiceId);


	handleInvoiceAttrs($self, $page, $command, $flags, $invoiceId);
}

sub handleInvoiceAttrs
{
	my ($self, $page, $command, $flags, $invoiceId) = @_;
	$command ||= 'add';

	my $todaysDate = $page->getDate();
	my $personId = $page->field('attendee_id');
	my $billingFacility = $page->field('billing_facility_id');

	#CONSTANTS
	my $textValueType = App::Universal::ATTRTYPE_TEXT;
	my $intValueType = App::Universal::ATTRTYPE_INTEGER;
	my $phoneValueType = App::Universal::ATTRTYPE_PHONE;
	my $boolValueType = App::Universal::ATTRTYPE_BOOLEAN;
	my $currencyValueType = App::Universal::ATTRTYPE_CURRENCY;
	my $durationValueType = App::Universal::ATTRTYPE_DURATION;
	my $historyValueType = App::Universal::ATTRTYPE_HISTORY;


	## Then, create invoice attribute indicating that this is the first (primary) claim
	$page->schemaAction(
			'Invoice_Attribute', 'add',
			parent_id => $invoiceId || undef,
			item_name => 'Submission Order',
			value_type => defined $intValueType ? $intValueType : undef,
			value_int => 0,
			_debug => 0
		) if $command ne 'update';

	## Then, create invoice attribute for history of invoice status
	my $action = $command eq 'add' ? 'Created claim' : 'Updated claim';

	$page->schemaAction(
			'Invoice_Attribute', 'add',
			parent_id => $invoiceId || undef,
			item_name => 'Invoice/History/Item',
			value_type => defined $historyValueType ? $historyValueType : undef,
			value_text => $action,
			value_textB => $page->field('comments') || undef,
			value_date => $todaysDate,
			_debug => 0
		);

	## Then, create some invoice attributes for HCFA (the rest are found in the Procedure dialog):
	#	 Accident Related To, Prior Auth Num, Deduct Balance, Accept Assignment, Ref Physician Name/Id,
	#	 Illness/Disability/Hospitalization Dates

	my $condRelToAuto = App::Universal::CONDRELTO_AUTO;
	my $condRelToFakeNone = App::Universal::CONDRELTO_FAKE_NONE;
	my @condRelToIds = $page->field('accident');
	my @condRelToCaptions = ();
	my $state = '';

	foreach my $relToId (@condRelToIds)
	{
		next if $relToId == $condRelToFakeNone;

		my $condition = $STMTMGR_TRANSACTION->getSingleValue($page, STMTMGRFLAG_NONE, 'selCondition', $relToId);

		push(@condRelToCaptions, $condition);

		$state = $page->field('accident_state') if $relToId == $condRelToAuto;
	}

	$page->schemaAction(
			'Invoice_Attribute', $command,
			item_id => $page->field('condition_item_id') || undef,
			parent_id => $invoiceId || undef,
			item_name => 'Condition/Related To',
			value_type => defined $textValueType ? $textValueType : undef,
			value_text => join(', ', @condRelToCaptions) || 'None',
			value_textB => $state || undef,
			_debug => 0
	);


	#referring physician information
	if(my $refPhysId = $page->field('ref_id'))
	{
		my $refPhysInfo = $STMTMGR_PERSON->getRowAsHash($page, STMTMGRFLAG_NONE, 'selRegistry', $refPhysId);
		my $refPhysUpin = $STMTMGR_PERSON->getRowAsHash($page, STMTMGRFLAG_NONE, 'selAttributeByItemNameAndValueTypeAndParent', $refPhysId, 'UPIN', App::Universal::ATTRTYPE_LICENSE);
		my $refPhysState = $STMTMGR_PERSON->getRowAsHash($page, STMTMGRFLAG_NONE, 'selPhysStateLicense', $refPhysId, 1);
		$STMTMGR_INVOICE->execute($page, STMTMGRFLAG_NONE, 'delRefProviderAttrs', $invoiceId);

		$page->schemaAction(
				'Invoice_Attribute', 'add',
				parent_id => $invoiceId || undef,
				item_name => 'Ref Provider/Name/First',
				value_type => defined $textValueType ? $textValueType : undef,
				value_text => $refPhysInfo->{name_first} || undef,
				value_textB => $refPhysId || undef,
				_debug => 0
			);

		$page->schemaAction(
				'Invoice_Attribute', 'add',
				parent_id => $invoiceId || undef,
				item_name => 'Ref Provider/Name/Middle',
				value_type => defined $textValueType ? $textValueType : undef,
				value_text => $refPhysInfo->{name_middle} || undef,
				value_textB => $refPhysId || undef,
				_debug => 0
			) if $refPhysInfo->{name_middle} ne '';

		$page->schemaAction(
				'Invoice_Attribute', 'add',
				parent_id => $invoiceId || undef,
				item_name => 'Ref Provider/Name/Last',
				value_type => defined $textValueType ? $textValueType : undef,
				value_text => $refPhysInfo->{name_last} || undef,
				value_textB => $refPhysId || undef,
				_debug => 0
			);

		$page->schemaAction(
				'Invoice_Attribute', 'add',
				parent_id => $invoiceId || undef,
				item_name => 'Ref Provider/Identification',
				value_type => defined $textValueType ? $textValueType : undef,
				value_text => $refPhysUpin->{value_text} || undef,
				value_textB => $refPhysState->{value_textb} || undef,
				_debug => 0
			);
		#end referring phys attrs
	}


	$page->schemaAction(
			'Invoice_Attribute', $command,
			item_id => $page->field('prior_auth_item_id') || undef,
			parent_id => $invoiceId || undef,
			item_name => 'Prior Authorization Number',
			value_type => defined $textValueType ? $textValueType : undef,
			value_text => $page->field('prior_auth') || undef,
			_debug => 0
		);

	$page->schemaAction(
			'Invoice_Attribute', $command,
			item_id => $page->field('deduct_item_id') || undef,
			parent_id => $invoiceId || undef,
			item_name => 'Patient/Deductible/Balance',
			value_type => defined $currencyValueType ? $currencyValueType : undef,
			value_text => $page->field('deduct_balance'),
			_debug => 0
		);

	my $acceptAssign = $page->field('accept_assignment') eq '' ? 0 : 1;
	$page->schemaAction(
			'Invoice_Attribute', $command,
			item_id => $page->field('assignment_item_id') || undef,
			parent_id => $invoiceId || undef,
			item_name => 'Assignment of Benefits',
			value_type => defined $boolValueType ? $boolValueType : undef,
			value_int => defined $acceptAssign ? $acceptAssign : undef,
			_debug => 0
		);

	$page->schemaAction(
			'Invoice_Attribute', $command,
			item_id => $page->field('illness_item_id') || undef,
			parent_id => $invoiceId || undef,
			item_name => 'Patient/Illness/Dates',
			value_type => defined $durationValueType ? $durationValueType : undef,
			value_date => $page->field('illness_begin_date') || undef,
			value_dateEnd => $page->field('illness_end_date') || undef,
			_debug => 0
		);

	$page->schemaAction(
			'Invoice_Attribute', $command,
			item_id => $page->field('disability_item_id') || undef,
			parent_id => $invoiceId || undef,
			item_name => 'Patient/Disability/Dates',
			value_type => defined $durationValueType ? $durationValueType : undef,
			value_date => $page->field('disability_begin_date') || undef,
			value_dateEnd => $page->field('disability_end_date') || undef,
			_debug => 0
		);

	$page->schemaAction(
			'Invoice_Attribute', $command,
			item_id => $page->field('hospital_item_id') || undef,
			parent_id => $invoiceId || undef,
			item_name => 'Patient/Hospitalization/Dates',
			value_type => defined $durationValueType ? $durationValueType : undef,
			value_date => $page->field('hospitalization_begin_date') || undef,
			value_dateEnd => $page->field('hospitalization_end_date') || undef,
			_debug => 0
		);

	$page->schemaAction(
			'Invoice_Attribute', $command,
			item_id => $page->field('cntrl_num_item_id') || undef,
			parent_id => $invoiceId,
			item_name => 'Patient/Control Number',
			value_type => defined $textValueType ? $textValueType : undef,
			value_text => $invoiceId || undef,
			_debug => 0
		);


	my $billingContact = $STMTMGR_ORG->getRowAsHash($page, STMTMGRFLAG_CACHE, 'selAttribute', $billingFacility, 'Contact Information');
	my $contactName = $page->field('billing_contact') eq '' ? $billingContact->{value_text} : $page->field('billing_contact');
	my $contactPhone = $page->field('billing_phone') eq '' ? $billingContact->{value_textb} : $page->field('billing_phone');

	$page->schemaAction(
			'Invoice_Attribute', $command,
			item_id => $page->field('bill_contact_item_id') || undef,
			parent_id => $invoiceId,
			item_name => 'Service Provider/Facility/Billing/Contact',
			value_type => defined $textValueType ? $textValueType : undef,
			value_text => $contactName || undef,
			value_textB => $contactPhone || undef,
			_debug => 0
		);

	my $secondaryIns = App::Universal::INSURANCE_SECONDARY;
	my $personSecInsur = $STMTMGR_INSURANCE->getRowAsHash($page, STMTMGRFLAG_CACHE, 'selPersonInsurance', $personId, $secondaryIns);
	my $claimFiling = 'P';
	$claimFiling = 'M' if $personSecInsur->{ins_internal_id} ne '';

	$page->schemaAction(
			'Invoice_Attribute', $command,
			item_id => $page->field('claim_filing_item_id') || undef,
			parent_id => $invoiceId,
			item_name => 'Claim Filing/Indicator',
			value_type => defined $textValueType ? $textValueType : undef,
			value_text => $claimFiling,
			_debug => 0
		);

	my $payToOrgId = $page->field('pay_to_org_id');
	my $payToFacility = $STMTMGR_ORG->getRowAsHash($page, STMTMGRFLAG_CACHE, 'selOrgAddressByAddrName', $payToOrgId, 'Mailing');
	my $payToFacilityName = $STMTMGR_ORG->getSingleValue($page, STMTMGRFLAG_NONE, 'selOrgSimpleNameById', $payToOrgId);
	my $payToFacilityPhone = $STMTMGR_ORG->getRowAsHash($page, STMTMGRFLAG_NONE, 'selAttributeByItemNameAndValueTypeAndParent', $payToOrgId, 'Primary', App::Universal::ATTRTYPE_PHONE);

	$page->schemaAction(
			'Invoice_Attribute', $command,
			item_id => $page->field('pay_to_org_item_id') || undef,
			parent_id => $invoiceId,
			item_name => 'Pay To Org/Name',
			value_type => defined $textValueType ? $textValueType : undef,
			value_text => $payToFacilityName || undef,
			value_textB => $payToOrgId || undef,
			_debug => 0
	);

	$page->schemaAction(
			'Invoice_Attribute', $command,
			item_id => $page->field('pay_to_org_phone_item_id') || undef,
			parent_id => $invoiceId,
			item_name => 'Pay To Org/Phone',
			value_type => defined $phoneValueType ? $phoneValueType : undef,
			value_text => $payToFacilityPhone->{value_text} || undef,
			value_textB => $payToOrgId || undef,
			_debug => 0
	);

	$page->schemaAction(
			'Invoice_Address', $command,
			item_id => $page->field('pay_to_org_addr_item_id') || undef,
			parent_id => $invoiceId,
			address_name => 'Pay To Org',
			line1 => $payToFacility->{line1},
			line2 => $payToFacility->{line2},
			city => $payToFacility->{city},
			state => $payToFacility->{state},
			zip => $payToFacility->{zip},
			_debug => 0
		);

	addProcedureItems($self, $page, $command, $flags, $invoiceId);

	handleBillingInfo($self, $page, $command, $flags, $invoiceId) if $command ne 'remove';
}

sub handleBillingInfo
{
	my ($self, $page, $command, $flags, $invoiceId) = @_;
	my $personId = $page->field('attendee_id');


	#CONSTANTS ---------------------------------------------------------------

	#fake values for self-pay and third party payers
	my $fakeProdNameThirdParty = App::Universal::INSURANCE_FAKE_CLIENTBILL;
	my $fakeProdNameSelfPay = App::Universal::INSURANCE_FAKE_SELFPAY;

	#bill party types
	my $billPartyTypeClient = App::Universal::INVOICEBILLTYPE_CLIENT;
	my $billPartyTypePerson = App::Universal::INVOICEBILLTYPE_THIRDPARTYPERSON;
	my $billPartyTypeOrg = App::Universal::INVOICEBILLTYPE_THIRDPARTYORG;
	my $billPartyTypeIns = App::Universal::INVOICEBILLTYPE_THIRDPARTYINS;


	#------DELETE ALL PAYERS WHEN UPDATING OR REMOVING

	$STMTMGR_INVOICE->execute($page, STMTMGRFLAG_NONE, 'delInvoiceBillingParties', $invoiceId) if $command ne 'add';



	#------PRIMARY PAYER

	my $primPayer = $page->field('primary_payer');
	if($primPayer)
	{
		my $billParty = '';
		my $billToId = '';
		my $billInsId = '';
		my $billAmt = '';
		my $billPct = '';
		my $billDate = '';
		my $billStatus = '';
		my $billResult = '';

		if($primPayer == $fakeProdNameSelfPay)
		{
			$billParty = $billPartyTypeClient;
			$billToId = $personId;
			#$billAmt = '';
			#$billPct = '';
			#$billDate = '';
			#$billStatus = '';
			#$billResult = '';
		}
		elsif($primPayer == $fakeProdNameThirdParty)
		{
			#my $insInfo = $STMTMGR_INSURANCE->getRowAsHash($page, STMTMGRFLAG_NONE, 'selInsuranceByPersonOwnerOrgOwnerAndInsType', $personId, $thirdPartyId, App::Universal::CLAIMTYPE_CLIENT);

			$billParty = $billPartyTypeOrg;
			$billToId = $page->field('third_party_payer_id');
			#$billAmt = '';
			#$billPct = '';
			#$billDate = '';
			#$billStatus = '';
			#$billResult = '';
		}
		else
		{
			my $insInfo = $STMTMGR_INSURANCE->getRowAsHash($page, STMTMGRFLAG_NONE, 'selInsuranceByOwnerAndProductName', $primPayer, $personId);
			$billParty = $billPartyTypeIns;
			$billToId = $insInfo->{ins_org_id};
			$billInsId = $insInfo->{ins_internal_id};
			#$billAmt = '';
			$billPct = $insInfo->{percentage_pay};
			#$billDate = '';
			#$billStatus = '';
			#$billResult = '';

			$page->field('copay_amt', $insInfo->{copay_amt});
		}

		my $primBillSeq = App::Universal::PAYER_PRIMARY;
		$page->schemaAction(
			'Invoice_Billing', 'add',
			invoice_id => $invoiceId || undef,
			bill_sequence => defined $primBillSeq ? $primBillSeq : undef,
			bill_party_type => defined $billParty ? $billParty : undef,
			bill_to_id => $billToId || undef,
			bill_ins_id => $billInsId || undef,
			bill_amount => $billAmt || undef,
			bill_pct => $billPct || undef,
			bill_date => $billDate || undef,
			bill_status => $billStatus || undef,
			bill_result => $billResult || undef,
			_debug => 0
		);
	}


	#------SECONDARY PAYER

	my $secondPayer = $page->field('secondary_payer');
	if($secondPayer ne '' && $secondPayer ne $primPayer)
	{
		my $billParty = '';
		my $billToId = '';
		my $billInsId = '';
		my $billAmt = '';
		my $billPct = '';
		my $billDate = '';
		my $billStatus = '';
		my $billResult = '';

		my $insInfo = $STMTMGR_INSURANCE->getRowAsHash($page, STMTMGRFLAG_NONE, 'selInsuranceByOwnerAndProductName', $secondPayer, $personId);
		$billParty = $billPartyTypeIns;
		$billToId = $insInfo->{ins_org_id};
		$billInsId = $insInfo->{ins_internal_id};
		#$billAmt = '';
		$billPct = $insInfo->{percentage_pay};
		#$billDate = '';
		#$billStatus = '';
		#$billResult = '';


		my $secBillSeq = App::Universal::PAYER_SECONDARY;
		$page->schemaAction(
			'Invoice_Billing', 'add',
			invoice_id => $invoiceId || undef,
			bill_sequence => defined $secBillSeq ? $secBillSeq : undef,
			bill_party_type => defined $billParty ? $billParty : undef,
			bill_to_id => $billToId || undef,
			bill_ins_id => $billInsId || undef,
			bill_amount => $billAmt || undef,
			bill_pct => $billPct || undef,
			bill_date => $billDate || undef,
			bill_status => $billStatus || undef,
			bill_result => $billResult || undef,
			_debug => 0
		);
	}



	#------TERTIARY PAYER

	my $tertPayer = $page->field('tertiary_payer');
	if($tertPayer ne '' && $tertPayer ne $secondPayer && $tertPayer ne $primPayer)
	{
		my $billParty = '';
		my $billToId = '';
		my $billInsId = '';
		my $billAmt = '';
		my $billPct = '';
		my $billDate = '';
		my $billStatus = '';
		my $billResult = '';

		my $insInfo = $STMTMGR_INSURANCE->getRowAsHash($page, STMTMGRFLAG_NONE, 'selInsuranceByOwnerAndProductName', $tertPayer, $personId);
		$billParty = $billPartyTypeIns;
		$billToId = $insInfo->{ins_org_id};
		$billInsId = $insInfo->{ins_internal_id};
		#$billAmt = '';
		$billPct = $insInfo->{percentage_pay};
		#$billDate = '';
		#$billStatus = '';
		#$billResult = '';


		my $tertBillSeq = $secondPayer ne '' && $secondPayer ne $primPayer ? App::Universal::PAYER_TERTIARY : App::Universal::PAYER_SECONDARY;
		$page->schemaAction(
			'Invoice_Billing', 'add',
			invoice_id => $invoiceId || undef,
			bill_sequence => defined $tertBillSeq ? $tertBillSeq : undef,
			bill_party_type => defined $billParty ? $billParty : undef,
			bill_to_id => $billToId || undef,
			bill_ins_id => $billInsId || undef,
			bill_amount => $billAmt || undef,
			bill_pct => $billPct || undef,
			bill_date => $billDate || undef,
			bill_status => $billStatus || undef,
			bill_result => $billResult || undef,
			_debug => 0
		);
	}



	#------QUATERNARY PAYER

	my $quatPayer = $page->field('quaternary_payer');
	if($quatPayer ne '' && $quatPayer ne $tertPayer && $quatPayer ne $secondPayer && $quatPayer ne $primPayer)
	{
		my $billParty = '';
		my $billToId = '';
		my $billInsId = '';
		my $billAmt = '';
		my $billPct = '';
		my $billDate = '';
		my $billStatus = '';
		my $billResult = '';

		my $insInfo = $STMTMGR_INSURANCE->getRowAsHash($page, STMTMGRFLAG_NONE, 'selInsuranceByOwnerAndProductName', $quatPayer, $personId);
		$billParty = $billPartyTypeIns;
		$billToId = $insInfo->{ins_org_id};
		$billInsId = $insInfo->{ins_internal_id};
		#$billAmt = '';
		$billPct = $insInfo->{percentage_pay};
		#$billDate = '';
		#$billStatus = '';
		#$billResult = '';


		my $quatBillSeq = App::Universal::PAYER_QUATERNARY;
		$page->schemaAction(
			'Invoice_Billing', 'add',
			invoice_id => $invoiceId || undef,
			bill_sequence => defined $quatBillSeq ? $quatBillSeq : undef,
			bill_party_type => defined $billParty ? $billParty : undef,
			bill_to_id => $billToId || undef,
			bill_ins_id => $billInsId || undef,
			bill_amount => $billAmt || undef,
			bill_pct => $billPct || undef,
			bill_date => $billDate || undef,
			bill_status => $billStatus || undef,
			bill_result => $billResult || undef,
			_debug => 0
		);
	}

	#------BY DEFAULT, ADD SELF-PAY AS THE LAST POSSIBLE PAYER IF IT HAS NOT ALREADY BEEN SELECTED

	if($primPayer != $fakeProdNameSelfPay && $quatPayer eq '')
	{
		my $billParty = '';
		my $billToId = '';
		my $billInsId = '';
		my $billAmt = '';
		my $billPct = '';
		my $billDate = '';
		my $billStatus = '';
		my $billResult = '';

		my $lastBillSeq = '';
		if( ($secondPayer eq '' && $tertPayer eq '') || ($secondPayer eq $primPayer && $tertPayer eq $primPayer) )
		{
			$lastBillSeq = App::Universal::PAYER_SECONDARY;
		}
		elsif( ($secondPayer ne '' && $secondPayer ne $primPayer) && ($tertPayer eq '' || $tertPayer eq $primPayer || $tertPayer eq $secondPayer) )
		{
			$lastBillSeq = App::Universal::PAYER_TERTIARY;
		}
		else
		{
			$lastBillSeq = App::Universal::PAYER_QUATERNARY;
		}

		$page->schemaAction(
			'Invoice_Billing', 'add',
			invoice_id => $invoiceId || undef,
			bill_sequence => defined $lastBillSeq ? $lastBillSeq : undef,
			bill_party_type => defined $billPartyTypeClient ? $billPartyTypeClient : undef,
			bill_to_id => $personId || undef,
			#bill_amount => $billAmt || undef,
			#bill_pct => $billPct || undef,
			#bill_date => $billDate || undef,
			#bill_status => $billStatus || undef,
			#bill_result => $billResult || undef,
			_debug => 0
		);
	}



	#redirect to next function according to copay due

	my $copayAmt = $page->field('copay_amt');
	if($copayAmt && ! $STMTMGR_INVOICE->getRowAsHash($page, STMTMGRFLAG_NONE, 'selInvoiceItemsByType', $invoiceId, App::Universal::INVOICEITEMTYPE_COPAY))
	{
		billCopay($self, $page, 'add', $flags, $invoiceId);
	}
	else
	{
		$self->handlePostExecute($page, $command, $flags);
	}
}

sub billCopay
{
	my ($self, $page, $command, $flags, $invoiceId) = @_;

	my $todaysDate = $page->getDate();
	my $personId = $page->field('attendee_id');
	my $personType = App::Universal::ENTITYTYPE_PERSON;
	my $copayAmt = $page->field('copay_amt');


	#ADD COPAY ITEM

	my $itemType = App::Universal::INVOICEITEMTYPE_COPAY;
	my $copayItemId = $page->schemaAction(
		'Invoice_Item', $command,
		parent_id => $invoiceId || undef,
		item_type => defined $itemType ? $itemType : undef,
		extended_cost => defined $copayAmt ? $copayAmt : undef,
		balance => defined $copayAmt ? $copayAmt : undef,
		_debug => 0
	);


	#ADD INVOICE BILLING RECORD FOR COPAY ITEM

	my $billSeq = App::Universal::PAYER_PRIMARY;
	my $billPartyType = App::Universal::INVOICEBILLTYPE_CLIENT;
	$page->schemaAction(
		'Invoice_Billing', $command,
		invoice_id => $invoiceId || undef,
		invoice_item_id => $copayItemId || undef,
		bill_sequence => defined $billSeq ? $billSeq : undef,
		bill_party_type => defined $billPartyType ? $billPartyType : undef,
		bill_to_id => $personId || undef,
		bill_amount => defined $copayAmt ? $copayAmt : undef,
		bill_date => $todaysDate || undef,
		bill_status => 'Not paid',
		_debug => 0
	);



	#UPDATE INVOICE

	my $invoice = $STMTMGR_INVOICE->getRowAsHash($page, STMTMGRFLAG_NONE, 'selInvoice', $invoiceId);
	my $totalItems = $invoice->{total_items} + 1;
	my $totalCost = $invoice->{total_cost} + $copayAmt;
	my $invBalance = $totalCost + $invoice->{total_adjust};
	$page->schemaAction(
		'Invoice', 'update',
		invoice_id => $invoiceId || undef,
		total_items => defined $totalItems ? $totalItems : undef,
		total_cost => defined $totalCost ? $totalCost : undef,
		balance => defined $invBalance ? $invBalance : undef,
		_debug => 0
	);


	#Need to set invoice id as a param in order for 'Add Procedure' and 'Go to Claim Summary' next actions to work
	$page->param('invoice_id', $invoiceId) if $command eq 'add';
	$self->handlePostExecute($page, $command, $flags);
}

sub __payCopay
{
	my ($self, $page, $command, $flags, $invoiceId) = @_;

	my $invoiceItem = $STMTMGR_INVOICE->getRowAsHash($page, STMTMGRFLAG_NONE, 'selInvoiceItemsByType', $invoiceId, App::Universal::INVOICEITEMTYPE_COPAY);

	my $todaysDate = $page->getDate();
	my $personId = $page->field('attendee_id');
	my $personType = App::Universal::ENTITYTYPE_PERSON;
	my $copay = $page->field('copay');
	my $copayAmt = $page->field('copay_amt');

	my $adjustType = App::Universal::ADJUSTMENTTYPE_PAYMENT;
	my $netAdjust = 0 - $copay;
	my $payMethod = $page->field('pay_method');
	$page->schemaAction(
		'Invoice_Item_Adjust', 'add',
		adjustment_type => defined $adjustType ? $adjustType : undef,
		adjustment_amount => defined $copay ? $copay : undef,
		payer_type => defined $personType ? $personType : undef,
		payer_id => $personId || undef,
		parent_id => $invoiceItem->{item_id} || undef,
		copay => defined $copay ? $copay : undef,
		submit_date => $todaysDate || undef,
		pay_date => $todaysDate || undef,
		pay_type => App::Universal::ADJUSTMENTPAYTYPE_COPAY || undef,
		pay_method => defined $payMethod ? $payMethod : undef,
		pay_ref => $page->field('check_number') || undef,
		net_adjust => defined $netAdjust ? $netAdjust : undef,
		_debug => 0
	);

	#Need to set invoice id as a param in order for 'Add Procedure' and 'Go to Claim Summary' next actions to work
	$page->param('invoice_id', $invoiceId) if $command eq 'add';
	$self->handlePostExecute($page, $command, $flags);
}

sub addProcedureItems
{
	my ($self, $page, $command, $flags, $invoiceId) = @_;

	my $servItemType = App::Universal::INVOICEITEMTYPE_SERVICE;
	my $labItemType = App::Universal::INVOICEITEMTYPE_LAB;

	my @feeSchedules = $page->param('_f_proc_default_catalog');

	my $lineCount = $page->param('_f_line_count');

	for(my $line = 1; $line <= $lineCount; $line++)
	{
		next if $page->param("_f_proc_$line\_dos_begin") eq 'From' || $page->param("_f_proc_$line\_dos_end") eq 'To';
		next unless $page->param("_f_proc_$line\_dos_begin") && $page->param("_f_proc_$line\_dos_end");

		my $procCommand = $command;
		my $itemId = $page->param("_f_proc_$line\_item_id");
		if(! $STMTMGR_INVOICE->getRowAsHash($page, STMTMGRFLAG_CACHE, 'selInvoiceItem', $itemId))
		{
			$procCommand = 'add';
		}


		my $emg = $page->param("_f_proc_$line\_emg") eq 'on' ? 1 : 0;
		my %record = (
			item_id => $itemId || undef,
			service_begin_date => $page->param("_f_proc_$line\_dos_begin") || undef,			#default for service start date is today
			service_end_date => $page->param("_f_proc_$line\_dos_end") || undef,			#default for service end date is today
			hcfa_service_place => $page->param('_f_proc_service_place') || undef,		#default for place is 11
			hcfa_service_type => $page->param("_f_proc_$line\_service_type") || undef,		#default for service type is 2 for consultation
			modifier => $page->param("_f_proc_$line\_modifier") || undef,				#default for modifier is "mandated services"
			quantity => $page->param("_f_proc_$line\_units") || undef,				#default for units is 1
			emergency => defined $emg ? $emg : undef,								#default for emergency is 0 or 1
			item_type => App::Universal::INVOICEITEMTYPE_SERVICE || undef,				#default for item type is service
			code => $page->param("_f_proc_$line\_procedure") || undef,
			comments =>  $page->param("_f_proc_$line\_comments") || undef,
			unit_cost => $page->param("_f_proc_$line\_charges") || undef,
			rel_diags => $page->param("_f_proc_$line\_actual_diags") || undef,		#the actual icd (diag) codes
			data_text_a => $page->param("_f_proc_$line\_diags") || undef,			#the diag code pointers
			);


			$record{extended_cost} = $record{unit_cost} * $record{quantity};
			$record{balance} = $record{extended_cost};

			my $totalInvItems = $STMTMGR_INVOICE->getSingleValue($page, STMTMGRFLAG_CACHE, 'selInvoiceProcedureItemCount', $invoiceId, $servItemType, $labItemType);
			my $itemSeq = 0;
			$itemSeq = $totalInvItems + 1;

			$record{data_num_c} = $itemSeq || undef;


			# IMPORTANT: ADD VALIDATION FOR FIELD ABOVE (TALK TO RADHA/MUNIR/SHAHID)
			$page->schemaAction('Invoice_Item',	$procCommand,
					%record,
					parent_id => $invoiceId,
					_debug => 0,
					);




			#UPDATE INVOICE

			my $invoice = $STMTMGR_INVOICE->getRowAsHash($page, STMTMGRFLAG_NONE, 'selInvoice', $invoiceId);

			my $totalItems = $invoice->{total_items};
			if($procCommand eq 'add')
			{
				$totalItems = $invoice->{total_items} + 1;
			}
			elsif($procCommand eq 'remove')
			{
				$totalItems = $invoice->{total_items} - 1;
			}

			my $allInvItems = $STMTMGR_INVOICE->getRowsAsHashList($page, STMTMGRFLAG_CACHE, 'selInvoiceItems', $invoiceId);
			my $totalCostForInvoice = '';
			foreach my $item (@{$allInvItems})
			{
				$totalCostForInvoice += $item->{extended_cost};
			}

			my $invBalance = $totalCostForInvoice + $invoice->{total_adjust};

			$page->schemaAction('Invoice',
					'update',
					invoice_id => $invoiceId,
					total_cost => defined $totalCostForInvoice ? $totalCostForInvoice : undef,
					total_items => defined $totalItems ? $totalItems : undef,
					balance => defined $invBalance ? $invBalance : undef
				);


	}
}

sub customValidate
{
	my ($self, $page) = @_;

	#VALIDATION FOR 'ACCIDENT?' FIELD
	my $condRelToAuto = App::Universal::CONDRELTO_AUTO;
	my $accident = $self->getField('accident');
	my $state = $self->getField('accident_state');
	my @condRelToIds = $page->field('accident');

	my $autoSet = '';
	foreach my $relToId (@condRelToIds)
	{
		next if $relToId != $condRelToAuto;

		if($page->field('accident_state') eq '')
		{
			$state->invalidate($page, "Must provide '$state->{caption}' when selecting 'Auto Accident'");
		}

		$autoSet = 1;
	}

	if($autoSet eq '' && $page->field('accident_state') ne '')
	{
		$accident->invalidate($page, "Must select 'Auto Accident' when indicating a '$state->{caption}'");
	}
}


use constant CLAIM_DIALOG => 'Dialog/Claim';

@CHANGELOG =
(
	[	CHANGELOGFLAG_ANYVIEWER | CHANGELOGFLAG_UPDATE, '12/30/1999', 'MAF',
		CLAIM_DIALOG,
		'Updated the setInsuranceFields subroutine to populate the Primary Physician in the Create claim, Checkin and Checkout dialogs for a patient. '],
	[	CHANGELOGFLAG_ANYVIEWER | CHANGELOGFLAG_UPDATE, '01/02/2000', 'MAF',
		CLAIM_DIALOG,
		'Updated validation to disallow user from entering in the same icd code twice.'],
	[	CHANGELOGFLAG_SDE | CHANGELOGFLAG_NOTE, '01/03/2000', 'MAF',
		CLAIM_DIALOG,
		'Added Pay To Org/Phone and Claim Filing/Indicator invoice attributes. '],
	[	CHANGELOGFLAG_SDE | CHANGELOGFLAG_ADD, '01/05/2000', 'RK',
		CLAIM_DIALOG,
		'Added active-session execute action.'],
	[	CHANGELOGFLAG_ANYVIEWER | CHANGELOGFLAG_UPDATE, '01/06/2000', 'MAF',
		CLAIM_DIALOG,
		'Updated validation to disallow user from deleting an icd code that is being used in a procedure.'],
	[	CHANGELOGFLAG_ANYVIEWER | CHANGELOGFLAG_ADD, '01/10/2000', 'RK',
		CLAIM_DIALOG,
		'Added session-activity to the claim.'],
	[	CHANGELOGFLAG_SDE | CHANGELOGFLAG_NOTE, '01/12/2000', 'MAF',
		CLAIM_DIALOG,
		'Retired old InvoiceButtons and replaced it with CGI::Dialog::Buttons.'],
	[	CHANGELOGFLAG_ANYVIEWER | CHANGELOGFLAG_REMOVE, '01/13/2000', 'MAF',
		CLAIM_DIALOG,
		'Removed Information Release checkbox and date (this is now an Authorization and can be set in the Authorization pane).'],
	[	CHANGELOGFLAG_SDE | CHANGELOGFLAG_UPDATE, '01/20/2000', 'MAF',
		CLAIM_DIALOG,
		'Changed setInsuranceFields to setFields.'],
	[	CHANGELOGFLAG_SDE | CHANGELOGFLAG_UPDATE, '01/23/2000', 'MM',
		CLAIM_DIALOG,
		'Added Optimized Procedure entry textarea box.'],
	[	CHANGELOGFLAG_SDE | CHANGELOGFLAG_UPDATE, '01/24/2000', 'MAF',
		CLAIM_DIALOG,
		'Replaced magic numbers with constants.'],
	[	CHANGELOGFLAG_SDE | CHANGELOGFLAG_UPDATE, '01/26/2000', 'MM',
		CLAIM_DIALOG,
		'Added validateProcEntryTextArea validation routine.'],
	[	CHANGELOGFLAG_SDE | CHANGELOGFLAG_UPDATE, '01/26/2000', 'MM',
		CLAIM_DIALOG,
		'Added validateEachItemInProcEntryTextArea validation routine.'],
	[	CHANGELOGFLAG_ANYVIEWER | CHANGELOGFLAG_ADD, '02/19/2000', 'MAF',
		CLAIM_DIALOG,
		'Created CPT Explosion Code entry field.'],
	[	CHANGELOGFLAG_SDE | CHANGELOGFLAG_ADD, '02/19/2000', 'MAF',
		CLAIM_DIALOG,
		'Added executeExplosionCode subroutine.'],
	[	CHANGELOGFLAG_SDE | CHANGELOGFLAG_ADD, '02/25/2000', 'MAF',
		CLAIM_DIALOG,
		'Added submission order attribute.'],
	[	CHANGELOGFLAG_SDE | CHANGELOGFLAG_ADD, '03/27/2000', 'MAF',
		CLAIM_DIALOG,
		'Added radio buttons for all insurances belonging to patient. Defaults to primary ins.'],
	[	CHANGELOGFLAG_SDE | CHANGELOGFLAG_ADD, '03/28/2000', 'MAF',
		CLAIM_DIALOG,
		'Removed setFields function. Placed contents in populateData.'],
	[	CHANGELOGFLAG_SDE | CHANGELOGFLAG_ADD, '03/28/2000', 'MAF',
		CLAIM_DIALOG,
		'Created parent sub initialize for checkin, checkout, and createclaim dialogs.'],
	[	CHANGELOGFLAG_SDE | CHANGELOGFLAG_ADD, '03/28/2000', 'MAF',
		CLAIM_DIALOG,
		'Finally got sub copay to work.'],
	[	CHANGELOGFLAG_SDE | CHANGELOGFLAG_ADD, '04/02/2000', 'MAF',
		CLAIM_DIALOG,
		"Deleted validateOrgId. The field 'Payment Type' which was using this is no longer being used in this dialog."],
	[	CHANGELOGFLAG_SDE | CHANGELOGFLAG_ADD, '04/02/2000', 'MAF',
		CLAIM_DIALOG,
		"Deleted sub copay. Now all 'visit' claim information will be stored in one invoice."],
);

1;