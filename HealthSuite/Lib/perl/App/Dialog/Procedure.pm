##############################################################################
package App::Dialog::Procedure;
##############################################################################
use strict;
use DBI::StatementManager;
use App::Statements::Invoice;
use App::Statements::Person;
use App::Statements::Insurance;
use App::Statements::Transaction;
use App::Statements::Org;
use App::Statements::Catalog;
use App::IntelliCode;
use Carp;
use CGI::Dialog;
use App::Dialog::OnHold;
use CGI::Validator::Field;
use App::Universal;
use App::Dialog::Field::Invoice;
use Date::Manip;

use vars qw(@ISA %RESOURCE_MAP);
@ISA = qw(CGI::Dialog);

%RESOURCE_MAP = (
	'procedure' => {},
);

sub new
{
	my ($self, $command) = CGI::Dialog::new(@_, id => 'procedures', heading => '$Command Procedure/Lab');
	my $schema = $self->{schema};
	delete $self->{schema};  # make sure we don't store this!

	croak 'schema parameter required' unless $schema;

	$self->addContent(
		new CGI::Dialog::Field(type => 'hidden', name => 'item_type'),
		new CGI::Dialog::Field(type => 'hidden', name => 'claim_diags'),
		new CGI::Dialog::Field(type => 'hidden', name => 'data_num_a'),	#used to indicate if item is FFS (null if it isn't)
		
		new CGI::Dialog::Field(type => 'hidden', name => 'code_type'),
		new CGI::Dialog::Field(type => 'hidden', name => 'use_fee'),
		new CGI::Dialog::Field(type => 'hidden', name => 'fee_schedules_item_id'),	#for storing and updating fee schedules as attribute
		new CGI::Dialog::Field(type => 'hidden', name => 'fee_schedules_catalog_ids'),	#for storing the internal catalog ids of the fee schedules entered in
	

		new CGI::Dialog::Field::Duration(
				name => 'illness',
				caption => 'Illness: Similar/Current',
				begin_caption => 'Similar Illness Date',
				end_caption => 'Current Illness Date',
				readOnlyWhen => CGI::Dialog::DLGFLAG_UPDORREMOVE,
				invisibleWhen => CGI::Dialog::DLGFLAG_ADD
				),
		new CGI::Dialog::Field::Duration(
				name => 'disability',
				caption => 'Disability: Begin/End',
				begin_caption => 'Begin Date',
				end_caption => 'End Date',
				readOnlyWhen => CGI::Dialog::DLGFLAG_UPDORREMOVE,
				invisibleWhen => CGI::Dialog::DLGFLAG_ADD
				),
		new CGI::Dialog::Field::Duration(
				name => 'hospitalization',
				caption => 'Hospitalization: Admit/Discharge',
				begin_caption => 'Admission Date',
				end_caption => 'Discharge Date',
				readOnlyWhen => CGI::Dialog::DLGFLAG_UPDORREMOVE,
				invisibleWhen => CGI::Dialog::DLGFLAG_ADD
				),
		new CGI::Dialog::Field::Duration(
				name => 'service',
				caption => 'Service Dates: From/To',
				#begin_options => FLDFLAG_REQUIRED,
				begin_caption => 'From Date',
				end_caption => 'To Date'
				),
		#new App::Dialog::Field::ServicePlaceType(caption => 'Service Place'),
		#new CGI::Dialog::Field(
		#		caption => 'Service Place',
		#		name => "servplace",
		#		size => 6, options => FLDFLAG_REQUIRED,
		#		#defaultValue => 11,				
		#		findPopup => '/lookup/serviceplace'),
		new CGI::Dialog::Field(type=>'hidden', name => "servtype"),
					
		new App::Dialog::Field::ProcedureLine(name=>'cptModfField', caption => 'CPT / Modf'),
		new App::Dialog::Field::DiagnosesCheckbox(caption => 'ICD-9 Codes', options => FLDFLAG_REQUIRED, name => 'procdiags'),

		new CGI::Dialog::Field(caption => 'Fee Schedule(s)',
			name => 'fee_schedules',
			size => 24,
			findPopupAppendValue => ',',
			findPopup => '/lookup/catalog',
			#options => FLDFLAG_PERSIST,
		),
		new App::Dialog::Field::ProcedureChargeUnits(caption => 'Charge/Units',
			name => 'proc_charge_fields'
		),

		new CGI::Dialog::MultiField(caption => 'Units', name => 'units_emg_fields',
			fields => [
				new CGI::Dialog::Field(caption => 'Units', name => 'procunits', type => 'integer', size => 6, minValue => 1, value => 1, options => FLDFLAG_REQUIRED),
				new CGI::Dialog::Field(caption => 'EMG', name => 'emg', type => 'bool', style => 'check'),
			]),

		new CGI::Dialog::Field(caption => 'Unit Cost',
			name => 'alt_cost', 
			#type => 'select',
			#options => FLDFLAG_REQUIRED,
		),

		#new CGI::Dialog::Field(caption => 'Reference', name => 'reference'),
		new CGI::Dialog::Field(caption => 'Comments', name => 'comments', type => 'memo', cols => 25, rows => 4),
	);
	$self->{activityLog} =
	{
		level => 1,
		scope =>'invoice_item',
		key => "#param.invoice_id#",
		data => "Procedure #param.item_id# to claim <a href='/invoice/#param.invoice_id#'>#param.invoice_id#</a>"
	};

	$self->addFooter(new CGI::Dialog::Buttons(
							nextActions_add => [
								['Add Another Procedure', "/invoice/%param.invoice_id%/dialog/procedure/add", 1],
								['Put Claim On Hold', "/invoice/%param.invoice_id%/dialog/hold"],
								#['Submit Claim for Review', "/invoice/%param.invoice_id%/review"],
								['Submit Claim for Transfer', "/invoice/%param.invoice_id%/submit"],
								],
						cancelUrl => $self->{cancelUrl} || undef));

	return $self;
}

sub makeStateChanges
{
	my ($self, $page, $command, $dlgFlags) = @_;
	$self->SUPER::makeStateChanges($page, $command, $dlgFlags);

	my $procItem = App::Universal::INVOICEITEMTYPE_SERVICE;
	my $labItem = App::Universal::INVOICEITEMTYPE_LAB;
	my $invoiceId = $page->param('invoice_id');

	$self->setFieldFlags('alt_cost', FLDFLAG_INVISIBLE, 1);
	$self->setFieldFlags('units_emg_fields', FLDFLAG_INVISIBLE, 1);

	if($command eq 'add')
	{
		my $serviceInfo = $STMTMGR_INVOICE->getRowsAsHashList($page, STMTMGRFLAG_NONE, 'selInvoiceProcedureItems', $invoiceId, $procItem, $labItem);

		my $numOfHashes = scalar (@{$serviceInfo});
		my $idx = $numOfHashes - 1;

		if($numOfHashes > 0)
		{
			if($page->field('service_begin_date') eq '')
			{
				$page->field('service_begin_date', $serviceInfo->[$idx]->{service_begin_date});
			}

			if($page->field('service_end_date') eq '')
			{
				$page->field('service_end_date', $serviceInfo->[$idx]->{service_end_date});
			}
		}
	}	
}

sub populateData
{
	my ($self, $page, $command, $activeExecMode, $flags) = @_;
	my $invoiceId = $page->param('invoice_id');

	$page->field('claim_diags', $STMTMGR_INVOICE->getSingleValue($page, 0, 'selClaimDiags', $invoiceId));
	return unless $flags & CGI::Dialog::DLGFLAG_DATAENTRY_INITIAL;	
	$page->field('proccharge', $page->field('alt_cost'));
	$page->field('', $page->getDate());	
	my $sqlStampFmt = $page->defaultSqlStampFormat();
	my $itemId = $page->param('item_id');

	$STMTMGR_INVOICE->createFieldsFromSingleRow($page, STMTMGRFLAG_NONE, 'selProcedure', $itemId);
	$page->field('servtype','');	
	if($page->field('item_type') == App::Universal::INVOICEITEMTYPE_LAB)
	{
		$page->field('lab_indicator', 1)
	}

	my $itemDiagCodes = $STMTMGR_INVOICE->getSingleValue($page, STMTMGRFLAG_NONE, 'selRelDiags', $itemId);
	my @icdCodes = split(/[,\s]+/, $itemDiagCodes);
	$page->field('procdiags', @icdCodes);

	$STMTMGR_INVOICE->createFieldsFromSingleRow($page, STMTMGRFLAG_NONE, 'selInvoiceAttrIllness',$invoiceId);
	$STMTMGR_INVOICE->createFieldsFromSingleRow($page, STMTMGRFLAG_NONE, 'selInvoiceAttrDisability',$invoiceId);
	$STMTMGR_INVOICE->createFieldsFromSingleRow($page, STMTMGRFLAG_NONE, 'selInvoiceAttrHospitalization',$invoiceId);
	
	my $feeSchedules = $STMTMGR_INVOICE->getRowAsHash($page, STMTMGRFLAG_NONE, 'selInvoiceAttr', $invoiceId, 'Fee Schedules');
	$page->field('fee_schedules', $feeSchedules->{value_textb});
	$page->field('fee_schedules_item_id', $feeSchedules->{item_id});
}

sub execAction_submit
{
	my ($page, $command, $invoiceId, $resubmitFlag) = @_;

	#if resubmitFlag == 1, submitting to same carrier
	#if resubmitFlag == 2, submitting to next payer in invoice_billing
	if($resubmitFlag == 2)
	{
		$invoiceId = copyInvoice($page, $command, $invoiceId);
	}

	my $todaysDate = UnixDate('today', $page->defaultUnixDateFormat());
	my $invoice = $STMTMGR_INVOICE->getRowAsHash($page, STMTMGRFLAG_NONE, 'selInvoice', $invoiceId);
	my $mainTransData = $STMTMGR_TRANSACTION->getRowAsHash($page, STMTMGRFLAG_CACHE, 'selTransactionById', $invoice->{main_transaction});

	my $attrDataFlag = App::Universal::INVOICEFLAG_DATASTOREATTR;
	my $invoiceFlags = $invoice->{flags};
	my $claimType = $invoice->{invoice_subtype};
	my $invoiceType = $invoice->{invoice_type};
	#unless($invoiceFlags & $attrDataFlag)
	#{
		$STMTMGR_INVOICE->execute($page, STMTMGRFLAG_NONE, 'delPostSubmitAttributes', $invoiceId);
		$STMTMGR_INVOICE->execute($page, STMTMGRFLAG_NONE, 'delPostSubmitAddresses', $invoiceId);

		storeFacilityInfo($page, $command, $invoiceId, $invoice, $mainTransData);
		storeAuthorizations($page, $command, $invoiceId, $invoice, $mainTransData);
		storePatientInfo($page, $command, $invoiceId, $invoice, $mainTransData);
		storePatientEmployment($page, $command, $invoiceId, $invoice, $mainTransData);
		storeProviderInfo($page, $command, $invoiceId, $invoice, $mainTransData);		

		if($claimType != App::Universal::CLAIMTYPE_SELFPAY)
		{
			storeInsuranceInfo($page, $command, $invoiceId, $invoice, $mainTransData);
		}

		if($claimType == App::Universal::CLAIMTYPE_HMO)
		{
			hmoCapWriteoff($page, $command, $invoiceId, $invoice, $mainTransData);
		}

		createActiveProbTrans($page, $command, $invoiceId, $invoice, $mainTransData);		


		#----NOW UPDATE THE INVOICE STATUS AND SET THE FLAG----#

		if($invoice->{balance} == 0 && $claimType != App::Universal::CLAIMTYPE_HMO)
		{
			$page->schemaAction(
				'Invoice_Attribute', 'add',
				parent_id => $invoiceId || undef,
				item_name => 'Invoice/History/Item',
				value_type => App::Universal::ATTRTYPE_HISTORY,
				value_text => 'Closed',
				value_date => $todaysDate,
				_debug => 0
			);
		}
		else
		{
			$page->schemaAction(
				'Invoice', 'update',
				invoice_id => $invoiceId,
				invoice_status => $resubmitFlag == 1 ? App::Universal::INVOICESTATUS_APPEALED : App::Universal::INVOICESTATUS_SUBMITTED,
				submitter_id => $page->session('user_id') || undef,
				submit_date => $todaysDate || undef,
				flags => $invoiceFlags | $attrDataFlag,
				_debug => 0
			);

			# create invoice attribute for history of invoice status
			$page->schemaAction(
				'Invoice_Attribute', 'add',
				parent_id => $invoiceId,
				item_name => 'Invoice/History/Item',
				value_type => App::Universal::ATTRTYPE_HISTORY,
				value_text => $resubmitFlag == 1 ? 'Resubmitted' : 'Submitted',
				value_date => $todaysDate || undef,
				_debug => 0
			);
		}
	#}

	return $invoiceId;
}

