##############################################################################
package App::Data::MDL::Invoice;
##############################################################################

use strict;
use DBI::StatementManager;
use App::Statements::Insurance;
use App::Statements::Invoice;
use App::Statements::Person;
use App::Statements::Org;

use App::Data::MDL::Module;
use vars qw(@ISA);
use Dumpvalue;

@ISA = qw(App::Data::MDL::Module);

use vars qw(%VISIT_TYPE_MAP %PAYMENT_TYPE_MAP);


%VISIT_TYPE_MAP = (
	'Office' => App::Universal::TRANSTYPEVISIT_OFFICE,
	'Clinic' => App::Universal::TRANSTYPEVISIT_CLINIC,
	'Hospital' => App::Universal::TRANSTYPEVISIT_HOSPITAL,
	'Facility' => App::Universal::TRANSTYPEVISIT_FACILITY,
);

sub new
{
	my $type = shift;
	my $self = new App::Data::MDL::Module(@_, parentTblPrefix => 'Invoice');
	return bless $self, $type;
}

sub importAccidentData
{
	my ($self, $flags, $accidentdata, $invoice) = @_;

	my $parentId = $invoice->{id};

	  	$accidentdata = [$accidentdata] if ref $accidentdata eq 'ARRAY';
		foreach my $item (@$accidentdata)
		{
			#my $dv = new Dumpvalue;
			#$dv->dumpValue($item);
				 $self->schemaAction($flags, "Invoice_Attribute", 'add',
				#parent_id => $parentId,
				item_name => "Condition/Related To",
				value_type => App::Universal::ATTRTYPE_TEXT,
				value_text => $item);

		}

}

sub importTransaction
{
	my ($self, $flags,  $transaction,$claim, $eventId) = @_;

	my $parentId = $claim->{id};
	my $parenteventId = $eventId;
	if(my $list = $claim->{transaction})
	{
		$list = [$list] if ref $list eq 'HASH';
		foreach my $item (@$list)
		{
			#my $dv = new Dumpvalue;
			#$dv->dumpValue($item);
			$transaction->{__trans_id} = $self->schemaAction($flags, "Transaction", 'add',
				trans_owner_id => $parentId,
				trans_status => App::Universal::TRANSSTATUS_ACTIVE,
				parent_event_id => $parenteventId,
				provider_id => $item->{'care-provider-id'},
				trans_type => $VISIT_TYPE_MAP{exists $item->{type} ? $item->{type} : 'Office'},
				caption => $item->{subject},
				bill_type => $self->translateEnum($flags, "Claim_Type", $item->{'payment-type'}),
				service_facility_id => $item->{'service-facility-id'},
				billing_facility_id => $item->{'billing-facility-id'},
				data_text_a => $item->{'referal-physician'},
				trans_begin_stamp =>$item->{'check-in-time'},
				init_onset_date => $item->{'current-illness-date'},
				curr_onset_date => $item->{'similar-illness-date'});
		}
	}

}

