##############################################################################
package App::Statements::Report::Billing;
##############################################################################

use strict;
use Exporter;
use DBI::StatementManager;
use App::Universal;

use vars qw(@ISA @EXPORT $STMTMGR_REPORT_BILLING $PUBLISH_DEFN
);
@ISA    = qw(Exporter DBI::StatementManager);
@EXPORT = qw($STMTMGR_REPORT_BILLING);

my $typeOrg = App::Universal::ENTITYTYPE_ORG;


$STMTMGR_REPORT_BILLING = new App::Statements::Report::Billing(

	'sel_payers' => {
		_stmtFmt => qq{
			select Claim_Type.caption as payer, count(Claim_Type.id) as count
			from Transaction, Claim_Type, Invoice
			where Invoice.owner_id = ?
				and Invoice.owner_type = $typeOrg
				and Invoice.invoice_date between to_date(? || ' 12:00 AM', '$SQLSTMT_DEFAULTSTAMPFORMAT')
					and to_date(? || ' 11:59 PM', '$SQLSTMT_DEFAULTSTAMPFORMAT')
				and Transaction.trans_id = Invoice.main_transaction
				and Claim_Type.id = Transaction.bill_type
			group by Claim_Type.caption
		},
		publishDefn => 	{
			columnDefn =>
				[
					{head => 'Payer', url => q{javascript:doActionPopup('#hrefSelfPopup#&detail=payer&payer=#&{?}#')}, hint => 'View Details' },
					{head => 'Count', dAlign => 'right'},
				],
		},
	},

	'sel_detail_payers' => {
		_stmtFmt => qq{
			select Claim_Type.caption as payer, invoice_id, invoice_date, client_id,
				provider_id, Transaction_Status.caption as status, total_cost, total_adjust, simple_name
			from Claim_Type, Transaction_Status, Transaction, Invoice, Person
			where Invoice.owner_id = ?
				and Invoice.owner_type = $typeOrg
				and Invoice.invoice_date between to_date(? || ' 12:00 AM', '$SQLSTMT_DEFAULTSTAMPFORMAT')
					and to_date(? || ' 11:59 PM', '$SQLSTMT_DEFAULTSTAMPFORMAT')
				and Transaction.trans_id = Invoice.main_transaction
				and Claim_Type.id = Transaction.bill_type
				and Claim_Type.caption = ?
				and Transaction_Status.id = Transaction.trans_status
				and client_id = person_id
		},
		publishDefn => 	{
			columnDefn =>
				[
					{colIdx => 0, head => 'Payer'},
					{colIdx => 1, head => 'Invoice'},
					{colIdx => 2, head => 'Date'},
					{colIdx => 3, head => 'Patient', dataFmt => '#8# <A HREF = "/person/#3#/account">#3#</A>'},
					{colIdx => 4, head => 'Provider'},
					{colIdx => 5, head => 'Status'},
					{colIdx => 6, head => 'Total cost', dformat => 'currency', dAlign => 'right'},
					{colIdx => 7, head => 'Total adjust', dformat => 'currency', dAlign => 'right'},
				],
		},
	},

	'sel_payersByInsurance' => {
		_stmtFmt => qq{
			select Insurance.ins_org_id as insurance, count(Insurance.ins_org_id) as count
			from Insurance, Invoice
			where Insurance.ins_org_id = ?
				and Invoice.invoice_date between to_date(? || ' 12:00 AM', '$SQLSTMT_DEFAULTSTAMPFORMAT')
					and to_date(? || ' 11:59 PM', '$SQLSTMT_DEFAULTSTAMPFORMAT')
				and Insurance.guarantor_type = $typeOrg
				and Invoice.owner_type = $typeOrg
				and Invoice.owner_id = Insurance.ins_org_id
			group by Insurance.ins_org_id
		},
		publishDefn => 	{
			columnDefn =>
				[
					{head => 'Insurance', url => q{javascript:doActionPopup('#hrefSelfPopup#&detail=insurance&insurance=#&{?}#')}, hint => 'View Details' },
					{head => 'Count', dAlign => 'right'},
				],
		},
	},

	'sel_detail_insurance' => {
		_stmtFmt => qq{
			select Insurance.ins_org_id as payer, invoice.invoice_id, invoice_date, client_id, bill_to_id,
				provider_id, Transaction_Status.caption as status, total_cost, total_adjust, simple_name
			from Insurance, Transaction_Status, Transaction, Invoice, Person, invoice_billing ib
			where Invoice.owner_id = ?
				and Invoice.owner_type = $typeOrg
				and Invoice.invoice_date between to_date(? || ' 12:00 AM', '$SQLSTMT_DEFAULTSTAMPFORMAT')
					and to_date(? || ' 11:59 PM', '$SQLSTMT_DEFAULTSTAMPFORMAT')
				and Transaction.trans_id = Invoice.main_transaction
				and Transaction_Status.id = Transaction.trans_status
				--and Insurance.ins_internal_id = Invoice.ins_id
				and Insurance.ins_internal_id = ib.bill_ins_id
				and invoice.billing_id = ib.bill_id
				and Insurance.ins_org_id  = ?
				and Invoice.client_id = Person.person_id
		},
		publishDefn => 	{
			columnDefn =>
				[
					{colIdx => 0, head => 'Insurance'},
					{colIdx => 1, head => 'Invoice'},
					{colIdx => 2, head => 'Date'},
					{colIdx => 3, head => 'Patient', dataFmt => '#9# <A HREF = "/person/#3#/account">#3#</A>'},
					{colIdx => 4, head => 'Bill to'},
					{colIdx => 5, head => 'Provider'},
					{colIdx => 6, head => 'Status'},
					{colIdx => 7, head => 'Total cost', dformat => 'currency', dAlign => 'right'},
					{colIdx => 8, head => 'Total adjust', dformat => 'currency', dAlign => 'right'},
				],
		},
	},

	'sel_earningsFromItem_Adjust' => {
		_stmtFmt => qq{
			--select payer_id as payer, sum(plan_paid) as earning
			select org_id as payer, sum(plan_paid) as earning			
			from Invoice_Item_Adjust, Invoice_Item, Invoice, org o
			where Invoice.invoice_date between to_date(? || ' 12:00 AM', '$SQLSTMT_DEFAULTSTAMPFORMAT')
					and to_date(? || ' 11:59 PM', '$SQLSTMT_DEFAULTSTAMPFORMAT')
				and Invoice.owner_id = ?
				and Invoice.owner_type = $typeOrg
				and Invoice_Item.parent_id = Invoice.invoice_id
				and Invoice_Item_Adjust.parent_id = Invoice_Item.item_id
				and Invoice_Item_Adjust.payer_type = 1
				and o.org_internal_id = payer_id
			--group by payer_id
			group by org_id
			UNION
			select 'Others' as payer_id, sum(total_cost) as earning
			from Invoice_Item_Adjust, Invoice_Item, Invoice
			where Invoice.invoice_date between to_date(? || ' 12:00 AM', '$SQLSTMT_DEFAULTSTAMPFORMAT')
					and to_date(? || ' 11:59 PM', '$SQLSTMT_DEFAULTSTAMPFORMAT')
				and Invoice.owner_id = ?
				and Invoice.owner_type = $typeOrg
				and Invoice_Item.parent_id = Invoice.invoice_id
				and Invoice_Item_Adjust.parent_id = Invoice_Item.item_id
				and Invoice_Item_Adjust.payer_type = 0
			group by payer_id
		},
		publishDefn => 	{
			columnDefn =>
				[
					{head => 'Payer', url => q{javascript:doActionPopup('#hrefSelfPopup#&detail=earning&insurance=#&{?}#')}, hint => 'View Details' },
					{head => 'Earning', dAlign => 'right', dformat => 'currency'},
				],
		},
	},

	'sel_proceduresFromInvoice_Item' => {
		_stmtFmt => qq{
			select code as procedure, count(code) as count
			from Invoice_Item, Invoice
			where code is NOT NULL
				and Invoice.invoice_date between to_date(? || ' 12:00 AM', '$SQLSTMT_DEFAULTSTAMPFORMAT')
					and to_date(? || ' 11:59 PM', '$SQLSTMT_DEFAULTSTAMPFORMAT')
				and Invoice.owner_id = ?
				and Invoice.owner_type = $typeOrg
				and Invoice_Item.parent_id = Invoice.invoice_id
			group by code
		},
		publishDefn => 	{
			columnDefn =>
				[
					{head => 'Procedure', url => q{javascript:doActionPopup('#hrefSelfPopup#&detail=cpt&code=#&{?}#')}, hint => 'View Details' },
					{head => 'Count', dAlign => 'right'},
				],
		},
	},

	'sel_detailProcedures' => {
		_stmtFmt => qq{
			select Invoice_Item.code as procedure, Invoice_Item.modifier, invoice_id, invoice_date,
				client_id, provider_id, simple_name
			from Transaction, Invoice_Item, Invoice, Person
			where Invoice_Item.code is NOT NULL
				and Invoice.owner_id = ?
				and Invoice.owner_type = $typeOrg
				and Invoice.invoice_date between to_date(? || ' 12:00 AM', '$SQLSTMT_DEFAULTSTAMPFORMAT')
					and to_date(? || ' 11:59 PM', '$SQLSTMT_DEFAULTSTAMPFORMAT')
				and Invoice_Item.parent_id = Invoice.invoice_id
				and Invoice_Item.code = ?
				and Transaction.trans_id = Invoice.main_transaction
				and Invoice.client_id = Person.person_id
		},
		publishDefn => 	{
			columnDefn =>
				[
					{colIdx => 0, head => 'Procedure'},
					{colIdx => 1, head => 'Modifier'},
					{colIdx => 2, head => 'Invoice'},
					{colIdx => 3, head => 'Date'},
					{colIdx => 4, head => 'Patient', dataFmt => '#6# <A HREF = "/person/#4#/account">#4#</A>'},
					{colIdx => 5, head => 'Provider'},
				],
		},		
	},

	'sel_diagsFromInvoice_Item' => qq{
		select rel_diags as Diagnosis
		from Invoice_Item, Invoice
		where rel_diags is NOT NULL
			and Invoice.invoice_date between to_date(? || ' 12:00 AM', '$SQLSTMT_DEFAULTSTAMPFORMAT')
				and to_date(? || ' 11:59 PM', '$SQLSTMT_DEFAULTSTAMPFORMAT')
			and Invoice.owner_id = ?
			and Invoice.owner_type = $typeOrg
			and Invoice_Item.parent_id = Invoice.invoice_id
	},

	'sel_earningsByInsurance' => qq{
		select Insurance.ins_org_id as insurance, sum(total_cost) as earning
		from Insurance, Invoice
		where bill_to_type = 1
			and Insurance.ins_internal_id = Invoice.ins_id
		group by Insurance.ins_org_id
	},

);

$PUBLISH_DEFN =
{
	columnDefn =>
	[
		{head => 'Link',  dataFmt => '#0#',  url => q{javascript:doActionPopup('/reportDetails/#&{?}#')}, hint => 'View Details' },
		{head => 'Count', dataFmt => '#1#', dAlign => 'right'},
	],
};


1;