sub copyInvoice
{
	my ($page, $command, $oldInvoiceId) = @_;
	my $oldInvoiceInfo = $STMTMGR_INVOICE->getRowAsHash($page, STMTMGRFLAG_NONE, 'selInvoice', $oldInvoiceId);

	my $sessOrgIntId = $page->session('org_internal_id');
	my $sessUser = $page->session('user_id');
	my $timeStamp = $page->getTimeStamp();
	my $todaysDate = $page->getDate();
	my $entityTypePerson = App::Universal::ENTITYTYPE_PERSON;
	my $entityTypeOrg = App::Universal::ENTITYTYPE_ORG;
	my $historyValueType = App::Universal::ATTRTYPE_HISTORY;

	my @claimDiags = split(/\s*,\s*/, $oldInvoiceInfo->{claim_diags});
	my $invoiceType = $oldInvoiceInfo->{invoice_type};
	my $newInvoiceId = $page->schemaAction(
		'Invoice', 'add',		
		invoice_type => defined $invoiceType ? $invoiceType : undef,
		#invoice_subtype => defined $claimType ? $claimType : undef,
		#invoice_status => defined $submitted ? $submitted : undef,
		invoice_date => $todaysDate || undef,
		main_transaction => $oldInvoiceInfo->{main_transaction} || undef,
		submitter_id => $oldInvoiceInfo->{submitter_id} || undef,
		claim_diags => join(', ', @claimDiags) || undef,
		owner_type => defined $entityTypeOrg ? $entityTypeOrg : undef,
		owner_id => $oldInvoiceInfo->{owner_id} || undef,
		client_type => defined $entityTypePerson ? $entityTypePerson : undef,
		client_id => $oldInvoiceInfo->{client_id} || undef,
		#billing_id => $oldInvoiceInfo->{billing_id} || undef,
		_debug => 0
	);


	#copy all attributes except history items
	my $attributes = $STMTMGR_INVOICE->getRowsAsHashList($page, STMTMGRFLAG_NONE, 'selAllAttributesExclHistory', $oldInvoiceId);
	foreach my $attr (@{$attributes})
	{
		my $valueType = $attr->{value_type};
		my $itemType = $attr->{item_type};
		my $valueInt = $attr->{value_int};
		my $valueIntB = $attr->{value_intb};
		$page->schemaAction(
			'Invoice_Attribute', 'add',
			parent_id => $newInvoiceId,
			item_type => defined $itemType ? $itemType : undef,
			item_name => $attr->{item_name} || undef,
			value_type => defined $valueType ? $valueType : undef,
			value_text => $attr->{value_text} || undef,
			value_textB => $attr->{value_textb} || undef,
			value_int => defined $valueInt ? $valueInt : undef,
			value_intB => defined $valueIntB ? $valueIntB : undef,
			value_float => $attr->{value_float} || undef,
			value_floatB => $attr->{value_floatb} || undef,
			value_date => $attr->{value_date} || undef,
			value_dateEnd => $attr->{value_dateend} || undef,
			value_dateA => $attr->{value_datea} || undef,
			value_dateB => $attr->{value_dateb} || undef,
			value_block => $attr->{value_block} || undef,
			_debug => 0
		);	
	}
	

	my $lineItems = $STMTMGR_INVOICE->getRowsAsHashList($page, STMTMGRFLAG_NONE, 'selInvoiceItems', $oldInvoiceId);
	foreach my $item (@{$lineItems})
	{
		my $itemType = $item->{item_type};
		my $emg = $item->{emergency};
		my $newItemId = $page->schemaAction(
			'Invoice_Item', 'add',
			parent_id => $newInvoiceId || undef,
			flags => $item->{flags} || undef,
			service_begin_date => $item->{service_begin_date} || undef,
			service_end_date => $item->{service_end_date} || undef,
			hcfa_service_place => defined $item->{hcfa_service_place} ? $item->{hcfa_service_place} : undef,
			hcfa_service_type => defined $item->{hcfa_service_type} ? $item->{hcfa_service_type} : undef,
			modifier => $item->{modifier} || undef,
			quantity => $item->{quantity} || undef,
			emergency => defined $emg ? $emg : undef,
			item_type => defined $itemType ? $itemType : undef,
			code => $item->{code} || undef,
			code_type => $item->{code_type} || undef,
			caption => $item->{caption} || undef,
			comments =>  $item->{comments} || undef,
			unit_cost => $item->{unit_cost} || undef,
			rel_diags => $item->{rel_diags} || undef,
			data_text_a => $item->{data_text_a} || undef,
			data_num_a => $item->{data_num_a} || undef,
			data_num_b => $item->{data_num_b} || undef,
			extended_cost => $item->{extended_cost} || undef,
			_debug => 0
		);

		my $adjustments = $STMTMGR_INVOICE->getRowsAsHashList($page, STMTMGRFLAG_NONE, 'selItemAdjustmentsByItemParent', $item->{item_id});
		my $newAdjId = '';
		foreach my $adjust (@{$adjustments})
		{
			my $adjType = $adjust->{adjustment_type};
			my $payType = $adjust->{pay_type};
			my $payMethod = $adjust->{pay_method};
			my $payerType = $adjust->{payer_type};
			my $writeoffCode = $adjust->{writeoff_code};
			$newAdjId = $page->schemaAction(
				'Invoice_Item_Adjust', 'add',
				adjustment_type => defined $adjType ? $adjType : undef,
				adjustment_amount => $adjust->{adjustment_amount} || undef,
				parent_id => $newItemId || undef,
				plan_allow => $adjust->{plan_allow} || undef,
				plan_paid => $adjust->{plan_paid} || undef,
				pay_date => $todaysDate,
				pay_type => defined $payType ? $payType : undef,
				pay_method => defined $payMethod ? $payMethod : undef,
				pay_ref => $adjust->{pay_ref} || undef,
				payer_type => defined $payerType ? $payerType : undef,
				payer_id => $adjust->{payer_id} || undef,
				writeoff_code => defined $writeoffCode ? $writeoffCode : 'NULL',
				writeoff_amount => $adjust->{writeoff_amount} || undef,
				comments => $adjust->{comments} || undef,
				_debug => 0
			);
			
			my $batchPayment = $STMTMGR_INVOICE->getRowsAsHashList($page, STMTMGRFLAG_NONE, 'selInvoiceAttr', $newInvoiceId, 'Invoice/Payment/Batch ID');
			foreach my $batch (@{$batchPayment})
			{				
				if($batch->{value_int} == $adjust->{adjustment_id})
				{
					$page->schemaAction(
						'Invoice_Attribute', 'update',
						item_id => $batch->{item_id},
						value_int => $newAdjId,
						_debug => 0
					);
				}
			}
		}
	}


	#copy old invoice's billing records
	my $billingInfo = $STMTMGR_INVOICE->getRowsAsHashList($page, STMTMGRFLAG_NONE, 'selInvoiceBillingRecs', $oldInvoiceId);
	my $billId = '';
	my $newPayerBillId = '';
	my $newInsIntId = '';
	my $billSeq = '';
	my $billPartyType = '';
	my $billStatus = '';
	my $oldPayerSeq = '';
	foreach my $billingRec (@{$billingInfo})
	{
		$billSeq = $billingRec->{bill_sequence};
		$billPartyType = $billingRec->{bill_party_type};
		$billStatus = $billingRec->{bill_status};
		if($billingRec->{bill_id} == $oldInvoiceInfo->{billing_id})
		{
			$oldPayerSeq = $billSeq;
			$billStatus = 'inactive';
		}

		$billId = $page->schemaAction(
			'Invoice_Billing', 'add',
			invoice_id => $newInvoiceId || undef,
			invoice_item_id => $billingRec->{invoice_item_id} || undef,
			assoc_bill_id => $billingRec->{assoc_bill_id} || undef,
			bill_sequence => defined $billSeq ? $billSeq : undef,
			bill_party_type => defined $billPartyType ? $billPartyType : undef,
			bill_to_id => $billingRec->{bill_to_id} || undef,
			bill_ins_id => $billingRec->{bill_ins_id} || undef,
			bill_amount => $billingRec->{bill_amount} || undef,
			bill_pct => $billingRec->{bill_pct} || undef,
			bill_date => $billingRec->{bill_date} || undef,
			bill_status => $billStatus || undef,
			bill_result => $billingRec->{bill_result} || undef,
			_debug => 0
		);
		
		if($billSeq == $oldPayerSeq + 1)
		{
			$newPayerBillId = $billId;
			$newInsIntId = $billingRec->{bill_ins_id};
		}
	}


	#update the new invoice with its new billing id and claim type
	my $claimType = $newInsIntId ? $STMTMGR_INSURANCE->getSingleValue($page, STMTMGRFLAG_NONE, 'selInsType', $newInsIntId) : 0;
	my $invoiceStatus = $claimType == App::Universal::CLAIMTYPE_SELFPAY ? App::Universal::INVOICESTATUS_CREATED : App::Universal::INVOICESTATUS_SUBMITTED;
	$page->schemaAction(
		'Invoice', 'update',
		invoice_id => $newInvoiceId || undef,
		invoice_status => defined $invoiceStatus ? $invoiceStatus : undef,
		invoice_subtype => defined $claimType ? $claimType : undef,
		billing_id => $newPayerBillId,
	);


	#update the submission order attribute
	my $submitOrder = $STMTMGR_INVOICE->getRowAsHash($page, STMTMGRFLAG_NONE, 'selInvoiceAttr', $newInvoiceId, 'Submission Order');
	$page->schemaAction(
		'Invoice_Attribute', 'update',
		item_id => $submitOrder->{item_id},
		value_int => $submitOrder->{value_int} + 1,
		_debug => 0
	);

	#update the patient control number attribute
	my $patientControlNo = $STMTMGR_INVOICE->getRowAsHash($page, STMTMGRFLAG_NONE, 'selInvoiceAttr', $newInvoiceId, 'Patient/Control Number');
	$page->schemaAction(
		'Invoice_Attribute', 'update',
		item_id => $patientControlNo->{item_id},
		value_text => $newInvoiceId,
		_debug => 0
	);

	#add new history attributes
	$page->schemaAction(
		'Invoice_Attribute', 'add',
		parent_id => $newInvoiceId || undef,
		item_name => 'Invoice/History/Item',
		value_type => defined $historyValueType ? $historyValueType : undef,
		value_text => 'Created claim',
		value_date => $todaysDate,
		_debug => 0
	);

	$page->schemaAction(
		'Invoice_Attribute', 'add',
		parent_id => $newInvoiceId,
		item_name => 'Invoice/History/Item',
		value_type => defined $historyValueType ? $historyValueType : undef,
		value_text => "This invoice is a resubmitted copy of invoice $oldInvoiceId",
		value_date => $todaysDate,
		_debug => 0
	);


	#update old invoice - status, parent invoice
	$page->schemaAction(
		'Invoice', 'update',
		invoice_id => $oldInvoiceId || undef,
		parent_invoice_id => $newInvoiceId || undef,
		invoice_status => App::Universal::INVOICESTATUS_CLOSED,
	);

	$page->schemaAction(
		'Invoice_Attribute', 'add',
		parent_id => $oldInvoiceId,
		item_name => 'Invoice/History/Item',
		value_type => defined $historyValueType ? $historyValueType : undef,
		value_text => "The remaining balance has been carried over to claim $newInvoiceId",
		value_date => $todaysDate,
		_debug => 0
	);

	$page->schemaAction(
		'Invoice_Attribute', 'add',
		parent_id => $oldInvoiceId || undef,
		item_name => 'Invoice/History/Item',
		value_type => defined $historyValueType ? $historyValueType : undef,
		value_text => 'Closed',
		value_date => $todaysDate,
		_debug => 0
	);

	return $newInvoiceId;
}