sub importInvoice
{
	my ($self, $flags, $invoice, $claim,$transaction) = @_;
	my $personId = $claim->{id};
	my $primBillSeq = App::Universal::INSURANCE_PRIMARY;
	my $parentId = $claim->{transaction}->{__trans_id};
	my $billingFacility = $claim->{transaction}->{'billing-facility-id'};
	my $dv = new Dumpvalue;
			$dv->dumpValue($parentId);
	if(my $list = $claim->{invoice})
	{
		$list = [$list] if ref $list eq 'HASH';

		my $insOrg = $STMTMGR_INSURANCE->getRowAsHash($self, STMTMGRFLAG_NONE, 'selInsuranceByBillSequence', $primBillSeq, $personId);
		my $dv = new Dumpvalue;
			$dv->dumpValue($billingFacility);
		my $insId = $insOrg->{ins_internal_id};
		foreach my $item (@$list)
		{
			#my $dv = new Dumpvalue;
			#$dv->dumpValue($parentId);
			$invoice->{__invoice_id}  = $self->schemaAction($flags, "Invoice", 'add',
				invoice_type => App::Universal::INVOICETYPE_HCFACLAIM,
				invoice_status => $self->translateEnum($flags, "Invoice_Status", $item->{'invoice-status'}),
				invoice_subtype => $self->translateEnum($flags, "Claim_Type", $item->{'payment-type'}),
				invoice_date => $item->{'invoice-date'},
				claim_diags => $item->{'diagnosis-items'},
				owner_id => $item->{'org-owner-id'},
				ins_id => $insId,
				reference => $item->{reference},
				owner_type => App::Universal::ENTITYTYPE_ORG,
				client_type => App::Universal::ENTITYTYPE_PERSON,
				client_id => $personId,
				submitter_id => $item->{'submitter-id'},
				bill_to_type => $self->translateEnum($flags, "Entity_Type", $item->{'bill-to-type'}),
				bill_to_id => $item->{'bill-to-id'},
				total_adjust => $item->{'total-adjust'},
				 balance => $item->{balance},
				 total_items => $item->{'total-items'},
				 total_cost => $item->{'total-cost'},
				main_transaction => $parentId);

		}
		my $invoiceId = $invoice->{__invoice_id};
		$self->schemaAction($flags,	'Invoice_Attribute', 'add',
			parent_id => $invoiceId,
			item_name => 'Submission Order',
			value_type => App::Universal::ATTRTYPE_INTEGER,
			value_int => 0);

		if(my $item = $claim->{invoice}->{comments})
		{
			$self->schemaAction($flags, 'Invoice_Attribute', 'add',
				parent_id => $invoice->{__invoice_id},
				item_name => 'Invoice/History/Item',
				value_type => App::Universal::ATTRTYPE_HISTORY,
				value_text => 'Created claim',
				value_textB => $item->{_text},
				value_date => $item->{date});
		}

		if(my $item = $claim->{invoice}->{accidentdata})
		{
			my @condRelToAccident = ();
			#my $dv = new Dumpvalue;
			#$dv->dumpValue($invoiceId);
			push(@condRelToAccident, $item->{accident});
			$self->schemaAction($flags, "Invoice_Attribute", 'add',
				parent_id => $invoiceId,
				item_name => "Condition/Related To",
				value_type => App::Universal::ATTRTYPE_TEXT,
				value_text => join(',', @condRelToAccident),
				value_textB => $item->{state});
		}

		if(my $refPhysicianId = $claim->{invoice}->{'ref_physician'})
		{
			my $refPhysInfo = $STMTMGR_PERSON->getRowAsHash($self, STMTMGRFLAG_NONE, 'selRegistry', $refPhysicianId);
			my $refPhysUpin = $STMTMGR_PERSON->getRowAsHash($self, STMTMGRFLAG_NONE, 'selAttributeByItemNameAndValueTypeAndParent', $refPhysicianId, 'UPIN', App::Universal::ATTRTYPE_LICENSE);
			my $refPhysState = $STMTMGR_PERSON->getRowAsHash($self, STMTMGRFLAG_NONE, 'selPhysStateLicense', $refPhysicianId, 1);

			my $dv = new Dumpvalue;
			$dv->dumpValue(" REFERING PHY:$refPhysicianId");

			$self->schemaAction($flags,'Invoice_Attribute', 'add',
					parent_id => $invoiceId,
					item_name => 'Ref Provider/Name/First',
					value_type => App::Universal::ATTRTYPE_TEXT,
					value_text => $refPhysInfo->{name_first},
					value_textB => $refPhysicianId);

			$self->schemaAction($flags,'Invoice_Attribute', 'add',
					parent_id => $invoiceId,
					item_name => 'Ref Provider/Name/Middle',
					value_type => App::Universal::ATTRTYPE_TEXT,
					value_text => $refPhysInfo->{name_middle},
					value_textB => $refPhysicianId) if $refPhysInfo->{name_middle} ne '';

			$self->schemaAction($flags,	'Invoice_Attribute', 'add',
					parent_id => $invoiceId || undef,
					item_name => 'Ref Provider/Name/Last',
					value_type => App::Universal::ATTRTYPE_TEXT,
					value_text => $refPhysInfo->{name_last},
					value_textB => $refPhysicianId);

			$self->schemaAction($flags,	'Invoice_Attribute', 'add',
					parent_id => $invoiceId,
					item_name => 'Ref Provider/Identification',
					value_type => App::Universal::ATTRTYPE_TEXT,
					value_text => $refPhysUpin->{value_text},
					value_textB => $refPhysState->{value_textb});
			#end referring phys attrs
		}

		if(my $item = $claim->{invoice}->{'prior_auth'})
		{
			$self->schemaAction($flags,	'Invoice_Attribute', 'add',
					parent_id => $invoiceId || undef,
					item_name => 'Prior Authorization Number',
					value_type => App::Universal::ATTRTYPE_TEXT,
					value_text => $item);
		}

		if(my $item = $claim->{invoice}->{'deduct_balanceamt'})
		{
			$self->schemaAction($flags,'Invoice_Attribute', 'add',
					parent_id => $invoiceId || undef,
					item_name => 'Patient/Deductible/Balance',
					value_type => App::Universal::ATTRTYPE_CURRENCY,
					value_text => $item);
		}

	# Billing Facility  Cotact Info Attributes

		my $billingContact = $STMTMGR_ORG->getRowAsHash($self, STMTMGRFLAG_CACHE, 'selAttribute', $billingFacility, 'Contact Information');
		my $contactName =  $billingContact->{value_text};
		my $contactPhone = $billingContact->{value_textb};

		$self->schemaAction($flags,	'Invoice_Attribute', 'add',
				parent_id => $invoiceId,
				item_name => 'Service Provider/Facility/Billing/Contact',
				value_type => App::Universal::ATTRTYPE_TEXT,
				value_text => $contactName,
				value_textB => $contactPhone);

		my $secondaryIns = App::Universal::INSURANCE_SECONDARY;
		my $personSecInsur = $STMTMGR_INSURANCE->getRowAsHash($self, STMTMGRFLAG_CACHE, 'selPersonInsurance', $personId, $secondaryIns);
		my $claimFiling = 'P';
		$claimFiling = 'M' if $personSecInsur->{ins_internal_id} ne '';

		$self->schemaAction($flags,'Invoice_Attribute', 'add',
				parent_id => $invoiceId,
				item_name => 'Claim Filing/Indicator',
				value_type => App::Universal::ATTRTYPE_TEXT,
				value_text => $claimFiling);

		if(my $payToOrgId = $claim->{invoice}->{'pay_to_org'})
		{
			my $dv = new Dumpvalue;
			$dv->dumpValue("PAY TO ORG: $payToOrgId");
			my $payToFacility = $STMTMGR_ORG->getRowAsHash($self, STMTMGRFLAG_CACHE, 'selOrgAddressByAddrName', $payToOrgId, 'Mailing');
			my $payToFacilityName = $STMTMGR_ORG->getSingleValue($self, STMTMGRFLAG_NONE, 'selOrgSimpleNameById', $payToOrgId);
			my $payToFacilityPhone = $STMTMGR_ORG->getRowAsHash($self, STMTMGRFLAG_NONE, 'selAttributeByItemNameAndValueTypeAndParent', $payToOrgId, 'Primary', App::Universal::ATTRTYPE_PHONE);
			my $dv = new Dumpvalue;
			$dv->dumpValue("PAY TO ORG NAME: $payToFacilityName, $payToFacilityPhone ");


			$self->schemaAction($flags,	'Invoice_Attribute', 'add',
					parent_id => $invoiceId,
					item_name => 'Pay To Org/Name',
					value_type => App::Universal::ATTRTYPE_TEXT,
					value_text => $payToFacilityName,
					value_textB => $payToOrgId);

			$self->schemaAction($flags,'Invoice_Attribute', 'add',
					parent_id => $invoiceId,
					item_name => 'Pay To Org/Phone',
					value_type => App::Universal::ATTRTYPE_PHONE,
					value_text => $payToFacilityPhone->{value_text},
					value_textB => $payToOrgId);

			$self->schemaAction($flags,	'Invoice_Address', 'add',
					parent_id => $invoiceId,
					address_name => 'Pay To Org',
					line1 => $payToFacility->{line1},
					line2 => $payToFacility->{line2},
					city => $payToFacility->{city},
					state => $payToFacility->{state},
					zip => $payToFacility->{zip});
		}

		if($claim->{invoice}->{'invoice-status'} eq 'Submitted')
		{
			$self->importClaimSubmission($flags, $claim, $invoice, $invoiceId, $personId)
		}


	}
}

