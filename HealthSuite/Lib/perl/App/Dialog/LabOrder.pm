##############################################################################
package App::Dialog::LabOrder;
##############################################################################

use strict;
use DBI::StatementManager;
use App::Statements::Catalog;
use App::Statements::Person;
use App::Statements::Org;
use Carp;
use CGI::Dialog;
use CGI::Validator::Field;
use App::Dialog::Field::Person;
use App::Statements::LabTest;

use Date::Manip;
use Text::Abbrev;
use App::Universal;

use vars qw(@ISA %RESOURCE_MAP %PROCENTRYABBREV %RESOURCE_MAP %ITEMTOFIELDMAP %CODE_TYPE_MAP);
@ISA = qw(CGI::Dialog);

%RESOURCE_MAP = (
	'lab-order' => {_arl_add => ['org_id'],
	_arl_update => ['lab_order_id']},
);


sub new
{
	my ($self, $command) = CGI::Dialog::new(@_, id => 'catalog', heading => '$Command Ancillary Test');

	my $schema = $self->{schema};

	delete $self->{schema};  # make sure we don't store this!

	croak 'schema parameter required' unless $schema;

	$self->addContent(

		new CGI::Dialog::Field( caption => 'Lab Company', preHtml=>'<B>' , postHtml=>'</B>', name => 'lab_name', type=>'text',options=>FLDFLAG_READONLY |FLDFLAG_REQUIRED ),
		new App::Dialog::Field::Person::ID(
						types => ['Patient'],
						name => 'person_id', 
						caption => 'Patient ID',
						options => FLDFLAG_REQUIRED),
		new App::Dialog::Field::Person::ID(
						name => 'provider_id', 
						caption => 'Ordering Provider ID',
						types => ['Physician'],
						incSimpleName=>1,
						options => FLDFLAG_REQUIRED),								
		new CGI::Dialog::Field( name => 'org_internal_id', type=>'hidden'),		
		new CGI::Dialog::Field( name => 'org_id', type=>'hidden'),						
#		new CGI::Dialog::Field( caption => 'Location', name => 'location', type=>'text',options=>FLDFLAG_REQUIRED,
#		findPopup => "/lookup/lablocation?search_type=#field.org_internal_id#",
#		findPopupControlField => '_f_org_internal_id'),		

                new CGI::Dialog::Field(caption => 'Ancillary Location',
                        name => 'location',
                        fKeyStmtMgr => $STMTMGR_ORG,
                        fKeyStmt => 'selAddresses',
                        fKeyDisplayCol => 1,
                        fKeyValueCol => 3,
                        options => FLDFLAG_REQUIRED,
		fKeyStmtBindFields=>['org_internal_id']
                ),
		new CGI::Dialog::MultiField(caption =>'Date/Time Ordered', name => 'order_date_time',
			fields => [
					new CGI::Dialog::Field( caption => 'Date Ordered', name => 'order_date', type=>'date'),
					new CGI::Dialog::Field( caption => 'Time Ordered', name => 'order_time', type=>'time'),
				 ]),

		new CGI::Dialog::MultiField(caption =>'Date/Time to be Done', name => 'done_date_time',
			fields => [
					new CGI::Dialog::Field( caption => 'Date to Done', name => 'done_date', type=>'date',defaultValue=>''),
					new CGI::Dialog::Field( caption => 'Time Ordered', type=>'time',name => 'done_time', ),
				 ]),
		new CGI::Dialog::Field( caption => 'Diagnosis', name => 'icd9', type=>'text',size=>'30',
			findPopup => '/lookup/icd',
			findPopupAppendValue=>','),	,
		new CGI::Dialog::Field(
						name => 'lab_order_id',
						type => 'hidden',
					),		
	);

	$self->{activityLog} =
	{
		scope =>'offering_catalog',
		key => "#field.catalog_id#",
		data => "Order Entry"
	};
	$self->addFooter(new CGI::Dialog::Buttons( cancelUrl => $self->{cancelUrl} || undef));

	return $self;
}