sub hmoCapWriteoff
{
	my ($page, $command, $invoiceId, $invoice, $mainTransData) = @_;

	my $todaysDate = UnixDate('today', $page->defaultUnixDateFormat());
	my $writeoffCode = App::Universal::ADJUSTWRITEOFF_CONTRACTAGREEMENT;

	my $totalAdjForItems = 0;
	my $procItems = $STMTMGR_INVOICE->getRowsAsHashList($page, STMTMGRFLAG_NONE, 'selInvoiceItems', $invoiceId);
	foreach my $proc (@{$procItems})
	{
		next if $proc->{item_type} == App::Universal::INVOICEITEMTYPE_ADJUST || $proc->{item_type} == App::Universal::INVOICEITEMTYPE_COPAY 
			|| $proc->{item_type} == App::Universal::INVOICEITEMTYPE_DEDUCTIBLE || $proc->{item_type} == App::Universal::INVOICEITEMTYPE_VOID;
		next if $proc->{data_num_a};	#data_num_a indicates that this item is FFS (null if it isn't)
		next if $proc->{data_text_b} eq 'void';	#data_text_b indicates that this item has been voided
		
		my $writeoffAmt = $proc->{balance};
		my $itemId = $proc->{item_id};
		$page->schemaAction(
			'Invoice_Item_Adjust', 'add',
			parent_id => $itemId || undef,
			adjustment_type => App::Universal::ADJUSTMENTTYPE_AUTOINSWRITEOFF,
			pay_date => $todaysDate,
			writeoff_code => defined $writeoffCode ? $writeoffCode : undef,
			writeoff_amount => defined $writeoffAmt ? $writeoffAmt : undef,
			comments => 'Writeoff auto-generated by system',
			_debug => 0
		);	
	}


	## create invoice attribute for history of these adjustments
	$page->schemaAction(
			'Invoice_Attribute', 'add',
			parent_id => $invoiceId,
			item_name => 'Invoice/History/Item',
			value_type => App::Universal::ATTRTYPE_HISTORY,
			value_text => 'Auto-generated writeoffs for HMO Capitated claim',
			value_date => $todaysDate || undef,
			_debug => 0
	);
}

sub storeFacilityInfo
{
	my ($page, $command, $invoiceId, $invoice, $mainTransData) = @_;

	my $textValueType = App::Universal::ATTRTYPE_TEXT;
	my $credentialsValueType = App::Universal::ATTRTYPE_CREDENTIALS;

	##billing facility information
	my $billFacilityId = $mainTransData->{billing_facility_id};
	my $billingFacilityAddr = $STMTMGR_ORG->getRowAsHash($page, STMTMGRFLAG_CACHE, 'selOrgAddressByAddrName', $billFacilityId, 'Mailing');
	my $billingFacilityPayAddr = $STMTMGR_ORG->getRowAsHash($page, STMTMGRFLAG_CACHE, 'selOrgAddressByAddrName', $billFacilityId, 'Payment');
	my $billingFacilityInfo = $STMTMGR_ORG->getRowAsHash($page, STMTMGRFLAG_NONE, 'selRegistry', $billFacilityId);

	my $employerNo = $STMTMGR_ORG->getRowAsHash($page, STMTMGRFLAG_CACHE, 'selAttributeByItemNameAndValueTypeAndParent', $billFacilityId, 'Employer#', $credentialsValueType);
	my $stateNo = $STMTMGR_ORG->getRowAsHash($page, STMTMGRFLAG_CACHE, 'selAttributeByItemNameAndValueTypeAndParent', $billFacilityId, 'State#', $credentialsValueType);
	my $medicaidNo = $STMTMGR_ORG->getRowAsHash($page, STMTMGRFLAG_CACHE, 'selAttributeByItemNameAndValueTypeAndParent', $billFacilityId, 'Medicaid#', $credentialsValueType);
	my $wrkCompNo = $STMTMGR_ORG->getRowAsHash($page, STMTMGRFLAG_CACHE, 'selAttributeByItemNameAndValueTypeAndParent', $billFacilityId, 'Workers Comp#', $credentialsValueType);
	my $bcbsNo = $STMTMGR_ORG->getRowAsHash($page, STMTMGRFLAG_CACHE, 'selAttributeByItemNameAndValueTypeAndParent', $billFacilityId, 'BCBS#', $credentialsValueType);
	my $medicareNo = $STMTMGR_ORG->getRowAsHash($page, STMTMGRFLAG_CACHE, 'selAttributeByItemNameAndValueTypeAndParent', $billFacilityId, 'Medicare#', $credentialsValueType);
	my $cliaNo = $STMTMGR_ORG->getRowAsHash($page, STMTMGRFLAG_CACHE, 'selAttributeByItemNameAndValueTypeAndParent', $billFacilityId, 'CLIA#', $credentialsValueType);

	$page->schemaAction(
			'Invoice_Attribute', $command,
			parent_id => $invoiceId,
			item_name => 'Billing Facility/Name',
			value_type => defined $textValueType ? $textValueType : undef,
			value_text => $billingFacilityInfo->{name_primary} || undef,
			value_textB => $billingFacilityInfo->{org_id} || undef,
			value_int => $billFacilityId || undef,
			value_intB => 1,
			_debug => 0
		);

	$page->schemaAction(
			'Invoice_Attribute', $command,
			parent_id => $invoiceId,
			item_name => 'Billing Facility/Tax ID',
			value_type => defined $textValueType ? $textValueType : undef,
			value_text => $billingFacilityInfo->{tax_id} || undef,
			value_textB => $billingFacilityInfo->{org_id} || undef,
			value_int => $billFacilityId || undef,
			value_intB => 1,
			_debug => 0
		);

	$page->schemaAction(
			'Invoice_Attribute', $command,
			parent_id => $invoiceId,
			item_name => 'Billing Facility/Employer Number',
			value_type => defined $textValueType ? $textValueType : undef,
			value_text => $employerNo->{value_text} || undef,
			value_textB => $billingFacilityInfo->{org_id} || undef,
			value_int => $billFacilityId || undef,
			value_intB => 1,
			_debug => 0
		);
		
	$page->schemaAction(
			'Invoice_Attribute', $command,
			parent_id => $invoiceId,
			item_name => 'Billing Facility/State',
			value_type => defined $textValueType ? $textValueType : undef,
			value_text => $stateNo->{value_text} || undef,
			value_textB => $billingFacilityInfo->{org_id} || undef,
			value_int => $billFacilityId || undef,
			value_intB => 1,
			_debug => 0
		);
		
	$page->schemaAction(
			'Invoice_Attribute', $command,
			parent_id => $invoiceId,
			item_name => 'Billing Facility/Medicaid',
			value_type => defined $textValueType ? $textValueType : undef,
			value_text => $medicaidNo->{value_text} || undef,
			value_textB => $billingFacilityInfo->{org_id} || undef,
			value_int => $billFacilityId || undef,
			value_intB => 1,
			_debug => 0
		);

	$page->schemaAction(
			'Invoice_Attribute', $command,
			parent_id => $invoiceId,
			item_name => 'Billing Facility/Workers Comp',
			value_type => defined $textValueType ? $textValueType : undef,
			value_text => $wrkCompNo->{value_text} || undef,
			value_textB => $billingFacilityInfo->{org_id} || undef,
			value_int => $billFacilityId || undef,
			value_intB => 1,
			_debug => 0
		);
		
	$page->schemaAction(
			'Invoice_Attribute', $command,
			parent_id => $invoiceId,
			item_name => 'Billing Facility/BCBS',
			value_type => defined $textValueType ? $textValueType : undef,
			value_text => $bcbsNo->{value_text} || undef,
			value_textB => $billingFacilityInfo->{org_id} || undef,
			value_int => $billFacilityId || undef,
			value_intB => 1,
			_debug => 0
		);

	$page->schemaAction(
			'Invoice_Attribute', $command,
			parent_id => $invoiceId,
			item_name => 'Billing Facility/Medicare',
			value_type => defined $textValueType ? $textValueType : undef,
			value_text => $medicareNo->{value_text} || undef,
			value_textB => $billingFacilityInfo->{org_id} || undef,
			value_int => $billFacilityId || undef,
			value_intB => 1,
			_debug => 0
		);

	$page->schemaAction(
			'Invoice_Attribute', $command,
			parent_id => $invoiceId,
			item_name => 'Billing Facility/CLIA',
			value_type => defined $textValueType ? $textValueType : undef,
			value_text => $cliaNo->{value_text} || undef,
			value_textB => $billingFacilityInfo->{org_id} || undef,
			value_int => $billFacilityId || undef,
			value_intB => 1,
			_debug => 0
		);

	$page->schemaAction(
			'Invoice_Address', $command,
			parent_id => $invoiceId,
			address_name => 'Billing',
			line1 => $billingFacilityAddr->{line1} || undef,
			line2 => $billingFacilityAddr->{line2} || undef,
			city => $billingFacilityAddr->{city} || undef,
			state => $billingFacilityAddr->{state} || undef,
			zip => $billingFacilityAddr->{zip} || undef,
			_debug => 0
		);

	$page->schemaAction(
			'Invoice_Address', $command,
			parent_id => $invoiceId,
			address_name => 'Pay To Org',
			line1 => $billingFacilityPayAddr->{line1},
			line2 => $billingFacilityPayAddr->{line2} || undef,
			city => $billingFacilityPayAddr->{city},
			state => $billingFacilityPayAddr->{state},
			zip => $billingFacilityPayAddr->{zip},
			_debug => 0
	);


	##SERVICE FACILITY INFORMATION
	my $servFacilityId = $mainTransData->{service_facility_id};
	my $serviceFacilityAddr = $STMTMGR_ORG->getRowAsHash($page, STMTMGRFLAG_CACHE, 'selOrgAddressByAddrName', $servFacilityId, 'Mailing');
	my $serviceFacilityInfo = $STMTMGR_ORG->getRowAsHash($page, STMTMGRFLAG_NONE, 'selRegistry', $servFacilityId);

	$page->schemaAction(
			'Invoice_Attribute', $command,
			parent_id => $invoiceId,
			item_name => 'Service Facility/Name',
			value_type => defined $textValueType ? $textValueType : undef,
			value_text => $serviceFacilityInfo->{name_primary} || undef,
			value_textB => $serviceFacilityInfo->{org_id} || undef,
			value_int => $servFacilityId || undef,
			value_intB => 1,
			_debug => 0
		);

	$page->schemaAction(
			'Invoice_Address', $command,
			parent_id => $invoiceId,
			address_name => 'Service',
			line1 => $serviceFacilityAddr->{line1} || undef,
			line2 => $serviceFacilityAddr->{line2} || undef,
			city => $serviceFacilityAddr->{city} || undef,
			state => $serviceFacilityAddr->{state} || undef,
			zip => $serviceFacilityAddr->{zip} || undef,
			_debug => 0
		);

	#store pay to org address
	#my $payToOrg = $STMTMGR_INVOICE->getRowAsHash($page, STMTMGRFLAG_NONE, 'selInvoiceAttr', $invoiceId, 'Pay To Org/Name');
	#my $payToFacilityAddr = $STMTMGR_ORG->getRowAsHash($page, STMTMGRFLAG_CACHE, 'selOrgAddressByAddrName', $payToOrg->{value_int}, 'Mailing');

	#$page->schemaAction(
	#		'Invoice_Address', $command,
	#		parent_id => $invoiceId,
	#		address_name => 'Pay To Org',
	#		line1 => $payToFacilityAddr->{line1},
	#		line2 => $payToFacilityAddr->{line2} || undef,
	#		city => $payToFacilityAddr->{city},
	#		state => $payToFacilityAddr->{state},
	#		zip => $payToFacilityAddr->{zip},
	#		_debug => 0
	#);
}