sub importClaimSubmission
{
	my ($self, $flags, $claim, $invoice, $invoiceId, $personId) = @_;

	my $invoice = $STMTMGR_INVOICE->getRowAsHash($self, STMTMGRFLAG_NONE, 'selInvoice', $invoiceId);
	my $clientId = $invoice->{client_id};
	my $submitterId = $invoice->{'submitter-id'};

	my $claimType = $invoice->{invoice_subtype};
	my $todaysDate = UnixDate('today', $self->defaultUnixDateFormat());

	my $textValueType = App::Universal::ATTRTYPE_TEXT;
	my $phoneValueType = App::Universal::ATTRTYPE_PHONE;
	my $boolValueType = App::Universal::ATTRTYPE_BOOLEAN;
	my $currencyValueType = App::Universal::ATTRTYPE_CURRENCY;
	my $dateValueType = App::Universal::ATTRTYPE_DATE;
	my $licenseValueType = App::Universal::ATTRTYPE_LICENSE;

	my $selfPay = App::Universal::CLAIMTYPE_SELFPAY;
	my $uniqPlan = App::Universal::RECORDTYPE_PERSONALCOVERAGE;
	my $attrDataFlag = App::Universal::INVOICEFLAG_DATASTOREATTR;

		#----FIRST CREATE THE INVOICE ATTRIBUTES FOR THE OLD HCFA1500!!----#

	my $invoiceFlags = $invoice->{flags};

	unless($invoiceFlags & $attrDataFlag)
	{
		my $mainTransId = $invoice->{main_transaction};
		my $mainTransData = $STMTMGR_TRANSACTION->getRowAsHash($self, STMTMGRFLAG_CACHE, 'selTransaction', $mainTransId);

		##BILLING FACILITY INFORMATION
		my $billingFacility = $STMTMGR_ORG->getRowAsHash($page, STMTMGRFLAG_CACHE, 'selOrgAddressByAddrName', $mainTransData->{billing_facility_id}, 'Mailing');
		my $billingFacilityName = $STMTMGR_ORG->getSingleValue($self, STMTMGRFLAG_NONE, 'selOrgSimpleNameById', $mainTransData->{billing_facility_id});

		$self->schemaAction($flags,	'Invoice_Attribute', 'add',
				parent_id => $invoiceId,
				item_name => 'Service Provider/Facility/Billing',
				value_type => $textValueType,
				value_text => $billingFacilityName,
				value_textB => $billingFacility->{billing_facility_id});

		$self->schemaAction($flags,	'Invoice_Address', 'add',
				parent_id => $invoiceId,
				address_name => 'Billing',
				line1 => $billingFacility->{line1},
				line2 => $billingFacility->{line2},
				city => $billingFacility->{city},
				state => $billingFacility->{state},
				zip => $billingFacility->{zip});

		##SERVICE FACILITY INFORMATION
		my $serviceFacility = $STMTMGR_ORG->getRowAsHash($self, STMTMGRFLAG_CACHE, 'selOrgAddressByAddrName', $mainTransData->{service_facility_id}, 'Mailing');
		my $serviceFacilityName = $STMTMGR_ORG->getSingleValue($self, STMTMGRFLAG_NONE, 'selOrgSimpleNameById', $mainTransData->{service_facility_id});

		$self->schemaAction($flags,	'Invoice_Attribute', 'add',
				parent_id => $invoiceId,
				item_name => 'Service Provider/Facility/Service',
				value_type =>'$textValueType',
				value_text => $serviceFacilityName,
				value_textB => $serviceFacility->{service_facility_id});

		$self->schemaAction($flags,'Invoice_Address', 'add',
				parent_id => $invoiceId,
				address_name => 'Service',
				line1 => $serviceFacility->{line1},
				line2 => $serviceFacility->{line2},
				city => $serviceFacility->{city},
				state => $serviceFacility->{state},
				zip => $serviceFacility->{zip});


			##PATIENT INFO AND AUTHORIZATIONS
		my $personData = $STMTMGR_PERSON->getRowAsHash($page, STMTMGRFLAG_CACHE, 'selRegistry', $clientId);
		my $personPhone = $STMTMGR_PERSON->getSingleValue($page, STMTMGRFLAG_CACHE, 'selHomePhone', $clientId);
		my $personAddr = $STMTMGR_PERSON->getRowAsHash($page, STMTMGRFLAG_NONE, 'selHomeAddress', $clientId);
		my $patSignature = $STMTMGR_PERSON->getRowAsHash($page, STMTMGRFLAG_NONE, 'selAttributeByItemNameAndValueTypeAndParent', $clientId, 'Signature Source', App::Universal::ATTRTYPE_AUTHPATIENTSIGN);
		my $provAssign = $STMTMGR_PERSON->getRowAsHash($page, STMTMGRFLAG_NONE, 'selAttributeByItemNameAndValueTypeAndParent', $clientId, 'Provider Assignment', App::Universal::ATTRTYPE_AUTHPROVIDERASSIGN);
		my $infoRelease = $STMTMGR_PERSON->getRowAsHash($page, STMTMGRFLAG_NONE, 'selAttributeByItemNameAndValueTypeAndParent', $clientId, 'Information Release', App::Universal::ATTRTYPE_AUTHINFORELEASE);

		$self->schemaAction($flags,	'Invoice_Attribute', 'add',
				parent_id => $invoiceId,
				item_name => 'Patient/Signature',
				value_type =>  $textValueType,
				value_text => $patSignature->{value_text} || undef);

		$self->schemaAction($flags,	'Invoice_Attribute', 'add',
				parent_id => $invoiceId || undef,
				item_name => 'Provider/Assign Indicator',
				value_type => defined $textValueType ? $textValueType : undef,
				value_text => $provAssign->{value_text} || undef,
				_debug => 0
			);

		my $infoRelIndctr = $infoRelease->{value_text} eq 'Yes' ? 1 : 0;
		$self->schemaAction($flags,	'Invoice_Attribute', 'add',
				parent_id => $invoiceId,
				item_name => 'Information Release/Indicator',
				value_type => $boolValueType,
				value_int =>$infoRelIndctr,
				value_date => $infoRelease->{value_date} || undef);

		$self->schemaAction($flags,	'Invoice_Attribute', 'add',
				parent_id => $invoiceId,
				item_name => 'Provider/Signature/Date',
				value_type =>$dateValueType ,
				value_date => $todaysDate || undef);

		$self->schemaAction($flags,	'Invoice_Address', 'add',
				parent_id => $invoiceId,
				address_name => 'Patient',
				line1 => $personAddr->{line1},
				line2 => $personAddr->{line2},
				city => $personAddr->{city},
				state => $personAddr->{state},
				zip => $personAddr->{zip});

		$self->schemaAction($flags,	'Invoice_Attribute', 'add',
				parent_id => $invoiceId,
				item_name => 'Patient/Name',
				value_type =>$textValueType,
				value_text => $personData->{complete_name});

		$self->schemaAction($flags,	'Invoice_Attribute', 'add',
				parent_id => $invoiceId,
				item_name => 'Patient/Name/Last',
				value_type => $textValueType,
				value_text => $personData->{name_last});

		$self->schemaAction($flags,	'Invoice_Attribute', 'add',
				parent_id => $invoiceId,
				item_name => 'Patient/Name/First',
				value_type =>$textValueType,
				value_text => $personData->{name_first});

		$self->schemaAction($flags,	'Invoice_Attribute', 'add',
				parent_id => $invoiceId,
				item_name => 'Patient/Name/Middle',
				value_type => $textValueType,
				value_text => $personData->{name_middle}
			) if $personData->{name_middle} ne '';

		$self->schemaAction($flags,	'Invoice_Attribute', 'add',
				parent_id => $invoiceId,
				item_name => 'Patient/Account Number',
				value_type => $textValueType,
				value_text => $personData->{person_ref});

		$self->schemaAction($flags,	'Invoice_Attribute', 'add',
				parent_id => $invoiceId,
				item_name => 'Patient/Contact/Home Phone',
				value_type => $phoneValueType,
				value_text => $personPhone);

		$self->schemaAction($flags,	'Invoice_Attribute', 'add',
				parent_id => $invoiceId,
				item_name => 'Patient/Personal/Marital Status',
				value_type => $textValueType,
				value_text => $personData->{marstat_caption});

		$self->schemaAction($flags,	'Invoice_Attribute', 'add',
				parent_id => $invoiceId,
				item_name => 'Patient/Personal/Gender',
				value_type => $textValueType ,
				value_text => $personData->{gender_caption});

		$self->schemaAction($flags,	'Invoice_Attribute', 'add',
				parent_id => $invoiceId,
				item_name => 'Patient/Personal/DOB',
				value_type => $dateValueType,
				value_date => $personData->{date_of_birth});


			##PATIENT'S EMPLOYMENT STATUS

		my $personEmployStat = $STMTMGR_PERSON->getRowsAsHashList($self, STMTMGRFLAG_CACHE, 'selEmploymentStatusCaption', $clientId);
		#here's a list of statuses:

		my $ftEmployAttr = App::Universal::ATTRTYPE_EMPLOYEDFULL;	#220
		my $ptEmployAttr = App::Universal::ATTRTYPE_EMPLOYEDPART;	#221
		my $selfEmployAttr = App::Universal::ATTRTYPE_SELFEMPLOYED;	#222
		my $retiredAttr = App::Universal::ATTRTYPE_RETIRED;			#223
		my $ftStudentAttr = App::Universal::ATTRTYPE_STUDENTFULL;	#224
		my $ptStudentAttr = App::Universal::ATTRTYPE_STUDENTPART;	#225
		my $unknownAttr = App::Universal::ATTRTYPE_EMPLOYUNKNOWN;	#226

		foreach my $employStat (@{$personEmployStat})
		{
			my $status = '';
			$status = $employStat->{caption};
			$status = 'Retired' if $employStat->{value_type} == $retiredAttr;
			$status = 'Employed' if $employStat->{value_type} >= $ftEmployAttr && $employStat->{value_type} <= $selfEmployAttr;

			if($status eq 'Employed')
			{
				$self->schemaAction($flags,	'Invoice_Attribute', 'add',
						parent_id => $invoiceId,
						item_name => 'Patient/Employment/Status',
						value_type => $textValueType,
						value_text => $status);
			}
			elsif($status eq 'Student (Full-Time)' || $status eq 'Student (Part-Time)')
			{
				$self->schemaAction($flags,	'Invoice_Attribute', 'add',
						parent_id => $invoiceId,
						item_name => 'Patient/Student/Status',
						value_type => $textValueType,
						value_text => $status);
			}
		}


		##PATIENT'S PROVIDER INFO, CONDITION RELATED TO, AND REFERRING PHYSICIAN NAME AND ID
		my $providerInfo = $STMTMGR_PERSON->getRowAsHash($self, STMTMGRFLAG_CACHE, 'selRegistry', $mainTransData->{provider_id});
		my $providerTaxId = $STMTMGR_PERSON->getRowAsHash($self, STMTMGRFLAG_CACHE, 'selAttributeByItemNameAndValueTypeAndParent', $mainTransData->{provider_id}, 'Tax ID', App::Universal::ATTRTYPE_LICENSE);
		my $providerUpin = $STMTMGR_PERSON->getRowAsHash($self, STMTMGRFLAG_CACHE, 'selAttributeByItemNameAndValueTypeAndParent', $mainTransData->{provider_id}, 'UPIN', App::Universal::ATTRTYPE_LICENSE);
		my $providerSpecialty = $STMTMGR_PERSON->getRowAsHash($page, STMTMGRFLAG_CACHE, 'selAttributeByItemNameAndValueTypeAndParent', $mainTransData->{provider_id}, 'Primary', App::Universal::ATTRTYPE_SPECIALTY);

		$self->schemaAction($flags,	'Invoice_Attribute', 'add',
				parent_id => $invoiceId,
				item_name => 'Provider/Name',
				value_type => $textValueType,
				value_text => $providerInfo->{complete_name},
				value_textB => $mainTransData->{provider_id});

		$self->schemaAction($flags,	'Invoice_Attribute', 'add',
				parent_id => $invoiceId,
				item_name => 'Provider/Name/First',
				value_type => $textValueType,
				value_text => $providerInfo->{name_first});

		$self->schemaAction($flags,	'Invoice_Attribute', 'add',
				parent_id => $invoiceId,
				item_name => 'Provider/Name/Middle',
				value_type => $textValueType,
				value_text => $providerInfo->{name_middle},
			) if $providerInfo->{name_middle} ne '';

		$self->schemaAction($flags,	'Invoice_Attribute', 'add',
				parent_id => $invoiceId,
				item_name => 'Provider/Name/Last',
				value_type => $textValueType,
				value_text => $providerInfo->{name_last});

		$self->schemaAction($flags,	'Invoice_Attribute', 'add',
				parent_id => $invoiceId,
				item_name => 'Provider/UPIN',
				value_type => $licenseValueType,
				value_text => $providerUpin->{value_text});

		$self->schemaAction($flags,	'Invoice_Attribute', 'add',
				parent_id => $invoiceId,
				item_name => 'Provider/Tax ID',
				value_type => $licenseValueType,
				value_text => $providerTaxId->{value_text},
				value_textB => $providerTaxId->{value_textb});

		$self->schemaAction($flags,	'Invoice_Attribute', 'add',
				parent_id => $invoiceId,
				item_name => 'Provider/Specialty',
				value_type => $textValueType,
				value_text => $providerSpecialty->{value_text},
				value_textB => $providerSpecialty->{value_textb});


		if($claimType != $selfPay)
		{
			##PATIENT'S INSURANCE INFO, INSURED INFO, OTHER INSURED INFO (IF ANY)

			my $primaryIns = App::Universal::INSURANCE_PRIMARY;
			my $textValueType = App::Universal::ATTRTYPE_TEXT;
			my $durationValueType = App::Universal::ATTRTYPE_DURATION;

			my $personInsur = $STMTMGR_INSURANCE->getRowAsHash($self, STMTMGRFLAG_CACHE, 'selPersonInsurance', $clientId, $primaryIns);
			my $claimType = $personInsur->{claim_type};

			my $insOrgName = $STMTMGR_ORG->getSingleValue($self, STMTMGRFLAG_NONE, 'selOrgSimpleNameById', $personInsur->{ins_org_id});

			my $parentId = $personInsur->{parent_ins_id} if $personInsur->{record_type} != $uniqPlan;
			$parentId = $personInsur->{ins_internal_id} if $personInsur->{record_type} == $uniqPlan;

			my $champusStatus = $STMTMGR_INSURANCE->getRowAsHash($self, STMTMGRFLAG_NONE, 'selInsuranceAttr', $parentId, 'Champus Status');
			my $champusBranch = $STMTMGR_INSURANCE->getRowAsHash($self, STMTMGRFLAG_NONE, 'selInsuranceAttr', $parentId, 'Champus Branch');
			my $champusGrade = $STMTMGR_INSURANCE->getRowAsHash($self, STMTMGRFLAG_NONE, 'selInsuranceAttr', $parentId, 'Champus Grade');

			my $ppoHmo = $STMTMGR_INSURANCE->getRowAsHash($self, STMTMGRFLAG_NONE, 'selInsuranceAttr', $parentId, 'HMO-PPO/Indicator');
			my $bcbsCode = $STMTMGR_INSURANCE->getRowAsHash($self, STMTMGRFLAG_NONE, 'selInsuranceAttr', $parentId, 'BCBS Plan Code');
			my $insOrgPhone = $STMTMGR_INSURANCE->getRowAsHash($self, STMTMGRFLAG_NONE, 'selInsurancePayerPhone', $parentId);
			my $insOrgAddr = $STMTMGR_INSURANCE->getRowAsHash($self, STMTMGRFLAG_NONE, 'selInsuranceAddrWithOutColNameChanges', $parentId);


			my $relToCaption = $STMTMGR_INSURANCE->getSingleValue($self, STMTMGRFLAG_NONE, 'selInsuredRelationship', $personInsur->{rel_to_insured});
			my $relToCode = '';
			$relToCode = '01' if $relToCaption eq 'Self';
			$relToCode = '02' if $relToCaption eq 'Spouse';
			$relToCode = '18' if $relToCaption eq 'Parent';
			$relToCode = '03' if $relToCaption eq 'Child';
			$relToCode = '99' if $relToCaption eq 'Other';

			my $paySource = '';
			$paySource = 'A' if $claimType eq 'Self-Pay';
			$paySource = 'B' if $claimType eq 'Workers Compensation';
			$paySource = 'C' if $claimType eq 'Medicare';
			$paySource = 'D' if $claimType eq 'Medicaid';
			#$paySource = 'E' if $claimType eq 'Other Federal Program';
			$paySource = 'F' if $claimType eq 'Insurance';
			#$paySource = 'G' if $claimType eq 'Blue Cross/Blue Shield';
			$paySource = 'H' if $claimType eq 'CHAMPUS';
			$paySource = 'I' if $claimType eq 'HMO';
			#$paySource = 'J' if $claimType eq 'Federal Employee�s Program (FEP)';
			#$paySource = 'K' if $claimType eq 'Central Certification';
			#$paySource = 'L' if $claimType eq 'Self Administered';
			#$paySource = 'M' if $claimType eq 'Family or Friends';
			#$paySource = 'N' if $claimType eq 'Managed Care - Non-HMO';
			$paySource = 'P' if $claimType eq 'BCBS';
			#$paySource = 'T' if $claimType eq 'Title V';
			#$paySource = 'V' if $claimType eq 'Veteran�s Administration Plan';
			$paySource = 'X' if $claimType eq 'PPO';
			$paySource = 'Z' if $claimType eq 'Client Billing' || $claimType eq 'ChampVA' || $claimType eq 'FECA Blk Lung';


			#first add insurance info
		$self->schemaAction($flags,	'Invoice_Attribute', 'add',
					parent_id => $invoiceId,
					item_name => 'Insurance/Primary/Name',
					value_type => $textValueType,
					value_text => $insOrgName,
					value_textB => $personInsur->{ins_org_id});

		$self->schemaAction($flags,	'Invoice_Attribute', 'add',
					parent_id => $invoiceId,
					item_name => 'Insurance/Primary/Effective Dates',
					value_type => $durationValueType,
					value_date => $personInsur->{coverage_begin_date},
					value_dateEnd => $personInsur->{coverage_end_date});

		$self->schemaAction($flags,	'Invoice_Attribute', 'add',
				parent_id => $invoiceId,
				item_name => 'Insurance/Primary/Type',
				value_type => $textValueType,
				value_text => $claimType,
				value_textB => $personInsur->{extra});

		$self->schemaAction($flags,	'Invoice_Attribute', 'add',
				parent_id => $invoiceId,
				item_name => 'HMO-PPO/Indicator',
				value_type => $textValueType,
				value_text => $ppoHmo->{value_text});

		$self->schemaAction($flags,	'Invoice_Attribute', 'add',
				parent_id => $invoiceId,
				item_name => 'BCBS Plan Code',
				value_type => $textValueType,
				value_text => $bcbsCode->{value_text});

		$self->schemaAction($flags,	'Invoice_Attribute', 'add',
				parent_id => $invoiceId,
				item_name => 'Champus Branch',
				value_type => $textValueType,
				value_text => $champusBranch->{value_text});

		$self->schemaAction($flags,	'Invoice_Attribute', 'add',
				parent_id => $invoiceId,
				item_name => 'Champus Status',
				value_type => $textValueType,
				value_text => $champusStatus->{value_text});

		$self->schemaAction($flags,	'Invoice_Attribute', 'add',
				parent_id => $invoiceId,
				item_name => 'Champus Grade',
				value_type => $textValueType,
				value_text => $champusGrade->{value_text});

		$self->schemaAction($flags,	'Invoice_Attribute', 'add',
				parent_id => $invoiceId,
				item_name => 'Payment Source',
				value_type => $textValueType,
				value_text => $paySource);

		$self->schemaAction($flags,	'Invoice_Attribute', 'add',
				parent_id => $invoiceId,
				item_name => 'Insurance/Primary/Phone',
				value_type => $phoneValueType,
				value_text => $insOrgPhone->{phone});

		$self->schemaAction($flags,	'Invoice_Attribute', 'add',
				parent_id => $invoiceId,
				item_name => 'Insurance/Primary/Group Number',
				value_type => $textValueType,
				value_text => $personInsur->{group_name} || $personInsur->{plan_name},
				value_textB => $personInsur->{group_number} || $personInsur->{policy_number});

		$self->schemaAction($flags,	'Invoice_Address', 'add',
				parent_id => $invoiceId,
				address_name => 'Insurance',
				line1 => $insOrgAddr->{line1},
				line2 => $insOrgAddr->{line2},
				city => $insOrgAddr->{city},
				state => $insOrgAddr->{state},
				zip => $insOrgAddr->{zip});

		#patient's relationship to the insured
		$self->schemaAction($flags,	'Invoice_Attribute', 'add',
				parent_id => $invoiceId,
				item_name => 'Patient/Insured/Relationship',
				value_type => $textValueType,
				value_text => $relToCaption,
				value_int => $relToCode);

			#now add insured info
		my $insuredData = $STMTMGR_PERSON->getRowAsHash($self, STMTMGRFLAG_CACHE, 'selRegistry', $personInsur->{insured_id});
		my $insuredPhone = $STMTMGR_PERSON->getSingleValue($self, STMTMGRFLAG_CACHE, 'selHomePhone', $personInsur->{insured_id});
		my $insuredAddr = $STMTMGR_PERSON->getRowAsHash($self, STMTMGRFLAG_NONE, 'selHomeAddress', $personInsur->{insured_id});
		my $insuredEmployers = $STMTMGR_PERSON->getRowsAsHashList($self, STMTMGRFLAG_NONE, 'selEmploymentAssociations', $personInsur->{insured_id});

		foreach my $employer (@{$insuredEmployers})
		{
			next if $employer->{value_type} == $retiredAttr;

			my $occupType = 'Employer';
			$occupType = 'School' if $employer->{value_type} == $ftStudentAttr || $employer->{value_type} == $ptStudentAttr;

			my $empStatus = $STMTMGR_PERSON->getSingleValue($self, STMTMGRFLAG_NONE, 'selEmploymentStatus', $employer->{value_type});

			my $employerName = $STMTMGR_ORG->getSingleValue($self, STMTMGRFLAG_NONE, 'selOrgSimpleNameById', $employer->{value_text});

		$self->schemaAction($flags,	'Invoice_Attribute', 'add',
					parent_id => $invoiceId,
					item_name => "Insured/$occupType/Name",
					value_type => $textValueType,
					value_text => $employerName,
					value_textB => $empStatus);
		}

		$self->schemaAction($flags,	'Invoice_Address', 'add',
				parent_id => $invoiceId,
				address_name => 'Insured',
				line1 => $insuredAddr->{line1},
				line2 => $insuredAddr->{line2},
				city => $insuredAddr->{city},
				state => $insuredAddr->{state},
				zip => $insuredAddr->{zip});

		$self->schemaAction($flags,	'Invoice_Attribute', 'add',
				parent_id => $invoiceId,
				item_name => 'Insured/Name',
				value_type => $textValueType,
				value_text => $insuredData->{complete_name});

		$self->schemaAction($flags,	'Invoice_Attribute', 'add',
				parent_id => $invoiceId,
				item_name => 'Insured/Name/Last',
				value_type => $textValueType,
				value_text => $insuredData->{name_last});

		$self->schemaAction($flags,	'Invoice_Attribute', 'add',
				parent_id => $invoiceId,
				item_name => 'Insured/Name/First',
				value_type => $textValueType,
				value_text => $insuredData->{name_first});

		$self->schemaAction($flags,	'Invoice_Attribute', 'add',
				parent_id => $invoiceId,
				item_name => 'Insured/Name/Middle',
				value_type => $textValueType,
				value_text => $insuredData->{name_middle}
			) if $insuredData->{name_middle} ne '';

		$self->schemaAction($flags,	'Invoice_Attribute', 'add',
				parent_id => $invoiceId,
				item_name => 'Insured/Contact/Home Phone',
				value_type => $phoneValueType,
				value_text => $insuredPhone);

		$self->schemaAction($flags,	'Invoice_Attribute', 'add',
				parent_id => $invoiceId,
				item_name => 'Insured/Personal/Marital Status',
				value_type => $textValueType,
				value_text => $insuredData->{marstat_caption});

		$self->schemaAction($flags,	'Invoice_Attribute', 'add',
				parent_id => $invoiceId,
				item_name => 'Insured/Personal/Gender',
				value_type => $textValueType,
				value_text => $insuredData->{gender_caption});

		$self->schemaAction($flags,	'Invoice_Attribute', 'add',
				parent_id => $invoiceId,
				item_name => 'Insured/Personal/DOB',
				value_type => $dateValueType,
				value_date => $insuredData->{date_of_birth});

		$self->schemaAction($flags,	'Invoice_Attribute', 'add',
				parent_id => $invoiceId,
				item_name => 'Insured/Personal/SSN',
				value_type => $textValueType,
				value_text => $insuredData->{ssn});


		#Create attributes for secondary insurance (for HCFA Box 11d, 9a-d)
		my $secondaryIns = App::Universal::INSURANCE_SECONDARY;
		my $secondInsur = $STMTMGR_INSURANCE->getRowAsHash($self, STMTMGRFLAG_CACHE, 'selPersonInsurance', $clientId, $secondaryIns);
		if($secondInsur->{ins_internal_id})
		{
		$self->schemaAction($flags,	'Invoice_Attribute', 'add',
					parent_id => $invoiceId,
					item_name => 'Insurance/Secondary/Group Number',
					value_type => $textValueType ,
					value_text => $secondInsur->{group_name},
					value_textB => $secondInsur->{group_number} || $secondInsur->{policy_number});

			my $otherInsuredData = $STMTMGR_PERSON->getRowAsHash($self, STMTMGRFLAG_CACHE, 'selRegistry', $secondInsur->{insured_id});
			my $otherInsuredEmployers = $STMTMGR_PERSON->getRowsAsHashList($self, STMTMGRFLAG_NONE, 'selEmploymentAssociations', $secondInsur->{insured_id});

			foreach my $employer (@{$otherInsuredEmployers})
			{
				next if $employer->{value_type} == $retiredAttr;

				my $occupType = 'Employer';
				$occupType = 'School' if $employer->{value_type} == $ftStudentAttr || $employer->{value_type} == $ptStudentAttr;

				my $empStatus = $STMTMGR_PERSON->getSingleValue($self, STMTMGRFLAG_NONE, 'selEmploymentStatus', $employer->{value_type});

				my $employerName = $STMTMGR_ORG->getSingleValue($self, STMTMGRFLAG_NONE, 'selOrgSimpleNameById', $employer->{value_text});

				$self->schemaAction($flags,	'Invoice_Attribute', 'add',
						parent_id => $invoiceId,
						item_name => "Other Insured/$occupType/Name",
						value_type => $textValueType,
						value_text => $employerName,
						value_textB => $empStatus);
			}

			$self->schemaAction($flags,	'Invoice_Attribute', 'add',
					parent_id => $invoiceId,
					item_name => 'Other Insured/Personal/Gender',
					value_type =>$textValueType,
					value_text => $otherInsuredData->{gender_caption});

			$self->schemaAction($flags,	'Invoice_Attribute', 'add',
					parent_id => $invoiceId,
					item_name => 'Other Insured/Personal/DOB',
					value_type => $dateValueType,
					value_date => $otherInsuredData->{date_of_birth});
			}
		}

		my @icdCodes = split(', ', $invoice->{claim_diags});
		foreach my $icdCode (@icdCodes)
		{
			$self->schemaAction($flags,	'Transaction', 'add',
					trans_owner_type => App::Universal::ENTITYTYPE_PERSON,
					trans_owner_id => $clientId,
					parent_trans_id => $mainTransId,
					trans_type => App::Universal::TRANSTYPEDIAG_ICD,
					trans_status => App::Universal::TRANSSTATUS_ACTIVE,
					billing_facility_id => $mainTransData->{billing_facility_id},
					service_facility_id => $mainTransData->{service_facility_id},
					code => $icdCode || undef,
					provider_id => $mainTransData->{provider_id},
					trans_begin_stamp => $todaysDate);

		}
	}

	#----NOW UPDATE THE INVOICE STATUS AND SET THE FLAG----#

	## Update invoice status, set flag for attributes, enter in submitter_id and date of submission
	my $todaysDate = $self->getDate();
	$self->schemaAction($flags,'Invoice', 'update',
			invoice_id => $invoiceId,
			invoice_status => App::Universal::INVOICESTATUS_SUBMITTED,
			submitter_id => $submitterId,
			flags => $invoiceFlags | $attrDataFlag);

}