sub makeStateChanges
{
	my ($self, $page, $command, $activeExecMode, $dlgFlags) = @_;
	$self->SUPER::makeStateChanges($page, $command, $activeExecMode, $dlgFlags);
	my $isNurse = grep {$_ eq 'Nurse'} @{$page->session('categories')};
	my $isPhysician = grep {$_ eq 'Physician'} @{$page->session('categories')};
	my $orgData;
	#Get Org Internal ID 
	if ($command eq 'add')
	{
		$orgData = $STMTMGR_ORG->getRowAsHash($page, STMTMGRFLAG_NONE, 'selOrg', $page->session('org_internal_id'), $page->param('org_id')||undef);		
	}
	else
	{
		$orgData = $STMTMGR_LAB_TEST->getRowAsHash($page, STMTMGRFLAG_NONE, 'selLabOrderByID', $page->param('lab_order_id')||undef);		
	};
	
	
	#Get All Catalogs
	my $catalogData =$STMTMGR_CATALOG->getRowsAsHashList($page,STMTMGRFLAG_NONE,'selCatalogByOrgIdType',$orgData->{org_internal_id},5);
	foreach (@$catalogData)
	{
		$self->addContent(
			new CGI::Dialog::Field(
				name =>  $_->{internal_catalog_id},
				style => 'multicheck',
				type => 'select',
				caption => '',
				#multiDualCaptionLeft => 'Available Other',
				#multiDualCaptionRight => 'Selected Other',
				size => '5',
				fKeyStmtMgr => $STMTMGR_LAB_TEST,
				fKeyStmt => 'selTestItems',
				fKeyStmtBindFields => $_->{internal_catalog_id},
				caption=>"$_->{caption}",
			),		
		);
	}
	$self->addContent(
	
			new CGI::Dialog::MultiField(caption =>'Comments to Lab/Patient', name => 'comments',
				fields => [		
			new CGI::Dialog::Field(caption => 'Comments to Lab', rows=>2,name => 'lab_comments', type=>'memo'),		
			new CGI::Dialog::Field(caption => 'Comments to Patient',rows=>2, name => 'patient_comments', type=>'memo'),			
			]),		
			new CGI::Dialog::Field(type => 'enum',style=>'radio',
				defaultValue=>'0', 
				enum=>'Lab_Order_Priority', 
				name => 'priority', 
				caption => 'Priority',
				),	
			new App::Dialog::Field::Person::ID(name => 'result_id', caption => 'Call Result to'),												
	
			new CGI::Dialog::MultiField(caption =>'Instructions to Patient', name => 'ins_patient_comm',
			fields => [		
			new CGI::Dialog::Field(caption => 'Instructions to Patient',size=>60, name => 'ins_patient', type=>'text'),	
			new CGI::Dialog::Field(type => 'enum',style=>'radio',
				defaultValue=>'0',
				enum=>'Lab_Order_Transmission',
				name => 'comm', 
				caption => 'Priority',
				),		
		])
		);
};	
sub populateData_add
{
	my ($self, $page, $command, $flags) = @_;
	$page->field('person_id',$page->param('person_id'));	
	$page->field('org_id',$page->param('org_id'));	
	$page->field('org_internal_id',$page->param('org_id'));		
	my $orgData = $STMTMGR_ORG->getRowAsHash($page, STMTMGRFLAG_NONE, 'selOrg', $page->session('org_internal_id'), $page->param('org_id')||undef);	
	$page->field('org_internal_id',$orgData->{org_internal_id});	
	$page->field('lab_name',$orgData->{name_primary});	
	$page->field('order_time',UnixDate('now', '%I:%M %p'));
	
	my $isPhysician = grep {$_ eq 'Physician'} @{$page->session('categories')};
	if($isPhysician)
	{
		$page->field('provider_id',$page->session('person_id'));
	}
	else
	{	#Try and get primary physician for patient
		my $phy =$STMTMGR_PERSON->getRowAsHash($page, STMTMGRFLAG_NONE,'selPrimaryPhysicianOrProvider',$page->field('person_id'));
		$page->field('provider_id',$phy->{value_text});
	}
}