sub storeAuthorizations
{
	my ($page, $command, $invoiceId, $invoice, $mainTransData) = @_;

	my $textValueType = App::Universal::ATTRTYPE_TEXT;
	my $boolValueType = App::Universal::ATTRTYPE_BOOLEAN;
	my $dateValueType = App::Universal::ATTRTYPE_DATE;
	my $todaysDate = UnixDate('today', $page->defaultUnixDateFormat());

	my $clientId = $invoice->{client_id};
	my $patSignature = $STMTMGR_PERSON->getRowAsHash($page, STMTMGRFLAG_NONE, 'selAttributeByPersonAndValueType', $clientId, App::Universal::ATTRTYPE_AUTHPATIENTSIGN);
	my $provAssign = $STMTMGR_PERSON->getRowAsHash($page, STMTMGRFLAG_NONE, 'selAttributeByPersonAndValueType', $clientId, App::Universal::ATTRTYPE_AUTHPROVIDERASSIGN);
	my $infoRelease = $STMTMGR_PERSON->getRowAsHash($page, STMTMGRFLAG_NONE, 'selAttributeByPersonAndValueType', $clientId, App::Universal::ATTRTYPE_AUTHINFORELEASE);

	$page->schemaAction(
			'Invoice_Attribute', $command,
			parent_id => $invoiceId || undef,
			item_name => 'Patient/Signature',
			value_type => defined $textValueType ? $textValueType : undef,
			value_text => $patSignature->{value_text} || undef,
			value_textB => $patSignature->{value_textb} || undef,
			value_date => $patSignature->{value_date} || undef,
			value_intB => 1,
			_debug => 0
		);

	$page->schemaAction(
			'Invoice_Attribute', $command,
			parent_id => $invoiceId || undef,
			item_name => 'Provider/Assign Indicator',
			value_type => defined $textValueType ? $textValueType : undef,
			value_text => $provAssign->{value_text} || undef,
			value_textB => $provAssign->{value_textb} || undef,
			value_intB => 1,
			_debug => 0
		);

	my $infoRelIndctr = $infoRelease->{value_text} eq 'Yes' ? 1 : 0;
	$page->schemaAction(
			'Invoice_Attribute', $command,
			parent_id => $invoiceId || undef,
			item_name => 'Information Release/Indicator',
			value_type => defined $boolValueType ? $boolValueType : undef,
			value_int => defined $infoRelIndctr ? $infoRelIndctr : undef,
			value_date => $infoRelease->{value_date} || undef,
			value_intB => 1,
			_debug => 0
		);

	$page->schemaAction(
			'Invoice_Attribute', $command,
			parent_id => $invoiceId || undef,
			item_name => 'Provider/Signature/Date',
			value_type => defined $dateValueType ? $dateValueType : undef,
			value_date => $todaysDate || undef,
			value_intB => 1,
			_debug => 0
		);
}

sub storePatientInfo
{
	my ($page, $command, $invoiceId, $invoice, $mainTransData) = @_;
	
	my $textValueType = App::Universal::ATTRTYPE_TEXT;
	my $phoneValueType = App::Universal::ATTRTYPE_PHONE;
	my $dateValueType = App::Universal::ATTRTYPE_DATE;

	my $clientId = $invoice->{client_id};
	my $personData = $STMTMGR_PERSON->getRowAsHash($page, STMTMGRFLAG_CACHE, 'selRegistry', $clientId);
	my $personPhone = $STMTMGR_PERSON->getSingleValue($page, STMTMGRFLAG_CACHE, 'selHomePhone', $clientId);
	my $personAddr = $STMTMGR_PERSON->getRowAsHash($page, STMTMGRFLAG_NONE, 'selHomeAddress', $clientId);

	$page->schemaAction(
			'Invoice_Address', $command,
			parent_id => $invoiceId,
			address_name => 'Patient',
			line1 => $personAddr->{line1} || undef,
			line2 => $personAddr->{line2} || undef,
			city => $personAddr->{city} || undef,
			state => $personAddr->{state} || undef,
			zip => $personAddr->{zip} || undef,
			_debug => 0
		);

	$page->schemaAction(
			'Invoice_Attribute', $command,
			parent_id => $invoiceId,
			item_name => 'Patient/Name',
			value_type => defined $textValueType ? $textValueType : undef,
			value_text => $personData->{complete_name} || undef,
			value_textB => $clientId || undef,
			value_intB => 1,
			_debug => 0
		);

	$page->schemaAction(
			'Invoice_Attribute', $command,
			parent_id => $invoiceId,
			item_name => 'Patient/Name/Last',
			value_type => defined $textValueType ? $textValueType : undef,
			value_text => $personData->{name_last} || undef,
			value_textB => $clientId || undef,
			value_intB => 1,
			_debug => 0
		);

	$page->schemaAction(
			'Invoice_Attribute', $command,
			parent_id => $invoiceId,
			item_name => 'Patient/Name/First',
			value_type => defined $textValueType ? $textValueType : undef,
			value_text => $personData->{name_first} || undef,
			value_textB => $clientId || undef,
			value_intB => 1,
			_debug => 0
		);

	$page->schemaAction(
			'Invoice_Attribute', $command,
			parent_id => $invoiceId,
			item_name => 'Patient/Name/Middle',
			value_type => defined $textValueType ? $textValueType : undef,
			value_text => $personData->{name_middle} || undef,
			value_textB => $clientId || undef,
			value_intB => 1,
			_debug => 0
		) if $personData->{name_middle} ne '';

	$page->schemaAction(
			'Invoice_Attribute', $command,
			parent_id => $invoiceId,
			item_name => 'Patient/Account Number',
			value_type => defined $textValueType ? $textValueType : undef,
			value_text => $personData->{person_ref} || undef,
			value_intB => 1,
			_debug => 0
		);

	$page->schemaAction(
			'Invoice_Attribute', $command,
			parent_id => $invoiceId,
			item_name => 'Patient/Contact/Home Phone',
			value_type => defined $phoneValueType ? $phoneValueType : undef,
			value_text => $personPhone || undef,
			value_intB => 1,
			_debug => 0
		);

	$page->schemaAction(
			'Invoice_Attribute', $command,
			parent_id => $invoiceId,
			item_name => 'Patient/Personal/Marital Status',
			value_type => defined $textValueType ? $textValueType : undef,
			value_text => $personData->{marstat_caption} || undef,
			value_intB => 1,
			_debug => 0
		);

	$page->schemaAction(
			'Invoice_Attribute', $command,
			parent_id => $invoiceId,
			item_name => 'Patient/Personal/Gender',
			value_type => defined $textValueType ? $textValueType : undef,
			value_text => $personData->{gender_caption} || undef,
			value_intB => 1,
			_debug => 0
		);

	$page->schemaAction(
			'Invoice_Attribute', $command,
			parent_id => $invoiceId,
			item_name => 'Patient/Personal/DOB',
			value_type => defined $dateValueType ? $dateValueType : undef,
			value_date => $personData->{date_of_birth} || undef,
			value_intB => 1,
			_debug => 0
		);
}

sub storePatientEmployment
{
	my ($page, $command, $invoiceId, $invoice, $mainTransData) = @_;

	my $textValueType = App::Universal::ATTRTYPE_TEXT;

	# a list of employment statuses:
	my $ftEmployAttr = App::Universal::ATTRTYPE_EMPLOYEDFULL;	#220
	my $ptEmployAttr = App::Universal::ATTRTYPE_EMPLOYEDPART;	#221
	my $selfEmployAttr = App::Universal::ATTRTYPE_SELFEMPLOYED;	#222
	my $retiredAttr = App::Universal::ATTRTYPE_RETIRED;			#223
	my $ftStudentAttr = App::Universal::ATTRTYPE_STUDENTFULL;	#224
	my $ptStudentAttr = App::Universal::ATTRTYPE_STUDENTPART;	#225
	my $unknownAttr = App::Universal::ATTRTYPE_EMPLOYUNKNOWN;	#226

	my $personEmployStat = $STMTMGR_PERSON->getRowsAsHashList($page, STMTMGRFLAG_CACHE, 'selEmploymentStatusCaption', $invoice->{client_id});
	foreach my $employStat (@{$personEmployStat})
	{
		my $valueType = $employStat->{value_type};
	
		my $status = '';
		$status = $employStat->{caption};
		$status = 'Retired' if $valueType == $retiredAttr;
		$status = 'Employed' if $valueType >= $ftEmployAttr && $valueType <= $selfEmployAttr;

		if($status eq 'Employed')
		{
			$page->schemaAction(
					'Invoice_Attribute', $command,
					parent_id => $invoiceId,
					item_name => 'Patient/Employment/Status',
					value_type => defined $valueType ? $valueType : undef,
					value_text => $status || undef,
					value_intB => 1,
					_debug => 0
				);
		}
		elsif($status eq 'Student (Full-Time)' || $status eq 'Student (Part-Time)')
		{
			$page->schemaAction(
					'Invoice_Attribute', $command,
					parent_id => $invoiceId,
					item_name => 'Patient/Student/Status',
					value_type => defined $valueType ? $valueType : undef,
					value_text => $status || undef,
					value_intB => 1,
					_debug => 0
				);
		}
	}
}