sub importProcedures
{
	my ($self, $flags, $claimprocedures, $claim,$invoice) = @_;
	my $personId = $claim->{id};
	my $parentId = $claim->{invoice}->{__invoice_id};
	if(my $list = $claimprocedures->{procedure})
	{

		$list = [$list] if ref $list eq 'HASH';
		foreach my $item (@$list)
		{
			#my $dv = new Dumpvalue;
			#$dv->dumpValue($parentId);
			my @relDiags = $item->{'icd-code'};
			my $item_id = $self->schemaAction($flags, "Invoice_Item", 'add',
				      	parent_id =>$parentId,
				      	item_type => App::Universal::INVOICEITEMTYPE_SERVICE,
				      	code => $item->{'cpt-code'},
				      	rel_diags => join(',', @relDiags),
				      	unit_cost => $item->{'unit-cost'},
				      	quantity => $item->{'num-of-units'},
				      	extended_cost => $item->{'total-cost'},
				      	total_adjust => $item->{'item-total-adjust'},
				      	balance => $item->{'item-balance'},
				      	data_text_a => $item->{'pro-emergency'},
				      	data_num_a => $item->{'service-place'},
				      	data_num_b => $item->{'sevice-type'},
				      	data_date_a => $item->{'service-begin-date'},
                			data_date_b => $item->{'service-end-date'},
                			modifier => $item->{'procedure-modifier'},
					data_text_b => $item->{comments},
				      	data_num_c => $item->{'item-sequence'});
		}
	}

}