sub populateData_update
{
	my ($self, $page, $command, $activeExecMode, $flags) = @_;
	
	my $labData = $STMTMGR_LAB_TEST->getRowAsHash($page, STMTMGRFLAG_NONE, 'selLabOrderByID', $page->param('lab_order_id')||undef);		
	$page->field('location',$labData->{location_address_id});	
	$page->field('person_id',$labData->{person_id});	
	$page->field('org_internal_id',$labData->{lab_internal_id});		
	$page->field('lab_name',$labData->{name_primary});	
	$page->field('icd9',$labData->{icd});
	$page->field('provider_id',$labData->{provider_id});
	$page->field('lab_comments',$labData->{lab_comments});
	$page->field('patient_comments',$labData->{patient_comments});
	$page->field('ins_patient',$labData->{instructions});
	$page->field('result_id',$labData->{result_id});	
	$page->field('comm',$labData->{communication});		
	$page->field('priority',$labData->{priority});		
	$page->field('lab_order_id',$page->param('lab_order_id'));
	$page->field('org_id',$labData->{org_id});
	$page->field('order_date',$labData->{date_order});
	$page->field('done_date',$labData->{date_done});
	$page->field('order_time',$labData->{order_time}) if $labData->{order_time};
	$page->field('done_time',$labData->{done_time}) if $labData->{done_time};	
	
	my %value=();
	#Get Org ID Value 
	#Get Lab Data	
	#Get Lab Catalogs
	my $catalogData =$STMTMGR_LAB_TEST->getRowsAsHashList($page,STMTMGRFLAG_NONE,'selSelectTestByParentId',$page->field('lab_order_id'));
	foreach my $catalog (@$catalogData)
	{		
		
 		if(my $array = $value{$catalog->{catalog_id}})
 		{
			push(@$array, $catalog->{test_entry_id}); 			
 		}
 		else
 		{
 			$value{$catalog->{catalog_id}} = [$catalog->{test_entry_id}];
 		}
 		my $data = $value{$catalog->{catalog_id}} ;
	};
	foreach my $key (keys %value)
	{
		my $line = $value{$key};
		$page->field($key,@$line); 
	};
}
sub populateData_remove
{
	populateData_update(@_);
}

sub customValidate
{
	my ($self, $page) = @_;
	
	#Check Make Sure Address  belong to this ORG
	
}

sub execute
{
	my ($self, $page, $command, $flags) = @_;
	my $patientId = $page->field('person_id');
	my $providerId = $page->field('provider_id');
	my $labInternalId = $page->field('org_internal_id');	
	my $address_id = $page->field('location');
	my $dateOrder = $page->field('order_date') . $page->field('order_time');
	my $dateDone = $page->field('done_date') . $page->field('done_time');
	my $icd9 = $page->field('icd9');
	my $labComments = $page->field('lab_comments');
	my $patComments = $page->field('patient_comments');	
	my $priority = $page->field('priority');
	my $comm = $page->field('comm');	
	my $ins = $page->field('ins_patient');
	my $resultId = $page->field('result_id');
	my $orderId = $page->field('lab_order_id');
	#Create Lab Order Record	
	my $labOrderId=$page->schemaAction (
		'Person_Lab_Order', $command,
		lab_order_id=>$orderId ,
		person_id => $patientId,
		lab_internal_id => $labInternalId,
		date_done => $dateDone,
		date_order => $dateOrder,
		icd => $icd9,
		lab_comments  => $labComments,
		patient_comments => $patComments,
		priority => $priority, 
		communication => $comm,
		instructions=>$ins,
		provider_id =>$providerId,
		result_id => $resultId,		
		lab_order_status=>1,
		org_internal_id =>$page->session('org_internal_id'),
		location_address_id => $address_id,
	);	

	$labOrderId = $orderId ? $orderId : $labOrderId; 
	
	#Delete All Lab Entries and Re_Create
	my $test=$STMTMGR_LAB_TEST->execute($page,STMTMGRFLAG_NONE,'delLabEntriesByOrderID',$labOrderId);

	
	#Get Lab Catalogs
	my $catalogData =$STMTMGR_CATALOG->getRowsAsHashList($page,STMTMGRFLAG_NONE,'selCatalogByOrgIdType',$page->field('org_internal_id'),5);
	foreach my $catalog (@$catalogData)
	{
		my @data = $page->field($catalog->{internal_catalog_id});
		foreach (@data)
		{
			$page->schemaAction(
			'Lab_Order_Entry','add',
			parent_id =>$labOrderId,
			test_entry_id=>$_,);				
		
		}		
	}
	$self->handlePostExecute($page, $command, $flags, undef);
	return '';
}