sub storeProviderInfo
{
	my ($page, $command, $invoiceId, $invoice, $mainTransData) = @_;
	
	my $textValueType = App::Universal::ATTRTYPE_TEXT;
	my $licenseValueType = App::Universal::ATTRTYPE_LICENSE;
	my $sessOrgId = $page->session('org_id');
	my $providerId = $mainTransData->{provider_id};
	my $servFacilityId = $STMTMGR_ORG->getSingleValue($page, STMTMGRFLAG_NONE, 'selId', $mainTransData->{service_facility_id});

	my $providerInfo = $STMTMGR_PERSON->getRowAsHash($page, STMTMGRFLAG_CACHE, 'selRegistry', $providerId);

	my $providerSpecialty = $STMTMGR_PERSON->getRowAsHash($page, STMTMGRFLAG_CACHE, 'selAttributeByItemNameAndValueTypeAndParent', $providerId, 'Primary', App::Universal::ATTRTYPE_SPECIALTY);

	my $providerTaxId = $STMTMGR_PERSON->getRowAsHash($page, STMTMGRFLAG_CACHE, 'selAttrByItemNameParentNameSort', $providerId, 'Tax ID', $servFacilityId);
	my $tax = $providerTaxId->{value_text};
	if($tax eq '')
	{
		$providerTaxId = $STMTMGR_PERSON->getRowAsHash($page, STMTMGRFLAG_CACHE, 'selAttrByItemNameParentNameSort', $providerId, 'Tax ID', $sessOrgId);
		$tax = $providerTaxId->{value_text};
	}

	my $providerUpin = $STMTMGR_PERSON->getRowAsHash($page, STMTMGRFLAG_CACHE, 'selAttrByItemNameParentNameSort', $providerId, 'UPIN', $servFacilityId);
	my $upin = $providerUpin->{value_text};
	if($upin eq '')
	{
		$providerUpin = $STMTMGR_PERSON->getRowAsHash($page, STMTMGRFLAG_CACHE, 'selAttrByItemNameParentNameSort', $providerId, 'UPIN', $sessOrgId);
		$upin = $providerUpin->{value_text};
	}
	
	my $providerBcbs = $STMTMGR_PERSON->getRowAsHash($page, STMTMGRFLAG_CACHE, 'selAttrByItemNameParentNameSort', $providerId, 'BCBS', $servFacilityId);
	my $bcbs = $providerBcbs->{value_text};
	if($bcbs eq '')
	{
		$providerBcbs = $STMTMGR_PERSON->getRowAsHash($page, STMTMGRFLAG_CACHE, 'selAttrByItemNameParentNameSort', $providerId, 'BCBS', $sessOrgId);
		$bcbs = $providerBcbs->{value_text};
	}

	my $providerMedicare = $STMTMGR_PERSON->getRowAsHash($page, STMTMGRFLAG_CACHE, 'selAttrByItemNameParentNameSort', $providerId, 'Medicare', $servFacilityId);
	my $medicare = $providerMedicare->{value_text};
	if($medicare eq '')
	{
		$providerMedicare = $STMTMGR_PERSON->getRowAsHash($page, STMTMGRFLAG_CACHE, 'selAttrByItemNameParentNameSort', $providerId, 'Medicare', $sessOrgId);
		$medicare = $providerMedicare->{value_text};
	}

	my $providerMedicaid = $STMTMGR_PERSON->getRowAsHash($page, STMTMGRFLAG_CACHE, 'selAttrByItemNameParentNameSort', $providerId, 'Medicaid', $servFacilityId);
	my $medicaid = $providerMedicaid->{value_text};
	if($medicaid eq '')
	{
		$providerMedicaid = $STMTMGR_PERSON->getRowAsHash($page, STMTMGRFLAG_CACHE, 'selAttrByItemNameParentNameSort', $providerId, 'Medicaid', $sessOrgId);
		$medicaid = $providerMedicaid->{value_text};
	}

	my $providerChampus = $STMTMGR_PERSON->getRowAsHash($page, STMTMGRFLAG_CACHE, 'selAttrByItemNameParentNameSort', $providerId, 'Champus', $servFacilityId);
	my $champus = $providerChampus->{value_text};
	if($champus eq '')
	{
		$providerChampus = $STMTMGR_PERSON->getRowAsHash($page, STMTMGRFLAG_CACHE, 'selAttrByItemNameParentNameSort', $providerId, 'Champus', $sessOrgId);
		$champus = $providerChampus->{value_text};
	}

	my $providerWorkComp = $STMTMGR_PERSON->getRowAsHash($page, STMTMGRFLAG_CACHE, 'selAttrByItemNameParentNameSort', $providerId, 'WC#', $servFacilityId);
	my $wc = $providerWorkComp->{value_text};
	if($wc eq '')
	{
		$providerWorkComp = $STMTMGR_PERSON->getRowAsHash($page, STMTMGRFLAG_CACHE, 'selAttrByItemNameParentNameSort', $providerId, 'WC#', $sessOrgId);
		$wc = $providerWorkComp->{value_text};
	}

	$page->schemaAction(
			'Invoice_Attribute', $command,
			parent_id => $invoiceId,
			item_name => 'Provider/Name',
			value_type => defined $textValueType ? $textValueType : undef,
			value_text => $providerInfo->{complete_name} || undef,
			value_textB => $providerId || undef,
			value_intB => 1,
			_debug => 0
		);

	$page->schemaAction(
			'Invoice_Attribute', $command,
			parent_id => $invoiceId,
			item_name => 'Provider/Name/First',
			value_type => defined $textValueType ? $textValueType : undef,
			value_text => $providerInfo->{name_first} || undef,
			value_textB => $providerId || undef,
			value_intB => 1,
			_debug => 0
		);

	$page->schemaAction(
			'Invoice_Attribute', $command,
			parent_id => $invoiceId,
			item_name => 'Provider/Name/Middle',
			value_type => defined $textValueType ? $textValueType : undef,
			value_text => $providerInfo->{name_middle} || undef,
			value_textB => $providerId || undef,
			value_intB => 1,
			_debug => 0
		) if $providerInfo->{name_middle} ne '';

	$page->schemaAction(
			'Invoice_Attribute', $command,
			parent_id => $invoiceId,
			item_name => 'Provider/Name/Last',
			value_type => defined $textValueType ? $textValueType : undef,
			value_text => $providerInfo->{name_last} || undef,
			value_textB => $providerId || undef,
			value_intB => 1,
			_debug => 0
		);

	$page->schemaAction(
			'Invoice_Attribute', $command,
			parent_id => $invoiceId,
			item_name => 'Provider/Specialty',
			value_type => defined $textValueType ? $textValueType : undef,
			value_text => $providerSpecialty->{value_text} || undef,
			value_textB => $providerSpecialty->{value_textb} || undef,
			value_intB => 1,
			_debug => 0
		);

	$page->schemaAction(
			'Invoice_Attribute', $command,
			parent_id => $invoiceId,
			item_name => 'Provider/Tax ID',
			value_type => defined $licenseValueType ? $licenseValueType : undef,
			value_text => $tax || undef,
			value_intB => 1,
			_debug => 0
		);

	$page->schemaAction(
			'Invoice_Attribute', $command,
			parent_id => $invoiceId,
			item_name => 'Provider/UPIN',
			value_type => defined $licenseValueType ? $licenseValueType : undef,
			value_text => $upin || undef,
			value_intB => 1,
			_debug => 0
		);

	$page->schemaAction(
			'Invoice_Attribute', $command,
			parent_id => $invoiceId,
			item_name => 'Provider/BCBS',
			value_type => defined $licenseValueType ? $licenseValueType : undef,
			value_text => $bcbs || undef,
			value_intB => 1,
			_debug => 0
		);

	$page->schemaAction(
			'Invoice_Attribute', $command,
			parent_id => $invoiceId,
			item_name => 'Provider/Medicare',
			value_type => defined $licenseValueType ? $licenseValueType : undef,
			value_text => $medicare || undef,
			value_intB => 1,
			_debug => 0
		);

	$page->schemaAction(
			'Invoice_Attribute', $command,
			parent_id => $invoiceId,
			item_name => 'Provider/Medicaid',
			value_type => defined $licenseValueType ? $licenseValueType : undef,
			value_text => $medicaid || undef,
			value_intB => 1,
			_debug => 0
		);

	$page->schemaAction(
			'Invoice_Attribute', $command,
			parent_id => $invoiceId,
			item_name => 'Provider/Champus',
			value_type => defined $licenseValueType ? $licenseValueType : undef,
			value_text => $champus || undef,
			value_intB => 1,
			_debug => 0
		);

	$page->schemaAction(
			'Invoice_Attribute', $command,
			parent_id => $invoiceId,
			item_name => 'Provider/Workers Comp',
			value_type => defined $licenseValueType ? $licenseValueType : undef,
			value_text => $wc || undef,
			value_intB => 1,
			_debug => 0
		);
}