sub importinvoiceItemAdjust
{
	my ($self, $flags, $invoiceadjust, $claim,$invoice) = @_;
	my $personId = $claim->{id};
	my $invoiceId = $claim->{invoice}->{__invoice_id};
	my $dv = new Dumpvalue;
	$dv->dumpValue($invoiceId);
	my $itemType = App::Universal::INVOICEITEMTYPE_ADJUST;
	my $totalDummyItems = $STMTMGR_INVOICE->getRowCount($self, STMTMGRFLAG_NONE, 'selInvoiceItemCountByType', $invoiceId, $itemType);
	my $itemSeq = $totalDummyItems + 1;
	#my $dv = new Dumpvalue;
			#$dv->dumpValue($itemSeq);
	if(my $list = $invoiceadjust->{adjust})
	{
		 my $itemId = $self->schemaAction($flags, 'Invoice_Item', 'add',
			parent_id => $invoiceId,
			item_type => $itemType,
			data_num_c => $itemSeq);

			#my $dv = new Dumpvalue;
			#$dv->dumpValue($itemId);

		$list = [$list] if ref $list eq 'HASH';
		foreach my $item (@$list)
		{
			#my $itemId = $invoiceadjust->{__itemId};
			my $netAdjust = (0 - $item->{'adjustment-amount'} - $item->{'plan-paid'} - $item->{'writeoff-amount'});
			my $dv = new Dumpvalue;
			$dv->dumpValue($itemId);
			$self->schemaAction($flags, "Invoice_Item_Adjust", 'add',
				      	adjustment_type => $self->translateEnum($flags, "Adjust_Method", $item->{'adjustment-type'}->{type}),
				      	adjustment_amount => $item->{'adjustment-amount'},
				      	parent_id => $itemId,
				      	plan_allow => $item->{'plan-allow'},
				      	plan_paid => $item->{'plan-paid'},
				      	pay_date => $item->{'pay-date'},
				      	pay_type => $self->translateEnum($flags, "Payment_Type", $item->{'pay-type'}->{type}),
				      	pay_method =>  $self->translateEnum($flags, "Payment_Method", $item->{'pay-method'}->{type}),
				      	pay_ref => $item->{'pay-ref'},
				      	writeoff_code => $item->{'writeoff-code'},
				      	writeoff_amount => $item->{'writeoff-amount'},
				      	net_adjust => defined $netAdjust ? $netAdjust : undef,
				      	adjust_codes => $item->{'adjust-codes'},
				      	data_text_a => $item->{'comments'});

			my $invItem = $STMTMGR_INVOICE->getRowAsHash($self, STMTMGRFLAG_CACHE, 'selInvoiceItem', $itemId);

			my $totalAdjustForItem = $invItem->{total_adjust} + $netAdjust;
			my $balance = $invItem->{extended_cost} + $totalAdjustForItem;

			$self->schemaAction($flags,'Invoice_Item', 'update',
					item_id => $itemId || undef,
					total_adjust => defined $totalAdjustForItem ? $totalAdjustForItem : undef,
					balance => defined $balance ? $balance : undef);

			my $invoice = $STMTMGR_INVOICE->getRowAsHash($self, STMTMGRFLAG_CACHE, 'selInvoice', $invoiceId);

			my $totalAdjustForInvoice = $invoice->{total_adjust} + $netAdjust;
			my $balance = $invoice->{total_cost} + $totalAdjustForInvoice;

			$self->schemaAction($flags,'Invoice', 'update',
					invoice_id => $invoiceId || undef,
					total_adjust => defined $totalAdjustForInvoice ? $totalAdjustForInvoice : undef,
					balance => defined $balance ? $balance : undef);

		}
	}
}