sub storeInsuranceInfo
{
	my ($page, $command, $invoiceId, $invoice, $mainTransData) = @_;
	
	my $textValueType = App::Universal::ATTRTYPE_TEXT;
	my $phoneValueType = App::Universal::ATTRTYPE_PHONE;
	my $dateValueType = App::Universal::ATTRTYPE_DATE;
	my $durationValueType = App::Universal::ATTRTYPE_DURATION;
	my $primaryIns = App::Universal::INSURANCE_PRIMARY;
	my $uniqPlan = App::Universal::RECORDTYPE_PERSONALCOVERAGE;

	my $ftEmployAttr = App::Universal::ATTRTYPE_EMPLOYEDFULL;		#220
	my $ptEmployAttr = App::Universal::ATTRTYPE_EMPLOYEDPART;		#221
	my $selfEmployAttr = App::Universal::ATTRTYPE_SELFEMPLOYED;		#222
	my $retiredAttr = App::Universal::ATTRTYPE_RETIRED;				#223
	my $ftStudentAttr = App::Universal::ATTRTYPE_STUDENTFULL;		#224
	my $ptStudentAttr = App::Universal::ATTRTYPE_STUDENTPART;		#225
	my $unknownAttr = App::Universal::ATTRTYPE_EMPLOYUNKNOWN;	#226

	my $clientId = $invoice->{client_id};
	my $billingId = $invoice->{billing_id};
	my $payerBillSeq = '';
	my $order = '';
	my $partyType = '';
	my $insIntId = '';
	my $billId = '';
	my $primaryPayerBillSeq = '';
	my $invoicePayers = $STMTMGR_INVOICE->getRowsAsHashList($page, STMTMGRFLAG_CACHE, 'selInvoiceBillingRecs', $invoiceId); #this query is ordered by bill_sequence
	foreach my $payer (@{$invoicePayers})
	{
		$partyType = $payer->{bill_party_type};
		$insIntId = $payer->{bill_ins_id};
		$billId = $payer->{bill_id};
		$payerBillSeq = $payer->{bill_sequence};

		next if $partyType == App::Universal::INVOICEBILLTYPE_CLIENT;	#don't want to continue because this type is a self-pay
		next if $payer->{bill_status} eq 'inactive';						#don't want to include payers that have been used already
	
		if($billId == $billingId)
		{
			$order = 'Primary';
			$primaryPayerBillSeq = $payerBillSeq;
		}

		$order = 'Secondary' if $payerBillSeq == $primaryPayerBillSeq + 1;
		$order = 'Tertiary' if $payerBillSeq == $primaryPayerBillSeq + 2;
		$order = 'Quaternary' if $payerBillSeq == $primaryPayerBillSeq + 3;


		if($partyType == App::Universal::INVOICEBILLTYPE_THIRDPARTYORG)
		{
			my $thirdPartyInsur = $STMTMGR_INSURANCE->getRowAsHash($page, STMTMGRFLAG_CACHE, 'selInsuranceData', $insIntId);
			my $thirdPartyId = $thirdPartyInsur->{guarantor_id};
			
			my $thirdPartyInfo = $STMTMGR_ORG->getRowAsHash($page, STMTMGRFLAG_NONE, 'selRegistry', $thirdPartyId);
			my $thirdPartyPhone = $STMTMGR_INSURANCE->getRowAsHash($page, STMTMGRFLAG_NONE, 'selInsurancePayerPhone', $insIntId);
			my $thirdPartyAddr = $STMTMGR_INSURANCE->getRowAsHash($page, STMTMGRFLAG_NONE, 'selInsuranceAddrWithOutColNameChanges', $insIntId);

			$page->schemaAction(
					'Invoice_Attribute', $command,
					parent_id => $invoiceId,
					item_name => 'Third-Party/Org/Name',
					value_type => defined $textValueType ? $textValueType : undef,
					value_text => $thirdPartyInfo->{name_primary} || undef,
					value_textB => $thirdPartyInfo->{org_id} || undef,
					value_int => $thirdPartyId || undef,
					value_intB => 1,
					_debug => 0
				);
		
			$page->schemaAction(
					'Invoice_Attribute', $command,
					parent_id => $invoiceId,
					item_name => 'Third-Party/Org/Phone',
					value_type => defined $phoneValueType ? $phoneValueType : undef,
					value_text => $thirdPartyPhone->{phone} || undef,
					value_intB => 1,
					_debug => 0
				);

			$page->schemaAction(
					'Invoice_Address', $command,
					parent_id => $invoiceId,
					address_name => 'Third-Party',
					line1 => $thirdPartyAddr->{line1} || undef,
					line2 => $thirdPartyAddr->{line2} || undef,
					city => $thirdPartyAddr->{city} || undef,
					state => $thirdPartyAddr->{state} || undef,
					zip => $thirdPartyAddr->{zip} || undef,
					_debug => 0
				);
		
		}
		elsif($partyType == App::Universal::INVOICEBILLTYPE_THIRDPARTYPERSON)
		{
			my $thirdPartyInsur = $STMTMGR_INSURANCE->getRowAsHash($page, STMTMGRFLAG_CACHE, 'selInsuranceData', $insIntId);
			my $thirdPartyId = $thirdPartyInsur->{guarantor_id};

			my $thirdPartyName = $STMTMGR_PERSON->getSingleValue($page, STMTMGRFLAG_NONE, 'selPersonSimpleNameById', $thirdPartyId);
			my $thirdPartyPhone = $STMTMGR_INSURANCE->getRowAsHash($page, STMTMGRFLAG_NONE, 'selInsurancePayerPhone', $insIntId);
			my $thirdPartyAddr = $STMTMGR_INSURANCE->getRowAsHash($page, STMTMGRFLAG_NONE, 'selInsuranceAddrWithOutColNameChanges', $insIntId);

			$page->schemaAction(
					'Invoice_Attribute', $command,
					parent_id => $invoiceId,
					item_name => 'Third-Party/Person/Name',
					value_type => defined $textValueType ? $textValueType : undef,
					value_text => $thirdPartyName || undef,
					value_textB => $thirdPartyId || undef,
					value_intB => 1,
					_debug => 0
				);
		
			$page->schemaAction(
					'Invoice_Attribute', $command,
					parent_id => $invoiceId,
					item_name => 'Third-Party/Person/Phone',
					value_type => defined $phoneValueType ? $phoneValueType : undef,
					value_text => $thirdPartyPhone->{phone} || undef,
					value_intB => 1,
					_debug => 0
				);

			$page->schemaAction(
					'Invoice_Address', $command,
					parent_id => $invoiceId,
					address_name => 'Third-Party',
					line1 => $thirdPartyAddr->{line1} || undef,
					line2 => $thirdPartyAddr->{line2} || undef,
					city => $thirdPartyAddr->{city} || undef,
					state => $thirdPartyAddr->{state} || undef,
					zip => $thirdPartyAddr->{zip} || undef,
					_debug => 0
				);
		
		}
		elsif($partyType == App::Universal::INVOICEBILLTYPE_THIRDPARTYINS)
		{
			my $personInsur = $STMTMGR_INSURANCE->getRowAsHash($page, STMTMGRFLAG_CACHE, 'selInsuranceForInvoiceSubmit', $insIntId);
			my $insOrgId = $personInsur->{ins_org_id};
			my $parentInsId = $personInsur->{parent_ins_id};
			my $personInsurPlanOrProd = $STMTMGR_INSURANCE->getRowAsHash($page, STMTMGRFLAG_CACHE, 'selInsuranceForInvoiceSubmit', $parentInsId);
			my $personInsurProduct = undef;
			if($personInsurPlanOrProd->{record_type} == App::Universal::RECORDTYPE_INSURANCEPLAN)
			{
				$personInsurProduct = $STMTMGR_INSURANCE->getRowAsHash($page, STMTMGRFLAG_CACHE, 'selInsuranceForInvoiceSubmit', $personInsurPlanOrProd->{parent_ins_id});
			}

			#Basic Insurance Information --------------------
			my $insOrgInfo = $STMTMGR_ORG->getRowAsHash($page, STMTMGRFLAG_NONE, 'selRegistry', $insOrgId);
			$page->schemaAction(
					'Invoice_Attribute', $command,
					parent_id => $invoiceId,
					item_name => "Insurance/$order/Name",
					value_type => defined $textValueType ? $textValueType : undef,
					value_text => $insOrgInfo->{name_primary} || undef,
					value_textB => $insOrgInfo->{org_id} || undef,
					value_int => $insOrgId || undef,
					value_intB => 1,
					_debug => 0
				);

			$page->schemaAction(
					'Invoice_Attribute', $command,
					parent_id => $invoiceId,
					item_name => "Insurance/$order/Effective Dates",
					value_type => defined $durationValueType ? $durationValueType : undef,
					value_date => $personInsur->{coverage_begin_date} || undef,
					value_dateEnd => $personInsur->{coverage_end_date} || undef,
					value_intB => 1,
					_debug => 0
				);

			$page->schemaAction(
					'Invoice_Attribute', $command,
					parent_id => $invoiceId,
					item_name => "Insurance/$order/Type",
					value_type => defined $textValueType ? $textValueType : undef,
					value_text => $personInsur->{claim_type} || undef,
					value_textB => $personInsur->{extra} || undef,
					value_intB => 1,
					_debug => 0
				);

			$page->schemaAction(
					'Invoice_Attribute', $command,
					parent_id => $invoiceId,
					item_name => "Insurance/$order/Group Number",
					value_type => defined $textValueType ? $textValueType : undef,
					value_text => $personInsur->{plan_name} || $personInsur->{product_name} || $personInsur->{group_name} || undef,
					value_textB => $personInsur->{group_number} || $personInsur->{policy_number} || undef,
					value_intB => 1,
					_debug => 0
				);

			#HMO-PPO Indicator and BCBS Plan Code --------------------
			my $ppoHmo = $STMTMGR_INSURANCE->getRowAsHash($page, STMTMGRFLAG_NONE, 'selInsuranceAttr', $parentInsId, 'HMO-PPO/Indicator');
			my $bcbsCode = $STMTMGR_INSURANCE->getRowAsHash($page, STMTMGRFLAG_NONE, 'selInsuranceAttr', $parentInsId, 'BCBS Plan Code');
			$page->schemaAction(
					'Invoice_Attribute', $command,
					parent_id => $invoiceId,
					item_name => "Insurance/$order/HMO-PPO ID",
					value_type => defined $textValueType ? $textValueType : undef,
					value_text => $ppoHmo->{value_text} || undef,
					value_intB => 1,
					_debug => 0
				);

			$page->schemaAction(
					'Invoice_Attribute', $command,
					parent_id => $invoiceId,
					item_name => "Insurance/$order/BCBS Plan Code",
					value_type => defined $textValueType ? $textValueType : undef,
					value_text => $bcbsCode->{value_text} || undef,
					value_intB => 1,
					_debug => 0
				);


			#E-Remitter Payer ID --------------------
			$page->schemaAction(
					'Invoice_Attribute', $command,
					parent_id => $invoiceId,
					item_name => "Insurance/$order/E-Remitter ID",
					value_type => defined $textValueType ? $textValueType : undef,
					value_text => $personInsurPlanOrProd->{remit_payer_id} || $personInsurProduct->{remit_payer_id},
					value_intB => 1,
					_debug => 0
				);

			#Payment Source --------------------
			my $claimType = $personInsur->{claim_type};
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

			$page->schemaAction(
					'Invoice_Attribute', $command,
					parent_id => $invoiceId,
					item_name => "Insurance/$order/Payment Source",
					value_type => defined $textValueType ? $textValueType : undef,
					value_text => $paySource || undef,
					value_intB => 1,
					_debug => 0
				);

			#Champus Information --------------------
			my $champusStatus = $STMTMGR_INSURANCE->getRowAsHash($page, STMTMGRFLAG_NONE, 'selInsuranceAttr', $parentInsId, 'Champus Status');
			my $champusBranch = $STMTMGR_INSURANCE->getRowAsHash($page, STMTMGRFLAG_NONE, 'selInsuranceAttr', $parentInsId, 'Champus Branch');
			my $champusGrade = $STMTMGR_INSURANCE->getRowAsHash($page, STMTMGRFLAG_NONE, 'selInsuranceAttr', $parentInsId, 'Champus Grade');

			$page->schemaAction(
					'Invoice_Attribute', $command,
					parent_id => $invoiceId,
					item_name => "Insurance/$order/Champus Branch",
					value_type => defined $textValueType ? $textValueType : undef,
					value_text => $champusBranch->{value_text} || undef,
					value_intB => 1,
					_debug => 0
				);

			$page->schemaAction(
					'Invoice_Attribute', $command,
					parent_id => $invoiceId,
					item_name => "Insurance/$order/Champus Status",
					value_type => defined $textValueType ? $textValueType : undef,
					value_text => $champusStatus->{value_text} || undef,
					value_intB => 1,
					_debug => 0
				);

			$page->schemaAction(
					'Invoice_Attribute', $command,
					parent_id => $invoiceId,
					item_name => "Insurance/$order/Champus Grade",
					value_type => defined $textValueType ? $textValueType : undef,
					value_text => $champusGrade->{value_text} || undef,
					value_intB => 1,
					_debug => 0
				);


			#Medigap Number  --------------------
			if($invoice->{invoice_subtype} == App::Universal::CLAIMTYPE_MEDICARE)
			{
				my $medigapNo = $STMTMGR_INSURANCE->getRowAsHash($page, STMTMGRFLAG_NONE, 'selInsuranceAttr', $personInsurProduct->{ins_internal_id} || $personInsurPlanOrProd->{ins_internal_id}, 'Medigap/Number');
				$page->schemaAction(
						'Invoice_Attribute', $command,
						parent_id => $invoiceId,
						item_name => "Insurance/$order/Medigap",
						value_type => defined $textValueType ? $textValueType : undef,
						value_text => $medigapNo->{value_text} || undef,
						value_intB => 1,
						_debug => 0
					);
			}


			#Insurance Contact Info --------------------
			my $insOrgPhone = $STMTMGR_INSURANCE->getRowAsHash($page, STMTMGRFLAG_NONE, 'selInsurancePayerPhone', $parentInsId);
			my $insOrgAddr = $STMTMGR_INSURANCE->getRowAsHash($page, STMTMGRFLAG_NONE, 'selInsuranceAddrWithOutColNameChanges', $parentInsId);

			$page->schemaAction(
					'Invoice_Attribute', $command,
					parent_id => $invoiceId,
					item_name => "Insurance/$order/Phone",
					value_type => defined $phoneValueType ? $phoneValueType : undef,
					value_text => $insOrgPhone->{phone} || undef,
					value_intB => 1,
					_debug => 0
				);

			$page->schemaAction(
					'Invoice_Address', $command,
					parent_id => $invoiceId,
					address_name => "$order Insurance",
					line1 => $insOrgAddr->{line1} || undef,
					line2 => $insOrgAddr->{line2} || undef,
					city => $insOrgAddr->{city} || undef,
					state => $insOrgAddr->{state} || undef,
					zip => $insOrgAddr->{zip} || undef,
					_debug => 0
				);

			#Relationship to Insured --------------------
			my $relToCode = $personInsur->{rel_to_insured};
			my $relToCaption = $STMTMGR_INSURANCE->getSingleValue($page, STMTMGRFLAG_NONE, 'selInsuredRelationship', $relToCode);
			$page->schemaAction(
					'Invoice_Attribute', $command,
					parent_id => $invoiceId,
					item_name => "Insurance/$order/Patient-Insured/Relationship",
					value_type => defined $textValueType ? $textValueType : undef,
					value_text => $relToCaption || undef,
					value_int => $relToCode || undef,
					value_intB => 1,
					_debug => 0
				);

			#Insured Information --------------------
			my $insuredData = $STMTMGR_PERSON->getRowAsHash($page, STMTMGRFLAG_CACHE, 'selRegistry', $personInsur->{insured_id});
			my $insuredId = $insuredData->{person_id};
			$page->schemaAction(
					'Invoice_Attribute', $command,
					parent_id => $invoiceId,
					item_name => "Insurance/$order/Insured/Name",
					value_type => defined $textValueType ? $textValueType : undef,
					value_text => $insuredData->{complete_name} || undef,
					value_textB => $insuredId || undef,
					value_intB => 1,
					_debug => 0
				);

			$page->schemaAction(
					'Invoice_Attribute', $command,
					parent_id => $invoiceId,
					item_name => "Insurance/$order/Insured/Name/Last",
					value_type => defined $textValueType ? $textValueType : undef,
					value_text => $insuredData->{name_last} || undef,
					value_textB => $insuredId || undef,
					value_intB => 1,
					_debug => 0
				);

			$page->schemaAction(
					'Invoice_Attribute', $command,
					parent_id => $invoiceId,
					item_name => "Insurance/$order/Insured/Name/First",
					value_type => defined $textValueType ? $textValueType : undef,
					value_text => $insuredData->{name_first} || undef,
					value_textB => $insuredId || undef,
					value_intB => 1,
					_debug => 0
				);

			$page->schemaAction(
					'Invoice_Attribute', $command,
					parent_id => $invoiceId,
					item_name => "Insurance/$order/Insured/Name/Middle",
					value_type => defined $textValueType ? $textValueType : undef,
					value_text => $insuredData->{name_middle} || undef,
					value_textB => $insuredId || undef,
					value_intB => 1,
					_debug => 0
				) if $insuredData->{name_middle} ne '';

			$page->schemaAction(
					'Invoice_Attribute', $command,
					parent_id => $invoiceId,
					item_name => "Insurance/$order/Insured/Personal/Marital Status",
					value_type => defined $textValueType ? $textValueType : undef,
					value_text => $insuredData->{marstat_caption} || undef,
					value_intB => 1,
					_debug => 0
				);

			$page->schemaAction(
					'Invoice_Attribute', $command,
					parent_id => $invoiceId,
					item_name => "Insurance/$order/Insured/Personal/Gender",
					value_type => defined $textValueType ? $textValueType : undef,
					value_text => $insuredData->{gender_caption} || undef,
					value_intB => 1,
					_debug => 0
				);

			$page->schemaAction(
					'Invoice_Attribute', $command,
					parent_id => $invoiceId,
					item_name => "Insurance/$order/Insured/Personal/DOB",
					value_type => defined $dateValueType ? $dateValueType : undef,
					value_date => $insuredData->{date_of_birth} || undef,
					value_intB => 1,
					_debug => 0
				);

			$page->schemaAction(
					'Invoice_Attribute', $command,
					parent_id => $invoiceId,
					item_name => "Insurance/$order/Insured/Personal/SSN",
					value_type => defined $textValueType ? $textValueType : undef,
					value_text => $insuredData->{ssn} || undef,
					value_intB => 1,
					_debug => 0
				);

			$page->schemaAction(
					'Invoice_Attribute', $command,
					parent_id => $invoiceId,
					item_name => "Insurance/$order/Insured/Member Number",
					value_type => defined $textValueType ? $textValueType : undef,
					value_text => $personInsur->{member_number} || undef,
					value_intB => 1,
					_debug => 0
				);

			#Insured's Contact Information
			my $insuredPhone = $STMTMGR_PERSON->getSingleValue($page, STMTMGRFLAG_CACHE, 'selHomePhone', $personInsur->{insured_id});
			my $insuredAddr = $STMTMGR_PERSON->getRowAsHash($page, STMTMGRFLAG_NONE, 'selHomeAddress', $personInsur->{insured_id});

			$page->schemaAction(
					'Invoice_Attribute', $command,
					parent_id => $invoiceId,
					item_name => "Insurance/$order/Insured/Contact/Home Phone",
					value_type => defined $phoneValueType ? $phoneValueType : undef,
					value_text => $insuredPhone || undef,
					value_intB => 1,
					_debug => 0
				);

			$page->schemaAction(
					'Invoice_Address', $command,
					parent_id => $invoiceId,
					address_name => "$order Insured",
					line1 => $insuredAddr->{line1} || undef,
					line2 => $insuredAddr->{line2} || undef,
					city => $insuredAddr->{city} || undef,
					state => $insuredAddr->{state} || undef,
					zip => $insuredAddr->{zip} || undef,
					_debug => 0
				);



			#Insured's Employment Info
			my $employerName = $STMTMGR_ORG->getSingleValue($page, STMTMGRFLAG_NONE, 'selOrgSimpleNameById', $personInsur->{employer_org_id});

			$page->schemaAction(
					'Invoice_Attribute', $command,
					parent_id => $invoiceId,
					item_name => "Insurance/$order/Insured/Employer/Name",
					value_type => defined $textValueType ? $textValueType : undef,
					value_text => $employerName || undef,
					value_intB => 1,
					_debug => 0
				);


			my $insuredEmployerAddr = $STMTMGR_ORG->getRowAsHash($page, STMTMGRFLAG_CACHE, 'selOrgAddressByAddrName', $personInsur->{employer_org_id}, 'Mailing');
			$page->schemaAction(
					'Invoice_Address', $command,
					parent_id => $invoiceId,
					address_name => "$order Insured Employer",
					line1 => $insuredEmployerAddr->{line1} || undef,
					line2 => $insuredEmployerAddr->{line2} || undef,
					city => $insuredEmployerAddr->{city} || undef,
					state => $insuredEmployerAddr->{state} || undef,
					zip => $insuredEmployerAddr->{zip} || undef,
					_debug => 0
				);


			##MEDICAID - RESUBMISSION CODE AND ORIGINAL REFERENCE

			#if()
			#{
			#	$page->schemaAction(
			#			'Invoice_Attribute', $command,
			#			parent_id => $invoiceId,
			#			item_name => 'Medicaid/Resubmission',
			#			value_type => defined $textValueType ? $textValueType : undef,
			#			value_text => (code)
			#			value_textB => (reference)
			#			value_intB => 1,
			#			_debug => 0
			#		);
			#}

		}
	}
}

sub createActiveProbTrans
{
	my ($page, $command, $invoiceId, $invoice, $mainTransData) = @_;
	
	my $personValueType = App::Universal::ENTITYTYPE_PERSON;
	my $transStatActive = App::Universal::TRANSSTATUS_ACTIVE;
	my $todaysStamp = $page->getTimeStamp();

	my @icdCodes = split(/\s*,\s*/, $invoice->{claim_diags});
	foreach my $icdCode (@icdCodes)
	{
		$page->schemaAction(
				'Transaction', $command,
				trans_owner_type => defined $personValueType ? $personValueType : undef,
				trans_owner_id => $invoice->{client_id} || undef,
				parent_trans_id => $mainTransData->{trans_id} || undef,
				trans_type => App::Universal::TRANSTYPEDIAG_ICD,
				trans_status => defined $transStatActive ? $transStatActive : undef,
				init_onset_date => $mainTransData->{init_onset_date} || undef,
				curr_onset_date => $mainTransData->{curr_onset_date} || undef,
				billing_facility_id => $mainTransData->{billing_facility_id} || undef,
				service_facility_id => $mainTransData->{service_facility_id} || undef,
				code => $icdCode || undef,
				provider_id => $mainTransData->{provider_id} || undef,
				care_provider_id => $mainTransData->{care_provider_id} || undef,
				trans_begin_stamp => $todaysStamp || undef,
				_debug => 0
		);
	}
}