sub importStruct
{
	my ($self, $flags, $claim) = @_;
	unless($claim)
	{
		$self->addError('$invoice parameter is required');
		return 0;
	}

	$self->{mainStruct} = $claim;
	my $item = $claim->{event};
		#my $dv = new Dumpvalue;
		#$dv->dumpValue($item);
	my $eventId = $self->schemaAction($flags, 'Event', 'add',
			owner_id => $item->{id},
			event_type => $self->translateEnum($flags, "Event_Type", $item->{type}),
			event_status => $self->translateEnum($flags, "Appt_Status", $item->{status}),
			subject => $item->{subject},
			start_time => $item->{'start-time'},
			duration => $item->{duration},
			facility_id => $item->{'facility-id'},
			scheduled_by_id => $item->{'scheduled-by-id'},
			scheduled_stamp => $item->{'scheduled-time'},
			remarks => $item->{remarks},
			checkin_stamp => $item->{'checkin-time'},
			checkout_stamp => $item->{'checkout-time'},
			checkout_by_id => $item->{'checkout-by-id'});

	if ( $eventId gt 0)
	{
		if(my $item = $claim->{event}->{'patient-id'})
		{

			#my $dv = new Dumpvalue;
			#$dv->dumpValue($eventId);
			$self->schemaAction($flags, 'Event_Attribute', 'add',
				 value_text => $item->{_text},
				 value_type => 0,
				 item_name => "Appointment/Attendee/Patient",
				 value_int => $self->translateEnum($flags, "Appt_Attendee_Type", $item->{type}),
				 parent_id => $eventId);

		}
		if (my $item = $claim->{event}->{'physician-id'})
		{
			my $parentId = $claim->{event}->{$eventId};
				#my $dv = new Dumpvalue;
			#$dv->dumpValue($eventId);
			 $self->schemaAction($flags, 'Event_Attribute', 'add',
					value_text => $item,
					value_type => 0,
					item_name => "Appointment/Attendee/Physician",
					parent_id => $eventId);
		}
	}

	$self->importTransaction($flags, $claim->{transaction}, $claim, $eventId);
	$self->importInvoice($flags, $claim->{invoice}, $claim, $claim->{transaction});
	$self->importProcedures($flags, $claim->{claimprocedures}, $claim, $claim->{invoice});
	$self->importinvoiceItemAdjust($flags, $claim->{invoiceadjust}, $claim, $claim->{invoice});
	#$self->importsubmitInvoice($flags, $claim->{'submitinvoice'}, $claim, $claim->{invoice}});

	#$self->importContactMethods($flags, $claim->{contactmethods}, $claim);
}

1;