sub customValidate
{
	my ($self, $page) = @_;

	my $servicetype = $page->field('servtype');
	my $cptCode = $page->field('procedure');
	my $modCode = $page->field('procmodifier');
	my $use_fee = $page->field('use_fee');

	my @fsIntIds = ();
	my @feeSchedules = split(/\s*,\s*/, $page->field('fee_schedules'));
	foreach (@feeSchedules)
	{
		my $catalog = $STMTMGR_CATALOG->getRowAsHash($page, STMTMGRFLAG_NONE, 'selInternalCatalogIdByIdType',
					$page->session('org_internal_id'), $_, App::Universal::CATALOGTYPE_FEESCHEDULE);
		
		push(@fsIntIds, $catalog->{internal_catalog_id});
		#$page->addError("FS Names: $_");
		#$page->addError("FS Ids: $catalog->{internal_catalog_id}");
	}

	$page->field('fee_schedules_catalog_ids', join(',', @fsIntIds));
	
	my $svc_type = App::IntelliCode::getSvcType($page, $cptCode, $modCode, \@fsIntIds);
	my $count_type = scalar(@$svc_type);
	my $count=0;	
	unless ($servicetype)
	{
		if ($count_type==1||$use_fee ne '')
		{
			foreach(@$svc_type)
			{
				#Store code_type and service type in hidden fields
				if($count_type==1||$use_fee eq $count)
				{
					$page->field("servtype",$_->[1]); 	
					$page->field('code_type',$_->[3]);
				}
			 	$count++
			}
		}
		elsif ($count_type>1)
		{
			my $html_svc = $self->getMultiSvcTypesHtml($page,$cptCode, $svc_type);
			#Use the service place to send error message because service type field is hidden
			my $type = $self->getField('cptModfField')->{fields}->[0];
			$type->invalidate($page, $html_svc);
		}
		else
		{
			my $type = $self->getField('cptModfField')->{fields}->[0];
			$type->invalidate($page,"Unable to find Code '$cptCode' in fee schedule(s) " . join ",",@fsIntIds);
		}
	}
	#GET ITEM COST FROM FEE SCHEDULE
	$count=0;
	if (! $page->field('proccharge') && ! $page->field('alt_cost'))
	{
		my $unitCostField = $self->getField('proc_charge_fields')->{fields}->[0];				
		my $fsResults = App::IntelliCode::getItemCost($page, $cptCode, $modCode, \@fsIntIds);
		my $resultCount = scalar(@$fsResults);
		if($resultCount == 0)
		{
			$unitCostField->invalidate($page, 'No unit cost was found');
		}
		elsif($resultCount == 1 || $use_fee ne '')
		{
			foreach (@$fsResults)
			{
				if ($count_type==1 || $use_fee eq $count)
				{
					my $unitCost = $_->[1];
					$page->field('proccharge', $unitCost);
				
					my $isFfs = $_->[2];
					$page->field('data_num_a', $isFfs);
				}
				$count++;
			}
			
		}
		else
		{
			my @costs = ();
			foreach (@$fsResults)
			{
				push(@costs, $_->[1]);
			}

			$self->updateFieldFlags('alt_cost', FLDFLAG_INVISIBLE, 0);
			$self->updateFieldFlags('units_emg_fields', FLDFLAG_INVISIBLE, 0);
			$self->updateFieldFlags('proc_charge_fields', FLDFLAG_INVISIBLE, 1);

			#my $costList = join(';', @costs);
			#$self->getField('alt_cost')->{selOptions} = "$costList";
			
			my $field = $self->getField('alt_cost');
			
			#my $html = $self->getMultiPricesHtml($page, $fsResults);
			#$field->invalidate($page, $html);
		}
	}
}



sub getMultiSvcTypesHtml
{
	my ($self, $page,$code,  $fsResults) = @_;

	my $html = qq{Multiple fee schedule have code '$code'.  Please select a fee schedule to use for this item.};
	my $count=0;
	foreach (@$fsResults)
	{
		my $svc_type=$_->[1];
		#my $svc_name=$_->[4];
		#Use the above line if you want to see the fee schedule name instead of the fee schedule number
		my $svc_name=$_->[0];
		$html .= qq{
			<input onClick="document.dialog._f_use_fee.value=this.value" 
				type=radio name='_f_multi_svc_type' value=$count>$svc_name
		};	
		$count++;
	}

	return $html;
}


sub getMultiPricesHtml
{
	my ($self, $page, $fsResults) = @_;

	my $html = qq{Multiple prices found.  Please select a price for this item.};
	
	foreach (@$fsResults)
	{
		my $cost = sprintf("%.2f", $_->[1]);
		$html .= qq{
			<input onClick="document.dialog._f_alt_cost.value=this.value" 
				type=radio name='_f_multi_price' value=$cost>\$$cost
		};
	}

	return $html;
}

sub execute
{
	my ($self, $page, $command, $flags) = @_;
	my $invoiceId = $page->param('invoice_id');

	if($command eq 'add' || $command eq 'update')
	{
		execute_addOrUpdate($self, $page, $command, $flags);
		$self->handlePostExecute($page, $command, $flags);
	}
	else
	{
		voidProcedure($self, $page, $command, $flags);
		$page->redirect("/invoice/$invoiceId/summary");
	}
}

sub execute_addOrUpdate
{
	my ($self, $page, $command, $flags) = @_;

	my $sessOrgIntId = $page->session('org_internal_id');
	my $sessUser = $page->session('user_id');
	my $todaysDate = UnixDate('today', $page->defaultUnixDateFormat());
	my $invoiceId = $page->param('invoice_id');
	my $itemId = $page->param('item_id');
	my $codeType = $page->field('code_type');

	my $itemType = App::Universal::INVOICEITEMTYPE_SERVICE;
	if($page->field('lab_indicator'))
	{
		$itemType = App::Universal::INVOICEITEMTYPE_LAB;
	}

	my $comments = $page->field('comments');
	my $emg = $page->field('emg') == 1 ? 1 : 0;

	my $unitCost = $page->field('proccharge') || $page->field('alt_cost');
	my $extCost = $unitCost * $page->field('procunits');

	my @relDiags = $page->field('procdiags');					#diags for this particular procedure
	my @claimDiags = split(/\s*,\s*/, $page->field('claim_diags'));		#all diags for a claim
	#my @hcpcsCode = split(/\s*,\s*/, $page->field('hcpcs'));
	my @cptCodes = split(/\s*,\s*/, $page->field('procedure'));		#there will always be only one value in this array

	## run increment usage in intellicode
	#App::IntelliCode::incrementUsage($page, 'Cpt', \@cptCodes, $sessUser, $sessOrgIntId);
	#App::IntelliCode::incrementUsage($page, 'Hcpcs', \@hcpcsCode, $sessUser, $sessOrgIntId);

	## figure out diag code pointers
	my @diagCodePointers = ();
	my $claimDiagCount = @claimDiags;
	foreach my $relDiag (@relDiags)
	{
		foreach my $claimDiagNum (1..$claimDiagCount)
		{
			if($relDiag eq $claimDiags[$claimDiagNum-1])
			{
				push(@diagCodePointers, $claimDiagNum);
			}
		}
	}

	## get short name for cpt code
	my $cptCode = $page->field('procedure');
	my $cptShortName = $STMTMGR_CATALOG->getRowAsHash($page, STMTMGRFLAG_CACHE, 'selGenericCPTCode', $cptCode);

	#get service place based on service facility, then convert code to its id
	my $mainTransId = $STMTMGR_INVOICE->getSingleValue($page, STMTMGRFLAG_NONE, 'selInvoiceMainTransById', $invoiceId);
	my $mainTransData = $STMTMGR_TRANSACTION->getRowAsHash($page, STMTMGRFLAG_NONE, 'selTransCreateClaim', $mainTransId);
	my $servPlace = $STMTMGR_ORG->getRowAsHash($page, STMTMGRFLAG_NONE, 'selAttribute', $mainTransData->{service_facility_id}, 'HCFA Service Place');
	my $servPlaceId = $STMTMGR_CATALOG->getSingleValue($page, STMTMGRFLAG_CACHE, 'selGenericServicePlaceByAbbr', $servPlace->{value_text});

	#convert service type code to its id
	my $servType = $page->field('servtype');
	my $servTypeId = $STMTMGR_CATALOG->getSingleValue($page, STMTMGRFLAG_CACHE, 'selGenericServiceTypeByAbbr', $servType);

	$page->schemaAction(
			'Invoice_Item', $command,
			item_id => $itemId || undef,
			parent_id => $invoiceId,
			item_type => defined $itemType ? $itemType : undef,
			code => $cptCode || undef,
			code_type => $codeType || undef,
			caption => $cptShortName->{name} || undef,
			modifier => $page->field('procmodifier') || undef,
			rel_diags => join(', ', @relDiags) || undef,
			unit_cost => $unitCost || undef,
			quantity => $page->field('procunits') || undef,
			extended_cost => $extCost || undef,
			emergency => defined $emg ? $emg : undef,
			comments => $comments || undef,
			hcfa_service_place => defined $servPlaceId ? $servPlaceId : undef,
			hcfa_service_type => defined $servTypeId ? $servTypeId : undef,
			service_begin_date => $page->field('service_begin_date') || undef,
			service_end_date => $page->field('service_end_date') || undef,
			data_text_a => join(', ', @diagCodePointers) || undef,
			data_num_a => $page->field('data_num_a') || undef,
			_debug => 0
		);




	## ADD HISTORY ATTRIBUTE

	my $action = '';
	$action = 'Added' if $command eq 'add';
	$action = 'Updated' if $command eq 'update';

	$page->schemaAction(
			'Invoice_Attribute', 'add',
			parent_id => $invoiceId,
			item_name => 'Invoice/History/Item',
			value_type => App::Universal::ATTRTYPE_HISTORY,
			value_text => "$action $cptCode",
			value_textB => $comments || undef,
			value_date => $todaysDate || undef,
			_debug => 0
	);


	## UPDATE FEE SCHEDULES ATTRIBUTE
	if(my $feeSchedItemId = $page->field('fee_schedules_item_id'))
	{
		$page->schemaAction(
				'Invoice_Attribute', 'update',
				item_id => $feeSchedItemId,
				value_text => $page->field('fee_schedules_catalog_ids') || undef,
				value_textB => $page->field('fee_schedules') || undef,
				_debug => 0
		);
	}
}

sub voidProcedure
{
	my ($self, $page, $command, $flags) = @_;

	my $sessUser = $page->session('user_id');
	my $todaysDate = UnixDate('today', $page->defaultUnixDateFormat());
	my $invoiceId = $page->param('invoice_id');
	my $itemId = $page->param('item_id');
	my $invItem = $STMTMGR_INVOICE->getRowAsHash($page, STMTMGRFLAG_CACHE, 'selInvoiceItem', $itemId);

	my $voidItemType = App::Universal::INVOICEITEMTYPE_VOID;
	my $extCost = 0 - $invItem->{extended_cost};
	my $emg = $invItem->{emergency};
	my $cptCode = $invItem->{code};
	my $servPlace = $invItem->{hcfa_service_place};
	my $servType = $invItem->{hcfa_service_type};

	my $voidItemId = $page->schemaAction(
			'Invoice_Item', 'add',
			parent_item_id => $itemId || undef,
			parent_id => $invoiceId,
			item_type => defined $voidItemType ? $voidItemType : undef,
			flags => $invItem->{flags} || undef,
			code => $cptCode || undef,
			code_type => $invItem->{code_type} || undef,
			caption => $invItem->{caption} || undef,
			modifier => $invItem->{modifier} || undef,
			rel_diags => $invItem->{rel_diags} || undef,
			unit_cost => $invItem->{unit_cost} || undef,
			quantity => $invItem->{quantity} || undef,
			extended_cost => defined $extCost ? $extCost : undef,
			emergency => defined $emg ? $emg : undef,
			hcfa_service_place => defined $servPlace ? $servPlace : undef,
			hcfa_service_type => defined $servType ? $servType : undef,
			service_begin_date => $invItem->{service_begin_date} || undef,
			service_end_date => $invItem->{service_end_date} || undef,
			data_text_a => $invItem->{data_text_a} || undef,
			data_num_a => $invItem->{data_num_a} || undef,
			#data_num_b => $invItem->{data_num_b} || undef,
			_debug => 0
		);

	$page->schemaAction(
			'Invoice_Item', 'update',
			item_id => $itemId || undef,
			data_text_b => 'void',
			_debug => 0
		);



	## ADD HISTORY ATTRIBUTE
	$page->schemaAction(
			'Invoice_Attribute', 'add',
			parent_id => $invoiceId,
			item_name => 'Invoice/History/Item',
			value_type => App::Universal::ATTRTYPE_HISTORY,
			value_text => "Voided $cptCode",
			#value_textB => $comments || undef,
			value_date => $todaysDate || undef,
			_debug => 0
	);
}

1;
